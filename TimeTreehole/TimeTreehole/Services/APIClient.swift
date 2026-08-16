import Foundation

// MARK: - API 客户端 · 业务层接口

/// 封装所有时间树洞后端 API 调用，对外暴露简洁的 async/await 方法
/// AppStore 通过 APIClient 与后端通信，无需关心 URLSession 细节
@MainActor
final class APIClient {

    static let shared = APIClient()
    private let network = NetworkManager.shared

    private init() {}

    // ============================================================
    // MARK: — 种子管理
    // ============================================================

    /// 上传语音种子（带录音文件 + 元数据）
    func uploadSeed(audioData: Data, title: String, duration: TimeInterval, privacy: VoicePrivacy) async throws -> SeedUploadResult {
        let fields: [String: String] = [
            "title":    title,
            "duration": String(Int(duration)),
            "privacy":  privacy.apiValue,
        ]

        let fileName = "recording-\(Int(Date().timeIntervalSince1970)).m4a"
        let response: UploadResponse = try await network.upload(
            path: "/api/seeds/with-duration",
            fileData: audioData,
            fileName: fileName,
            fields: fields
        )

        guard let uuid = response.uuid else {
            throw APIError.decodingError("服务器未返回种子 UUID")
        }

        return SeedUploadResult(
            uuid: uuid,
            audioUrl: URL(string: "\(network.baseURL)/api/seeds/\(uuid)/audio")!,
            creditsUsed: response.quota?.creditsUsed,
            remainingFree: response.quota?.remainingFree
        )
    }

    /// 获取我的种子列表
    func fetchMySeeds() async throws -> [VoiceSeed] {
        let response: APIListResponse<VoiceSeedDTO> = try await network.request("/api/my/seeds")
        return (response.seeds ?? []).map { $0.toModel() }
    }

    /// 获取种子详情
    func fetchSeed(uuid: String) async throws -> VoiceSeed {
        let response: APIItemResponse<VoiceSeedDTO> = try await network.request("/api/seeds/\(uuid)")
        guard let dto = response.seed else { throw APIError.notFound }
        return dto.toModel()
    }

    /// 下载音频文件
    func downloadAudio(uuid: String) async throws -> Data {
        try await network.requestData("/api/seeds/\(uuid)/audio")
    }

    /// 删除种子
    func deleteSeed(uuid: String) async throws {
        try await network.requestVoid("/api/seeds/\(uuid)", method: "DELETE")
    }

    /// 修改种子的私密/公域属性
    /// - privacy: .public 表示发布到公共域（私密→公域会重新扣上传额度），.private 表示收回为私密
    func updateSeedPrivacy(uuid: String, privacy: VoicePrivacy) async throws -> SeedPrivacyResult {
        struct Body: Encodable { let privacy: String }
        let body = Body(privacy: privacy.apiValue)
        return try await network.request("/api/seeds/\(uuid)/privacy", method: "PATCH", body: body)
    }

    // ============================================================
    // MARK: — 树洞（公共域）
    // ============================================================

    /// 获取随机公共种子（排除已看过的）
    func fetchRandomSeed(excludeUUIDs: [String] = []) async throws -> VoiceSeed? {
        var path = "/api/treehole/random"
        if !excludeUUIDs.isEmpty {
            let joined = excludeUUIDs.joined(separator: ",")
            path += "?exclude=\(joined)"
        }
        let response: APIItemResponse<VoiceSeedDTO> = try await network.request(path)
        return response.seed?.toModel()
    }

    /// 树洞统计
    func fetchTreeholeStats() async throws -> (totalPublic: Int, totalSeeds: Int) {
        let response: APIStatsResponse = try await network.request("/api/treehole/stats")
        return (response.totalPublic ?? 0, response.totalSeeds ?? 0)
    }

    /// 匿名回复（语音评论）
    func replyToSeed(seedUUID: String, audioData: Data) async throws -> Bool {
        let fileName = "reply-\(Int(Date().timeIntervalSince1970)).m4a"
        let response: UploadResponse = try await network.upload(
            path: "/api/treehole/\(seedUUID)/reply",
            fileData: audioData,
            fileName: fileName
        )
        return response.success ?? false
    }

    // ============================================================
    // MARK: — 通知
    // ============================================================

    /// 获取通知列表
    func fetchNotifications() async throws -> [TreeholeNotification] {
        let response: APIListResponse<NotificationDTO> = try await network.request("/api/notifications")
        return (response.notifications ?? []).map { $0.toModel() }
    }

    /// 获取未读通知数量
    func fetchUnreadCount() async throws -> Int {
        let response: APIUnreadResponse = try await network.request("/api/notifications/unread-count")
        return response.count
    }

    /// 标记单条已读
    func markRead(notificationId: UUID) async throws {
        try await network.requestVoid("/api/notifications/\(notificationId.uuidString)/read", method: "PUT")
    }

    /// 全部标记已读
    func markAllRead() async throws {
        try await network.requestVoid("/api/notifications/read-all", method: "PUT")
    }

    // ============================================================
    // MARK: — 配额与灵叶
    // ============================================================

    /// 获取用户配额和灵叶余额
    func fetchQuota() async throws -> QuotaInfo {
        try await network.request("/api/user/quota")
    }

    /// 获取灵叶余额（轻量）
    func fetchCredits() async throws -> Int {
        let response: APICreditsResponse = try await network.request("/api/user/credits")
        return response.credits
    }

    /// 获取充值套餐
    func fetchPackages() async throws -> [RechargePackageDTO] {
        let response: APIPackagesResponse = try await network.request("/api/user/packages")
        return response.packages ?? []
    }

    /// 充值灵叶（模拟，已废弃 — 请使用 IAPManager）
    func recharge(packageId: String) async throws -> RechargeResult {
        struct Body: Encodable { let packageId: String }
        let body = Body(packageId: packageId)
        return try await network.request("/api/user/recharge", method: "POST", body: body)
    }

    /// App Store IAP 收据验证
    func verifyReceipt(
        receiptData: String,
        packageId: String,
        transactionId: String,
        productId: String
    ) async throws -> IAPVerifyResult {
        struct Body: Encodable {
            let receiptData: String
            let packageId: String
            let transactionId: String
            let productId: String
        }
        let body = Body(
            receiptData: receiptData,
            packageId: packageId,
            transactionId: transactionId,
            productId: productId
        )
        return try await network.request("/api/iap/verify", method: "POST", body: body)
    }

    // ============================================================
    // MARK: — 推送注册
    // ============================================================

    /// 注册 APNs 推送令牌
    func registerPushToken(_ token: String) async throws {
        struct PushBody: Encodable { let token: String }
        let body = PushBody(token: token)
        let _: APISuccessResponse = try await network.request("/api/device/register", method: "POST", body: body)
    }

    // ============================================================
    // MARK: — 用户系统（匿名账号 + 设备标识）
    // ============================================================

    /// 注册匿名账号（首次启动时调用，自动生成昵称和恢复码）
    func registerUser(nickname: String? = nil, avatarColor: Int? = nil) async throws -> UserProfile {
        struct Body: Encodable {
            let nickname: String?
            let avatarColor: Int?
        }
        let body = Body(nickname: nickname, avatarColor: avatarColor)
        let response: UserProfileResponse = try await network.request("/api/user/register", method: "POST", body: body)
        return response.user.toModel()
    }

    /// 获取当前用户资料
    func getUserProfile() async throws -> UserProfile {
        let response: UserProfileResponse = try await network.request("/api/user/profile")
        return response.user.toModel()
    }

    /// 更新用户资料
    func updateUserProfile(nickname: String? = nil, avatarColor: Int? = nil, bio: String? = nil) async throws -> UserProfile {
        let body = UpdateProfileRequest(nickname: nickname, avatarColor: avatarColor, bio: bio)
        let response: UserProfileResponse = try await network.request("/api/user/profile", method: "PUT", body: body)
        return response.user.toModel()
    }

    /// 通过恢复码恢复账号（设备迁移）
    func recoverAccount(recoveryCode: String, confirm: Bool = false) async throws -> UserProfile {
        let body = RecoverRequest(recoveryCode: recoveryCode, confirm: confirm)
        let response: UserProfileResponse = try await network.request("/api/user/recover", method: "POST", body: body)
        return response.user.toModel()
    }

    /// 确认恢复（覆盖当前设备数据）
    func confirmRecovery(recoveryCode: String) async throws -> UserProfile {
        let body = RecoverRequest(recoveryCode: recoveryCode, confirm: true)
        let response: UserProfileResponse = try await network.request("/api/user/recover/confirm", method: "POST", body: body)
        return response.user.toModel()
    }

    /// 获取绑定的设备列表
    func getDevices() async throws -> [DeviceInfo] {
        let response: UserDevicesResponse = try await network.request("/api/user/devices")
        return response.devices.map { $0.toModel() }
    }

    /// 解绑设备
    func unbindDevice(deviceId: Int) async throws {
        try await network.requestVoid("/api/user/devices/\(deviceId)", method: "DELETE")
    }

    // ============================================================
    // MARK: — 举报 / 屏蔽 / 账号删除
    // ============================================================

    /// 举报公共树洞中的种子
    func reportSeed(seedUuid: String, reason: String? = nil) async throws {
        struct Body: Encodable { let seedUuid: String; let reason: String? }
        let body = Body(seedUuid: seedUuid, reason: reason)
        let _: APISuccessResponse = try await network.request("/api/moderation/report", method: "POST", body: body)
    }

    /// 屏蔽某用户
    func blockUser(userId: Int) async throws {
        struct Body: Encodable { let targetUserId: Int }
        let body = Body(targetUserId: userId)
        let _: APISuccessResponse = try await network.request("/api/moderation/block", method: "POST", body: body)
    }

    /// 取消屏蔽
    func unblockUser(userId: Int) async throws {
        try await network.requestVoid("/api/moderation/block/\(userId)", method: "DELETE")
    }

    /// 删除当前账号及全部数据
    func deleteAccount() async throws {
        try await network.requestVoid("/api/account", method: "DELETE")
    }
}

// MARK: - 数据传输对象 (DTO) · 用于 JSON 解码

struct VoiceSeedDTO: Decodable {
    let uuid: String
    let title: String
    let duration: Double?
    let privacy: String?
    let replyCount: Int?
    let createdAt: String?
    let growthStage: String?
    let authorUserId: Int?

    func toModel() -> VoiceSeed {
        VoiceSeed(
            id: UUID(uuidString: uuid) ?? UUID(),
            title: title,
            duration: duration ?? 0,
            privacy: (privacy == "public") ? .public : .private,
            replyCount: replyCount ?? 0,
            createdAt: parseDate(createdAt),
            audioURL: URL(string: "\(APIConfig.baseURL)/api/seeds/\(uuid)/audio"),
            serverUUID: uuid,
            authorUserId: authorUserId
        )
    }

    private func parseDate(_ iso: String?) -> Date {
        guard let iso = iso else { return Date() }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: iso) ?? Date()
    }
}

struct NotificationDTO: Decodable {
    let id: Int
    let type: String?
    let title: String?
    let subtitle: String?
    let relatedSeedTitle: String?
    let createdAt: String?
    let isRead: Int?

    func toModel() -> TreeholeNotification {
        TreeholeNotification(
            id: UUID(),
            type: (type == "growth") ? .growth : .reply,
            title: title ?? "",
            subtitle: subtitle ?? "",
            relatedSeedTitle: relatedSeedTitle ?? "",
            createdAt: parseDate(createdAt),
            isRead: (isRead ?? 0) == 1,
            serverId: id
        )
    }

    private func parseDate(_ iso: String?) -> Date {
        guard let iso = iso else { return Date() }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.date(from: iso) ?? Date()
    }
}

// MARK: - 配额相关 DTO

struct QuotaInfo: Decodable {
    let credits: Int
    let dailyUploads: Int
    let dailyRetrievals: Int
    let maxDailyUploads: Int
    let maxDailyRetrievals: Int
    let costExtraUpload: Int
    let costExtraRetrieval: Int
}

struct APICreditsResponse: Decodable {
    let credits: Int
}

struct APIPackagesResponse: Decodable {
    let packages: [RechargePackageDTO]?
}

struct RechargePackageDTO: Decodable {
    let id: String
    let name: String
    let credits: Int
    let price: Int
    let desc: String
    let popular: Bool?
}

struct RechargeResult: Decodable {
    let success: Bool
    let addedCredits: Int?
    let totalCredits: Int?
    let package: String?
    let message: String?
}

struct IAPVerifyResult: Decodable {
    let success: Bool
    let addedCredits: Int?
    let totalCredits: Int?
    let transactionId: String?
    let message: String?
}

// MARK: - 上传结果

struct SeedUploadResult {
    let uuid: String
    let audioUrl: URL
    let creditsUsed: Int?
    let remainingFree: Int?
}

struct SeedPrivacyResult: Decodable {
    let success: Bool
    let privacy: String?
    let changed: Bool?
    let creditsUsed: Int?
    let remainingFree: Int?
    let message: String?
}

// MARK: - VoicePrivacy API 值

extension VoicePrivacy {
    var apiValue: String {
        switch self {
        case .private: return "private"
        case .public:  return "public"
        }
    }
}
