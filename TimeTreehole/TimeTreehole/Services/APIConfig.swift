import Foundation

// MARK: - API 配置 · 集中管理所有网络相关配置

/// 全局 API 配置，控制环境切换和功能开关
enum APIConfig {

    // ============================================================
    // MARK: — 环境配置
    // ============================================================

    /// 后端 API 基础地址
    /// DEBUG → 本地开发服务器 (localhost:3000)
    /// RELEASE → Railway 免费部署 (自动 HTTPS)
    #if DEBUG
    static let baseURL = "http://localhost:3000"
    #else
    // 内测/生产后端地址：Railway 免费层 (自动 HTTPS, 无需境外信用卡)
    // 后端实际部署在 Railway，UptimeRobot 每 5 分钟 ping /api/health 保活。
    static let baseURL = "https://timetreehole-api-production-f42f.up.railway.app"
    #endif

    /// 当前运行环境
    #if DEBUG
    static let environment = "development"
    #else
    static let environment = "production"
    #endif

    // ============================================================
    // MARK: — 超时配置
    // ============================================================

    /// 普通 API 请求超时（秒）
    static let requestTimeout: TimeInterval = 30

    /// 音频上传超时（秒，大文件需要更长时间）
    static let uploadTimeout: TimeInterval = 120

    /// 音频下载超时（秒）
    static let downloadTimeout: TimeInterval = 60

    // ============================================================
    // MARK: — 文件限制
    // ============================================================

    /// 最大音频文件大小（MB）
    static let maxAudioSizeMB = 20

    /// 最大音频时长（秒）
    static let maxRecordingDuration: TimeInterval = 300 // 5 分钟

    // ============================================================
    // MARK: — 功能开关
    // ============================================================

    /// 是否启用推送通知
    static let pushEnabled = true

    /// 是否启用 IAP（内购）
    static let iapEnabled = true

    /// 是否打印网络日志
    #if DEBUG
    static let networkLogging = true
    #else
    static let networkLogging = false
    #endif

    // ============================================================
    // MARK: — 设备信息
    // ============================================================

    static let platform = "ios"

    static var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
