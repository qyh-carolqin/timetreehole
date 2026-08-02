import SwiftUI

// MARK: - 我的花园

struct GardenView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 标题 + 个人资料入口
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的花园")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(TreeholeColors.textPrimary)
                            Text("你种下的每一颗种子都在这里")
                                .font(.system(size: 14))
                                .foregroundColor(TreeholeColors.textSecondary)
                        }

                        Spacer()

                        // 头像按钮 → 个人资料
                        Button(action: { store.showProfile = true }) {
                            AvatarView(
                                nickname: store.userProfile?.nickname ?? "匿",
                                avatarColor: store.userProfile?.avatarColor ?? 0,
                                size: 44
                            )
                            .overlay(
                                Circle()
                                    .stroke(TreeholeColors.borderSubtle, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.top, 12)

                    // 灵叶余额 + 商店入口
                    storeBalanceBar

                    // 语音列表
                    if store.mySeeds.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "leaf.arrow.circlepath")
                                .font(.system(size: 40))
                                .foregroundColor(TreeholeColors.textMuted)
                            Text("还没有种下种子")
                                .font(.system(size: 14))
                                .foregroundColor(TreeholeColors.textMuted)
                            Text("去首页录制你的第一颗种子吧")
                                .font(.system(size: 12))
                                .foregroundColor(TreeholeColors.textMuted.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(store.mySeeds) { seed in
                                VoiceListItem(seed: seed) {
                                    store.deleteSeed(seed)
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    )
                                )
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

    // MARK: - 灵叶余额条

    private var storeBalanceBar: some View {
        Button(action: { store.showStore = true }) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14))
                    .foregroundColor(TreeholeColors.accentPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("灵叶余额")
                        .font(.system(size: 11))
                        .foregroundColor(TreeholeColors.textMuted)
                    Text("🍃 \(store.credits) 灵叶")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TreeholeColors.accentPrimary)
                }

                Spacer()

                Text("充值 →")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TreeholeColors.accentPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(TreeholeColors.accentPrimary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
            }
            .padding(14)
            .background(TreeholeColors.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
        }
    }
}
