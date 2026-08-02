import SwiftUI

// MARK: - 通知列表项

struct NotificationItem: View {
    let notification: TreeholeNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.2))
                        .frame(width: 40, height: 40)

                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundColor(iconColor)
                }

                // 内容
                VStack(alignment: .leading, spacing: 4) {
                    Text(notification.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 0) {
                        if !notification.subtitle.isEmpty {
                            Text("「\(notification.relatedSeedTitle)」\(notification.subtitle)")
                                .font(.system(size: 12))
                                .foregroundColor(TreeholeColors.textSecondary)
                        } else {
                            Text("「\(notification.relatedSeedTitle)」")
                                .font(.system(size: 12))
                                .foregroundColor(TreeholeColors.textSecondary)
                        }
                    }

                    Text(notification.formattedTime)
                        .font(.system(size: 11))
                        .foregroundColor(TreeholeColors.textMuted)
                }

                Spacer()

                // 未读标记
                if !notification.isRead {
                    Circle()
                        .fill(TreeholeColors.accentPrimary)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(16)
            .background(
                notification.isRead
                    ? TreeholeColors.bgSurface
                    : TreeholeColors.bgSurface.opacity(0.85)
            )
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
        }
    }

    private var iconName: String {
        notification.type == .reply ? "bubble.left.and.bubble.right.fill" : "leaf.fill"
    }

    private var iconColor: Color {
        notification.type == .reply ? TreeholeColors.accentPrimary : TreeholeColors.accentSecondary
    }
}
