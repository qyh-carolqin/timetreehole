import SwiftUI

// MARK: - 种子详情页（展示原种子 + 所有语音回复）

struct SeedDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var player = AudioPlayer.shared

    let seed: VoiceSeed

    var body: some View {
        NavigationView {
            ZStack {
                TreeholeColors.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // 原种子播放卡片
                        VoiceCard(seed: seed)
                            .environmentObject(store)

                        // 回复列表
                        repliesSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        store.stopPlayback()
                        store.dismissSeedDetail()
                        dismiss()
                    }
                    .foregroundColor(TreeholeColors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear {
            store.stopPlayback()
        }
    }

    // MARK: - 回复列表

    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("语音回复")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TreeholeColors.textPrimary)

                Spacer()

                Text("\(store.seedDetailReplies.count) 条")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TreeholeColors.textMuted)
            }

            if store.isLoadingSeedDetailReplies && store.seedDetailReplies.isEmpty {
                ProgressView()
                    .scaleEffect(1.0)
                    .tint(TreeholeColors.accentPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if store.seedDetailReplies.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 40))
                        .foregroundColor(TreeholeColors.textMuted)

                    Text("还没有回复")
                        .font(.system(size: 14))
                        .foregroundColor(TreeholeColors.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(store.seedDetailReplies) { reply in
                        ReplyRow(reply: reply)
                            .environmentObject(store)
                    }
                }
            }
        }
    }
}

// MARK: - 单条回复行

private struct ReplyRow: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var player = AudioPlayer.shared

    let reply: VoiceReply

    private var isCurrent: Bool {
        player.currentURL?.lastPathComponent == "\(reply.uuid).m4a"
    }

    private var isPlayingThis: Bool {
        isCurrent && player.status == .playing
    }

    private var isLoadingThis: Bool {
        isCurrent && player.status == .loading
    }

    var body: some View {
        HStack(spacing: 14) {
            // 播放按钮
            Button(action: { store.playReply(reply) }) {
                ZStack {
                    Circle()
                        .fill(isPlayingThis
                            ? TreeholeColors.accentPrimary.opacity(0.2)
                            : TreeholeColors.accentPrimary.opacity(0.12)
                        )
                        .frame(width: 44, height: 44)

                    if isLoadingThis {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(TreeholeColors.accentPrimary)
                    } else if isPlayingThis {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 16))
                            .foregroundColor(TreeholeColors.accentPrimary)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundColor(TreeholeColors.accentPrimary)
                            .offset(x: 1)
                    }
                }
            }
            .disabled(isLoadingThis)

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text("匿名回复")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(TreeholeColors.textPrimary)

                HStack(spacing: 8) {
                    Text(reply.formattedDuration)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(TreeholeColors.textSecondary)

                    Text(reply.formattedDate)
                        .font(.system(size: 12))
                        .foregroundColor(TreeholeColors.textMuted)
                }
            }

            Spacer()

            // 迷你波形（播放时）
            if isPlayingThis {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(TreeholeColors.accentPrimary)
                            .frame(width: 2.5, height: 6 + CGFloat(6 * sin(Double(i) * 0.8 + player.currentTime * 8)))
                            .animation(.easeOut(duration: 0.1), value: player.currentTime)
                    }
                }
            }
        }
        .padding(14)
        .background(TreeholeColors.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
    }
}
