import Foundation

// MARK: - 语音回复数据模型

struct VoiceReply: Identifiable, Codable {
    let id: UUID
    let uuid: String
    var duration: TimeInterval
    var createdAt: Date
    var audioURL: URL?

    /// 是否已下载到本地缓存
    var isCached: Bool = false

    // 格式化时长
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // 格式化日期
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: createdAt)
    }
}

// MARK: - DTO

struct VoiceReplyDTO: Decodable {
    let uuid: String
    let duration: Double?
    let createdAt: String?
    let audioUrl: String?

    func toModel() -> VoiceReply {
        VoiceReply(
            id: UUID(uuidString: uuid) ?? UUID(),
            uuid: uuid,
            duration: duration ?? 0,
            createdAt: parseDate(createdAt),
            audioURL: audioUrl.flatMap { URL(string: "\(APIConfig.baseURL)\($0)") }
        )
    }

    private func parseDate(_ iso: String?) -> Date {
        guard let iso = iso else { return Date() }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: iso) ?? Date()
    }
}
