import Foundation

// MARK: - 后端日期解析
// 后端 created_at 由 SQLite datetime('now') 生成，格式形如 "2026-08-28 12:16:00"（UTC、空格分隔、无 T/Z）。
// 也兼容 ISO8601（带 T 与 Z 或毫秒）。解析失败才回退到当前时间。

extension Date {
    static func fromServer(_ value: String?) -> Date {
        guard let value = value else { return Date() }

        // 优先解析 ISO8601（带 T / Z / 毫秒）
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: value) { return d }

        // 兜底：SQLite datetime('now') 默认格式（UTC）
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = fmt.date(from: value) { return d }

        return Date()
    }
}
