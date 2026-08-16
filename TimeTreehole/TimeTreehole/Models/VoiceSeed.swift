import Foundation

// MARK: - 语音种子数据模型

enum GrowthStage: String, Codable, CaseIterable {
    case seed    = "种子"       // 0 回复
    case sprout  = "发芽"       // 1-2 回复
    case sapling = "幼苗"       // 3-5 回复
    case tree    = "大树"       // 6+ 回复

    static func stage(forReplyCount count: Int) -> GrowthStage {
        switch count {
        case 0:       return .seed
        case 1...2:   return .sprout
        case 3...5:   return .sapling
        default:      return .tree
        }
    }
}

enum VoicePrivacy: String, Codable {
    case `private` = "私密"
    case `public`  = "公共"
}

struct VoiceSeed: Identifiable, Codable {
    let id: UUID
    var title: String
    var duration: TimeInterval          // 秒数
    var privacy: VoicePrivacy
    var replyCount: Int
    var createdAt: Date
    var audioURL: URL?

    // MARK: — 服务端同步字段

    /// 服务端 UUID 字符串（用于 API 通信），nil 表示仅本地存在
    var serverUUID: String?

    /// 作者用户 ID（服务端用户 id，用于举报/屏蔽）
    var authorUserId: Int? = nil

    /// 是否已上传到服务器
    var isUploaded: Bool { serverUUID != nil }

    // 生长阶段
    var growthStage: GrowthStage {
        GrowthStage.stage(forReplyCount: replyCount)
    }

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
        formatter.dateFormat = "M月d日"
        return formatter.string(from: createdAt)
    }

    // 完整时间
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: createdAt)
    }

    // MARK: — 示例数据（离线兜底）

    static let samples: [VoiceSeed] = [
        VoiceSeed(
            id: UUID(),
            title: "心事片段",
            duration: 24,
            privacy: .private,
            replyCount: 0,
            createdAt: Calendar.current.date(byAdding: .hour, value: -3, to: Date())!,
            authorUserId: nil
        ),
        VoiceSeed(
            id: UUID(),
            title: "深夜的感慨",
            duration: 65,
            privacy: .public,
            replyCount: 2,
            createdAt: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            authorUserId: nil
        ),
        VoiceSeed(
            id: UUID(),
            title: "雨天的回忆",
            duration: 42,
            privacy: .public,
            replyCount: 5,
            createdAt: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
            authorUserId: nil
        ),
    ]
}
