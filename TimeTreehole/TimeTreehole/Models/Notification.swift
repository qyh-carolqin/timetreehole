import Foundation

// MARK: - 通知数据模型

enum NotificationType: String, Codable {
    case reply  = "回复"   // 收到新回复
    case growth = "生长"   // 种子成长阶段变化
}

struct TreeholeNotification: Identifiable, Codable {
    let id: UUID
    var type: NotificationType
    var title: String
    var subtitle: String
    var relatedSeedTitle: String
    var createdAt: Date
    var isRead: Bool = false

    /// 服务端 ID（整数），用于标记已读 API
    var serverId: Int?

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: createdAt)
    }

    // MARK: — 示例数据（离线兜底）

    static let samples: [TreeholeNotification] = [
        TreeholeNotification(
            id: UUID(),
            type: .reply,
            title: "你的种子收到了 2 条新回复",
            subtitle: "",
            relatedSeedTitle: "深夜的感慨",
            createdAt: Calendar.current.date(byAdding: .minute, value: -40, to: Date())!
        ),
        TreeholeNotification(
            id: UUID(),
            type: .growth,
            title: "你的种子发芽了！",
            subtitle: "已进入发芽阶段",
            relatedSeedTitle: "心事片段",
            createdAt: Calendar.current.date(byAdding: .hour, value: -6, to: Date())!
        ),
    ]
}
