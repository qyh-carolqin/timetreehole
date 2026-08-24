import SwiftUI

// MARK: - 消息通知

struct NotificationsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 标题
                    VStack(alignment: .leading, spacing: 4) {
                        Text("消息")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(TreeholeColors.textPrimary)
                        Text("你的种子正在发生变化")
                            .font(.system(size: 14))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }
                    .padding(.top, 12)

                    // 通知列表
                    if store.notifications.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bell.slash")
                                .font(.system(size: 40))
                                .foregroundColor(TreeholeColors.textMuted)
                            Text("暂无消息")
                                .font(.system(size: 14))
                                .foregroundColor(TreeholeColors.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.notifications) { notification in
                                NotificationItem(notification: notification) {
                                    store.markNotificationRead(notification)
                                    if let seedUUID = notification.seedUUID {
                                        store.showSeedDetail(seedUUID: seedUUID)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            TabBarPill(selectedTab: $store.selectedTab, unreadCount: store.unreadNotifications)
        }
        .background(TreeholeColors.bgPrimary.ignoresSafeArea())
    }
}
