import SwiftUI

// MARK: - 花园语音列表项（含播放控制）

struct VoiceListItem: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var player = AudioPlayer.shared

    let seed: VoiceSeed
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    private var isCurrentPlaying: Bool {
        guard let url = seed.audioURL else { return false }
        return player.currentURL == url && (player.status == .playing || player.status == .paused)
    }

    private var isPlayingThis: Bool {
        guard let url = seed.audioURL else { return false }
        return player.currentURL == url && player.status == .playing
    }

    var body: some View {
        HStack(spacing: 12) {
            // 生长阶段图标
            GrowthIcon(stage: seed.growthStage, size: 40)

            // 信息文字
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(seed.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TreeholeColors.textPrimary)
                        .lineLimit(1)

                    Text(seed.formattedDuration)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(TreeholeColors.textSecondary)
                }

                Text(seed.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(TreeholeColors.textMuted)

                // 附加标签
                HStack(spacing: 6) {
                    PrivacyBadge(privacy: seed.privacy)
                    if seed.replyCount > 0 {
                        ReplyBadge(count: seed.replyCount)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 播放按钮
            Button(action: { store.playVoice(seed: seed) }) {
                ZStack {
                    Circle()
                        .fill(isCurrentPlaying
                            ? TreeholeColors.accentPrimary.opacity(0.15)
                            : TreeholeColors.accentPrimary.opacity(0.1)
                        )
                        .frame(width: 36, height: 36)

                    if isPlayingThis {
                        // 播放中 → 动画波形条
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(TreeholeColors.accentPrimary)
                                    .frame(width: 2.5, height: 6 + CGFloat(6 * sin(Double(i) * 0.8 + player.currentTime * 8)))
                                    .animation(.easeOut(duration: 0.1), value: player.currentTime)
                            }
                        }
                    } else {
                        Image(systemName: isCurrentPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(
                                isCurrentPlaying
                                    ? TreeholeColors.accentPrimary
                                    : TreeholeColors.accentPrimary.opacity(0.8)
                            )
                    }
                }
            }

            // 删除按钮
            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundColor(TreeholeColors.danger.opacity(0.7))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(16)
        .background(
            isCurrentPlaying
                ? TreeholeColors.accentPrimary.opacity(0.05)
                : TreeholeColors.bgSurface
        )
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
        .overlay(
            isCurrentPlaying
                ? RoundedRectangle(cornerRadius: TreeholeRadius.md)
                    .stroke(TreeholeColors.accentPrimary.opacity(0.25), lineWidth: 1)
                : nil
        )
        .alert("删除这颗种子？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { onDelete() }
        } message: {
            Text("「\(seed.title)」将被永久删除，无法恢复。")
        }
    }
}

// MARK: - 隐私标签

private struct PrivacyBadge: View {
    let privacy: VoicePrivacy

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: privacy == .private ? "lock.fill" : "globe")
                .font(.system(size: 9))
            Text(privacy.rawValue)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(privacy == .private
            ? TreeholeColors.accentSecondary
            : TreeholeColors.accentPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            (privacy == .private
                ? TreeholeColors.accentSecondary
                : TreeholeColors.accentPrimary)
                .opacity(0.15)
        )
        .clipShape(Capsule())
    }
}

// MARK: - 回复数量标签

private struct ReplyBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 9))
            Text("\(count)条回复")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(TreeholeColors.accentSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(TreeholeColors.accentSecondary.opacity(0.15))
        .clipShape(Capsule())
    }
}
