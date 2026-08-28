import SwiftUI

// MARK: - 公共树洞（含额度系统）

struct TreeholeView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var recorder = AudioRecorder.shared
    @ObservedObject var player = AudioPlayer.shared

    @State private var isCommenting = false
    @State private var showModerationMenu = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 标题
                        VStack(alignment: .leading, spacing: 4) {
                            Text("公共树洞")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundColor(TreeholeColors.textPrimary)
                            Text("拾起一颗种子，听听陌生人的故事")
                                .font(.system(size: 14))
                                .foregroundColor(TreeholeColors.textSecondary)
                        }
                        .padding(.top, 12)

                        // 今日获取配额提示
                        retrievalQuotaBar

                        // 语音卡片（含播放控制 + 举报/屏蔽菜单）
                        if let seed = store.currentRandomSeed {
                            VStack(spacing: 12) {
                                HStack {
                                    Spacer()
                                    Button(action: { showModerationMenu = true }) {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(TreeholeColors.textSecondary)
                                            .padding(8)
                                            .background(TreeholeColors.bgSurface)
                                            .clipShape(Circle())
                                    }
                                }

                                VoiceCard(seed: seed)
                                    .environmentObject(store)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .confirmationDialog("更多操作", isPresented: $showModerationMenu, titleVisibility: .visible) {
                                Button("举报该内容", role: .none) {
                                    Task { await store.reportCurrentSeed(reason: "用户举报") }
                                }
                                Button("屏蔽该用户", role: .destructive) {
                                    Task { await store.blockCurrentSeedAuthor() }
                                }
                                Button("取消", role: .cancel) {}
                            } message: {
                                Text("如果你认为这条语音违反社区规范，可以选择举报或屏蔽发布者。")
                            }
                        } else {
                            emptyTreeholeView
                        }

                        // 操作按钮
                        HStack(spacing: 12) {
                            // 换一颗
                            Button(action: {
                                let feedback = UIImpactFeedbackGenerator(style: .light)
                                feedback.impactOccurred()
                                store.stopPlayback()

                                Task {
                                    await store.fetchRandomSeed()
                                }
                            }) {
                                HStack {
                                    if store.isLoadingTreehole {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(TreeholeColors.textPrimary)
                                    } else {
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 14))
                                    }
                                    Text("换一颗")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundColor(TreeholeColors.textPrimary)
                                .background(TreeholeColors.bgSurface)
                                .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
                            }
                            .disabled(store.isLoadingTreehole)

                            // 匿名评论
                            Button(action: {
                                let feedback = UIImpactFeedbackGenerator(style: .medium)
                                feedback.impactOccurred()
                                store.stopPlayback()
                                if isCommenting {
                                    if recorder.elapsedTime >= 1 {
                                        recorder.stopRecording()
                                        Task {
                                            if let seed = store.currentRandomSeed,
                                               let fileURL = recorder.recordedFileURL {
                                                if let data = try? Data(contentsOf: fileURL) {
                                                    await store.replyToSeed(seed: seed, audioData: data)
                                                }
                                            }
                                        }
                                        store.showToast("匿名评论已发送")
                                        isCommenting = false
                                    } else {
                                        recorder.cancelRecording()
                                        isCommenting = false
                                    }
                                } else {
                                    Task {
                                        let granted = await recorder.requestPermission()
                                        if granted {
                                            recorder.startRecording(title: "匿名评论")
                                            isCommenting = true
                                        } else {
                                            store.showToast("需要麦克风权限才能评论")
                                        }
                                    }
                                }
                            }) {
                                HStack {
                                    if isCommenting && recorder.status == .recording {
                                        Text(store.formattedElapsedTime)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .transition(.opacity)
                                    } else {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 14))
                                        Text("匿名评论")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundColor(TreeholeColors.bgPrimary)
                                .background(
                                    isCommenting
                                        ? TreeholeColors.statusDanger
                                        : TreeholeColors.accentPrimary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
                            }
                        }
                        .animation(.spring(response: 0.3), value: isCommenting)
                    }
                    .padding(.horizontal, 20)
                }

                TabBarPill(selectedTab: $store.selectedTab, unreadCount: store.unreadNotifications)
            }
            .background(TreeholeColors.bgPrimary.ignoresSafeArea())

            // Toast
            if store.showToast, let msg = store.toastMessage {
                toastOverlay(message: msg)
            }
        }
        .task {
            // 首次进入树洞时自动获取一颗种子
            if store.currentRandomSeed == nil {
                await store.fetchRandomSeed()
            }
        }
        .onDisappear {
            store.stopPlayback()
        }
    }

    // MARK: - 获取配额条

    private var retrievalQuotaBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(TreeholeColors.accentPrimary)

            Text("公共树洞免费畅听 · 不限次数")
                .font(.system(size: 12))
                .foregroundColor(TreeholeColors.accentPrimary)

            Spacer()

            // 灵叶余额 + 商店入口
            Button(action: { store.showStore = true }) {
                HStack(spacing: 4) {
                    Text("🍃 \(store.credits)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(TreeholeColors.accentPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(TreeholeColors.textMuted)
                }
            }
        }
        .padding(12)
        .background(TreeholeColors.accentPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
    }

    // MARK: - 空状态

    private var emptyTreeholeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tree.fill")
                .font(.system(size: 48))
                .foregroundColor(TreeholeColors.accentPrimary.opacity(0.3))

            VStack(spacing: 6) {
                Text("树洞还是空的")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TreeholeColors.textSecondary)

                Text("点击「换一颗」发现新的故事")
                    .font(.system(size: 14))
                    .foregroundColor(TreeholeColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func toastOverlay(message: String) -> some View {
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
