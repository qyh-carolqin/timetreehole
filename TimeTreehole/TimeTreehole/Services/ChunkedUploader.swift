import Foundation
import CryptoKit

// MARK: - 真·分片上传 + 断点续传

/// 把整段录音切成固定大小的分片（默认 1MB）逐片上传：
/// - 单片失败只重传该片（自带退避重试），不再整段重来 → 根治慢链路整段超时丢种子。
/// - 上传中途中断 / 用户重试时，用服务端 `status` 比对已传分片，从断点继续，
///   避免跨境慢链路上重复传输已成功的片段。
/// - 续传进度以「音频内容 SHA256」为 key 持久化在 UserDefaults：同一段录音
///   （audioData 不变）重试时命中同一 key → 断点续传；重新录音则开启新会话。
@MainActor
final class ChunkedUploader {

    static let shared = ChunkedUploader()

    private let network = NetworkManager.shared

    /// 每片大小：1MB。对 20MB 上限约 20 片；慢链路下单片传输远小于 Caddy 600s 超时。
    private let chunkSize = 1 * 1024 * 1024

    private init() {}

    // MARK: - 续传进度持久化

    private struct ResumeState: Codable {
        let uploadId: String
        let totalChunks: Int
        var uploaded: [Int]
    }
    private let resumePrefix = "com.timetreehole.upload.resume."

    /// 同一段音频内容稳定映射到同一 key → 重试可断点续传
    private func resumeKey(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    private func loadState(for key: String) -> ResumeState? {
        guard let raw = UserDefaults.standard.data(forKey: resumePrefix + key),
              let s = try? JSONDecoder().decode(ResumeState.self, from: raw) else { return nil }
        return s
    }
    private func saveState(_ s: ResumeState, for key: String) {
        if let raw = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(raw, forKey: resumePrefix + key)
        }
    }
    private func clearState(for key: String) {
        UserDefaults.standard.removeObject(forKey: resumePrefix + key)
    }

    // MARK: - 分片计算

    private func totalChunks(for size: Int) -> Int {
        size == 0 ? 0 : (size + chunkSize - 1) / chunkSize
    }
    private func rangeOfChunk(_ index: Int, totalSize: Int) -> Range<Int> {
        let start = index * chunkSize
        let end = min(start + chunkSize, totalSize)
        return start..<end
    }

    // MARK: - 会话创建

    private func createSession(
        fileName: String, title: String, duration: TimeInterval,
        privacy: VoicePrivacy, total: Int, fileSize: Int, key: String
    ) async throws -> ResumeState {
        let initReq = UploadInitRequest(
            fileName: fileName,
            fileSize: fileSize,
            totalChunks: total,
            mimeType: "audio/mp4",
            title: title,
            privacy: privacy.apiValue,
            duration: Int(duration)
        )
        let initResp: UploadInitResponse = try await network.request(
            "/api/uploads/init", method: "POST", body: initReq
        )
        let state = ResumeState(uploadId: initResp.uploadId, totalChunks: total, uploaded: [])
        saveState(state, for: key)
        return state
    }

    // MARK: - 主流程

    func upload(
        audioData: Data,
        fileName: String,
        title: String,
        duration: TimeInterval,
        privacy: VoicePrivacy
    ) async throws -> SeedUploadResult {
        let key = resumeKey(for: audioData)
        let total = totalChunks(for: audioData.count)

        // 1) 取/建会话
        var st: ResumeState
        if let existing = loadState(for: key), existing.totalChunks == total {
            st = existing
        } else {
            st = try await createSession(
                fileName: fileName, title: title, duration: duration,
                privacy: privacy, total: total, fileSize: audioData.count, key: key
            )
        }

        // 2) 查服务端已接收分片（断点续传）；会话失效则重建
        var done = Set<Int>()
        let status: UploadStatusResponse? = try? await network.request("/api/uploads/status?uploadId=\(st.uploadId)")
        if let status {
            done = Set(status.received)
            st.uploaded = Array(done).sorted()
            saveState(st, for: key)
        } else {
            clearState(for: key)
            st = try await createSession(
                fileName: fileName, title: title, duration: duration,
                privacy: privacy, total: total, fileSize: audioData.count, key: key
            )
        }

        // 3) 逐片补传缺失分片（每片自带重试）
        for i in 0..<total {
            if done.contains(i) { continue }
            let chunk = audioData.subdata(in: rangeOfChunk(i, totalSize: audioData.count))
            try await network.uploadChunk(uploadId: st.uploadId, index: i, data: chunk)
            done.insert(i)
            st.uploaded = Array(done).sorted()
            saveState(st, for: key)
        }

        // 4) 合并落库
        let completeResp: UploadCompleteResponse = try await network.request(
            "/api/uploads/complete?uploadId=\(st.uploadId)", method: "POST"
        )

        // 成功后清续传进度
        clearState(for: key)

        let uuid = completeResp.uuid
        let audioUrl = URL(string: "\(network.baseURL)/api/seeds/\(uuid)/audio")!
        let resultPrivacy = completeResp.privacy.flatMap { VoicePrivacy(serverValue: $0) }
        return SeedUploadResult(
            uuid: uuid,
            audioUrl: audioUrl,
            privacy: resultPrivacy,
            creditsUsed: completeResp.quota?.creditsUsed,
            remainingFree: completeResp.quota?.remainingFree,
            savedAsPrivateDueToQuota: completeResp.savedAsPrivateDueToQuota ?? false
        )
    }
}

// MARK: - 分片上传请求 / 响应模型

private struct UploadInitRequest: Encodable {
    let fileName: String
    let fileSize: Int
    let totalChunks: Int
    let mimeType: String
    let title: String
    let privacy: String
    let duration: Int
}

private struct UploadInitResponse: Decodable {
    let uploadId: String
    let totalChunks: Int
}

private struct UploadStatusResponse: Decodable {
    let uploadId: String
    let totalChunks: Int
    let received: [Int]
    let complete: Bool
}

private struct UploadCompleteResponse: Decodable {
    let uuid: String
    let privacy: String?
    let audioUrl: String?
    let savedAsPrivateDueToQuota: Bool?
    let quota: QuotaUsageInfo?
}

// MARK: - VoicePrivacy 服务端值转换

extension VoicePrivacy {
    /// 把服务端返回的 "private" / "public" 转回枚举（rawValue 是中文，不能用 rawValue 直接转）
    init?(serverValue: String) {
        switch serverValue {
        case "public":  self = .public
        case "private": self = .private
        default:        return nil
        }
    }
}
