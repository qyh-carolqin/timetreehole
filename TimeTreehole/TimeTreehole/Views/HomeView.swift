import SwiftUI

// MARK: - 首页 · 录制

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var seedTitle: String = ""
    @State private var selectedPrivacy: VoicePrivacy = .private

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 标题
                        VStack(alignment: .leading, spacing: 4) {
                            Text("时间树洞")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(TreeholeColors.textPrimary)
                            Text("把你的心事，种成一颗种子")
                                .font(.system(size: 14))
                                .foregroundColor(TreeholeColors.textSecondary)
                        }
                        .padding(.top, 12)

                        // 录制区域
                        VStack(spacing: 0) {
                            Spacer().frame(height: 36)

                            SeedButton()
                                .environmentObject(store)
                                .frame(maxWidth: .infinity, alignment: .center)

                            Spacer().frame(height: 36)
                        }

                        // 统计卡��
                        HStack(spacing: 12) {
                            StatCard(
                                number: store.totalSeeds,
                                label: "已种下",
                                color: TreeholeColors.accentPrimary
                            )
                            StatCard(
                                number: store.sproutedSeeds,
                                label: "已发芽",
                                color: TreeholeColors.accentSecondary
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Tab Bar
                TabBarPill(selectedTab: $store.selectedTab, unreadCount: store.unreadNotifications)
            }
            .background(TreeholeColors.bgPrimary.ignoresSafeArea())

            // ---- 录制完成保存弹窗 ----
            if store.showSaveDialog {
                saveDialogOverlay
            }

            // ---- Toast ----
            if store.showToast, let msg = store.toastMessage {
                toastView(message: msg)
            }
        }
        .onDisappear {
            // 离开页面时停止播放
            store.stopPlayback()
        }
    }

    // MARK: - 保存弹窗

    private var saveDialogOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { /* 阻止穿透 */ }

            VStack(spacing: 20) {
                // 标题
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundColor(TreeholeColors.accentPrimary)

                    Text("录制完成")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(TreeholeColors.textPrimary)

                    Text("时长 \(store.formattedElapsedTime)")
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(TreeholeColors.accentPrimary)
                }

                // 标题输入
                VStack(alignment: .leading, spacing: 6) {
                    Text("给种子起个名字")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.textSecondary)

                    TextField("", text: $seedTitle)
                        .placeholder(when: seedTitle.isEmpty) {
                            Text("输入标题（可选）")
                                .foregroundColor(TreeholeColors.textMuted)
                        }
                        .font(.system(size: 16))
                        .foregroundColor(TreeholeColors.textPrimary)
                        .padding(12)
                        .background(TreeholeColors.borderSubtle.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
                }

                // 隐私选择
                VStack(alignment: .leading, spacing: 8) {
                    Text("隐私设置")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.textSecondary)

                    HStack(spacing: 10) {
                        privacyOption(.private, icon: "lock.fill", label: "私密", desc: "仅自己可见")

                        privacyOption(.public, icon: "globe.asia.australia.fill", label: "公共", desc: "匿名投递到树洞")
                    }

                    // 公共上传的额度提示
                    if selectedPrivacy == .public {
                        quotaHintView
                    }
                }

                // 按钮组
                HStack(spacing: 12) {
                    Button(action: {
                        store.discardRecording()
                        seedTitle = ""
                    }) {
                        Text("丢弃")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundColor(TreeholeColors.statusDanger)
                            .background(TreeholeColors.statusDanger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
                    }

                    Button(action: {
                        store.saveRecording(title: seedTitle, privacy: selectedPrivacy)
                        seedTitle = ""
                    }) {
                        Text("种下这颗种子")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .foregroundColor(TreeholeColors.bgPrimary)
                            .background(TreeholeColors.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
                    }
                }
            }
            .padding(24)
            .background(TreeholeColors.bgSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.lg))
            .padding(.horizontal, 32)
            .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.showSaveDialog)
    }

    // MARK: - 上传配额提示

    private var quotaHintView: some View {
        HStack(spacing: 8) {
            Image(systemName: store.uploadQuotaExhausted ? "leaf.arrow.circlepath" : "leaf.fill")
                .font(.system(size: 13))
                .foregroundColor(
                    store.uploadQuotaExhausted
                        ? TreeholeColors.accentSecondary
                        : TreeholeColors.accentPrimary
                )

            VStack(alignment: .leading, spacing: 2) {
                if store.uploadQuotaExhausted {
                    if store.canAffordExtraUpload {
                        Text("今日免费额度已用完，将消耗 ")
                            .font(.system(size: 12))
                            .foregroundColor(TreeholeColors.textSecondary)
                        + Text("\(store.costExtraUpload) 灵叶")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(TreeholeColors.accentSecondary)
                    } else {
                        Text("灵叶不足！前往商店充值 →")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TreeholeColors.statusDanger)
                    }
                } else {
                    Text("今日免费 \(store.dailyUploads + 1)/\(store.maxDailyUploads) 次")
                        .font(.system(size: 12))
                        .foregroundColor(TreeholeColors.accentPrimary)
                }
            }

            Spacer()

            Text("🍃 \(store.credits)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(TreeholeColors.accentPrimary)
        }
        .padding(12)
        .background(
            store.uploadQuotaExhausted && !store.canAffordExtraUpload
                ? TreeholeColors.statusDanger.opacity(0.1)
                : TreeholeColors.accentPrimary.opacity(0.08)
        )
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
        .animation(.spring(response: 0.3), value: store.uploadQuotaExhausted)
    }

    // MARK: - 隐私选项按钮

    private func privacyOption(_ privacy: VoicePrivacy, icon: String, label: String, desc: String) -> some View {
        Button(action: {
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
            selectedPrivacy = privacy
        }) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(
                        selectedPrivacy == privacy
                            ? TreeholeColors.accentPrimary
                            : TreeholeColors.textMuted
                    )
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(
                        selectedPrivacy == privacy
                            ? TreeholeColors.textPrimary
                            : TreeholeColors.textMuted
                    )
                Text(desc)
                    .font(.system(size: 10))
                    .foregroundColor(TreeholeColors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                selectedPrivacy == privacy
                    ? TreeholeColors.accentPrimary.opacity(0.1)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: TreeholeRadius.sm)
                    .stroke(
                        selectedPrivacy == privacy
                            ? TreeholeColors.accentPrimary.opacity(0.5)
                            : TreeholeColors.borderSubtle,
                        lineWidth: 1
                    )
            )
        }
    }

    // MARK: - Toast

    private func toastView(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TreeholeColors.bgPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(TreeholeColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .padding(.bottom, 120)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.showToast)
    }
}

// MARK: - 统计卡片

private struct StatCard: View {
    let number: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(TreeholeColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(TreeholeColors.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
    }
}

// MARK: - TextField Placeholder 辅助

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}
