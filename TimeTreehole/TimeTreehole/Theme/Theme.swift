import SwiftUI

// MARK: - 时间树洞 · 魔法森林色彩系统

struct TreeholeColors {
    // 背景层
    static let bgPrimary    = Color(red: 0.055, green: 0.102, blue: 0.071)  // #0E1A12 深森林底色
    static let bgSurface    = Color(red: 0.094, green: 0.153, blue: 0.118)  // #18271E 卡片表面
    static let bgElevated   = Color(red: 0.122, green: 0.200, blue: 0.153)  // #1F3327 悬浮层

    // 主色 — 鼠尾草绿
    static let accentPrimary   = Color(red: 0.482, green: 0.714, blue: 0.380) // #7BB661
    static let accentSecondary = Color(red: 0.910, green: 0.627, blue: 0.298) // #E8A04C 暖琥珀
    static let accentGlow      = Color(red: 0.769, green: 0.843, blue: 0.498) // #C4D77F 魔法光晕

    // 生长阶段色
    static let growthSeed    = Color(red: 0.561, green: 0.722, blue: 0.302) // #8FB84E
    static let growthSprout  = Color(red: 0.482, green: 0.714, blue: 0.380) // #7BB661
    static let growthSapling = Color(red: 0.353, green: 0.620, blue: 0.239) // #5A9E3D
    static let growthTree    = Color(red: 0.239, green: 0.478, blue: 0.165) // #3D7A2A

    // 文字
    static let textPrimary   = Color(red: 0.941, green: 0.922, blue: 0.878) // #F0EBE0
    static let textSecondary = Color(red: 0.612, green: 0.690, blue: 0.635) // #9CB0A2
    static let textMuted     = Color(red: 0.361, green: 0.420, blue: 0.385) // #5C6B62

    // 功能色
    static let borderSubtle  = Color(red: 0.165, green: 0.227, blue: 0.188) // #2A3A30
    static let danger        = Color(red: 0.831, green: 0.385, blue: 0.367) // #D45C5D
    static let statusDanger  = Color(red: 0.831, green: 0.385, blue: 0.367) // #D45C5D 别名

    // 别名（兼容旧引用）
    static let bgSurfaceElevated = Color(red: 0.122, green: 0.200, blue: 0.153) // #1F3327
}

// MARK: - 渐变预设

extension LinearGradient {
    static let seedGlow = LinearGradient(
        colors: [TreeholeColors.growthSeed, TreeholeColors.growthSapling],
        startPoint: .top,
        endPoint: .bottom
    )

    static let forestMist = LinearGradient(
        colors: [TreeholeColors.bgPrimary.opacity(0), TreeholeColors.bgPrimary],
        startPoint: .top,
        endPoint: .bottom
    )

    /// 录制中脉冲渐变（绿 → 暖琥珀）
    static let recordingPulse = LinearGradient(
        colors: [TreeholeColors.accentPrimary, TreeholeColors.accentSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 圆角规范

struct TreeholeRadius {
    static let sm: CGFloat  = 12
    static let md: CGFloat  = 16
    static let lg: CGFloat  = 20
    static let pill: CGFloat = 100
}

// MARK: - 间距规范

struct TreeholeSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Color(hex:) 扩展

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - Array 安全下标

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
