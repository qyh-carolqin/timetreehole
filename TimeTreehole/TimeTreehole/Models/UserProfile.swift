import Foundation
import SwiftUI

// MARK: - 用户资料模型（匿名账号 + 设备标识）

/// 匿名用户资料，通过设备标识自动注册，可通过恢复码跨设备迁移
struct UserProfile: Codable, Identifiable {
    let id: Int
    let nickname: String
    let avatarColor: Int
    let bio: String
    let recoveryCode: String
    let credits: Int
    let createdAt: String?
    let deviceId: String?

    /// 头像色系（8 种自然系配色）
    var avatarColorSet: AvatarColorSet {
        AvatarColorSet.palette[safe: avatarColor] ?? .default
    }
}

// MARK: - 头像配色方案

struct AvatarColorSet: Identifiable {
    let id: Int
    let primary: Color
    let secondary: Color
    let name: String

    static let palette: [AvatarColorSet] = [
        AvatarColorSet(id: 0, primary: Color(hex: "7BB661"), secondary: Color(hex: "4A8A3E"), name: "鼠尾草绿"),
        AvatarColorSet(id: 1, primary: Color(hex: "E8A04C"), secondary: Color(hex: "C47E2E"), name: "暖琥珀"),
        AvatarColorSet(id: 2, primary: Color(hex: "6BAED6"), secondary: Color(hex: "3E8DBA"), name: "晨雾蓝"),
        AvatarColorSet(id: 3, primary: Color(hex: "C7A8D4"), secondary: Color(hex: "9A7BAA"), name: "薰衣草"),
        AvatarColorSet(id: 4, primary: Color(hex: "F7886E"), secondary: Color(hex: "D4634A"), name: "珊瑚橘"),
        AvatarColorSet(id: 5, primary: Color(hex: "8FD9B6"), secondary: Color(hex: "5BAE8E"), name: "薄荷绿"),
        AvatarColorSet(id: 6, primary: Color(hex: "F5C067"), secondary: Color(hex: "D49E3E"), name: "蜂蜜金"),
        AvatarColorSet(id: 7, primary: Color(hex: "A8C8E8"), secondary: Color(hex: "7A9FCC"), name: "冰川蓝"),
    ]

    static let `default` = palette[0]
}

// MARK: - 设备信息模型

struct DeviceInfo: Codable, Identifiable {
    let id: Int
    let platform: String
    let model: String?
    let isCurrent: Bool
    let lastActiveAt: String
    let createdAt: String
}

// MARK: - API 响应 DTO

struct UserProfileResponse: Codable {
    let success: Bool?
    let user: UserProfileDTO
}

struct UserDevicesResponse: Codable {
    let devices: [DeviceDTO]
}

struct UserProfileDTO: Codable {
    let id: Int
    let nickname: String?
    let avatarColor: Int?
    let bio: String?
    let recoveryCode: String?
    let credits: Int?
    let createdAt: String?
    let deviceId: String?

    func toModel() -> UserProfile {
        UserProfile(
            id: id,
            nickname: nickname ?? "匿名旅人",
            avatarColor: avatarColor ?? 0,
            bio: bio ?? "",
            recoveryCode: recoveryCode ?? "",
            credits: credits ?? 0,
            createdAt: createdAt,
            deviceId: deviceId
        )
    }
}

struct DeviceDTO: Codable {
    let id: Int
    let platform: String?
    let model: String?
    let isCurrent: Bool?
    let lastActiveAt: String?
    let createdAt: String?

    func toModel() -> DeviceInfo {
        DeviceInfo(
            id: id,
            platform: platform ?? "unknown",
            model: model,
            isCurrent: isCurrent ?? false,
            lastActiveAt: lastActiveAt ?? "",
            createdAt: createdAt ?? ""
        )
    }
}

// MARK: - 请求体

struct UpdateProfileRequest: Encodable {
    let nickname: String?
    let avatarColor: Int?
    let bio: String?
}

struct RecoverRequest: Encodable {
    let recoveryCode: String
    let confirm: Bool?
}

// MARK: - 首字母头像视图

struct AvatarView: View {
    let nickname: String
    let avatarColor: Int
    let size: CGFloat

    var body: some View {
        let colorSet = AvatarColorSet.palette[safe: avatarColor] ?? .default
        let initial = String(nickname.prefix(1))

        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [colorSet.primary, colorSet.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}
