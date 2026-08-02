import SwiftUI

// MARK: - 树洞语音卡片（含播放控制）

struct VoiceCard: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var player = AudioPlayer.shared

    let seed: VoiceSeed

    private var isCurrentPlaying: Bool {
        guard let url = seed.audioURL else { return false }
        return player.currentURL == url && (player.status == .playing || player.status == .paused)
    }

    private var isPlayingThis: Bool {
        guard let url = seed.audioURL else { return false }
        return player.currentURL == url && player.status == .playing
    }

    var body: some View {
        VStack(spacing: 16) {
            // 生长阶段徽章
            HStack(spacing: 6) {
                GrowthIcon(stage: seed.growthStage, size: 20)
                Text("\(seed.growthStage.rawValue)阶段")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(TreeholeColors.accentPrimary)
            }

            // 波形图（播放时根据音量动态变化）
            LiveWaveformView(
                isActive: isPlayingThis,
                audioLevel: isCurrentPlaying ? player.audioLevel : 0
            )
            .frame(height: 48)

            // 进度条（播放时显示）
            if isCurrentPlaying {
                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(TreeholeColors.accentPrimary.opacity(0.15))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(TreeholeColors.accentPrimary)
                                .frame(
                                    width: geometry.size.width * CGFloat(player.progress),
                                    height: 4
                                )
                                .animation(.linear(duration: 0.1), value: player.progress)
                        }
                    }
                    .frame(height: 4)

                    HStack {
                        Text(AudioPlayer.formatTime(player.currentTime))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(TreeholeColors.textSecondary)

                        Spacer()

                        Text(AudioPlayer.formatTime(player.duration))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }
                }
                .transition(.opacity)
            }

            // 播放按钮
            Button(action: { store.playVoice(seed: seed) }) {
                ZStack {
                    Circle()
                        .fill(
                            isCurrentPlaying
                                ? TreeholeColors.accentPrimary.opacity(0.15)
                                : TreeholeColors.accentPrimary
                        )
                        .frame(width: 64, height: 64)

                    // 图标随状态切换
                    if player.status == .loading {
                        ProgressView()
                            .tint(TreeholeColors.bgPrimary)
                    } else if isPlayingThis {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 24))
                            .foregroundColor(TreeholeColors.accentPrimary)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .foregroundColor(TreeholeColors.bgPrimary)
                            .offset(x: 2)
                    }

                    // 播放中 → 环形进度
                    if isCurrentPlaying && player.status != .loading {
                        Circle()
                            .trim(from: 0, to: CGFloat(player.progress))
                            .stroke(TreeholeColors.accentPrimary, lineWidth: 2)
                            .frame(width: 72, height: 72)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.1), value: player.progress)
                    }
                }
            }
            .disabled(player.status == .loading)

            // 信息行
            Text("\(seed.formattedDate) · \(seed.formattedDuration) · \(seed.replyCount) 条回复")
                .font(.system(size: 13))
                .foregroundColor(TreeholeColors.textSecondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(TreeholeColors.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.lg))
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: player.status)
    }
}

// MARK: - 实时波形（随音量变化）

private struct LiveWaveformView: View {
    let isActive: Bool
    let audioLevel: Float

    private let barCount = 24
    private let maxHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                let normalized = CGFloat(index) / CGFloat(barCount - 1)
                let baseHeight = maxHeight * (0.3 + 0.7 * abs(sin(normalized * .pi * 2)))

                // 活动时根据音量动态调整高度
                let dynamicHeight: CGFloat = isActive
                    ? baseHeight * (0.4 + 0.6 * CGFloat(audioLevel))
                    : baseHeight

                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isActive
                            ? TreeholeColors.accentPrimary
                            : TreeholeColors.accentPrimary.opacity(0.5)
                    )
                    .frame(width: 3, height: max(4, dynamicHeight))
                    .animation(
                        isActive
                            ? .easeOut(duration: 0.08)
                            : .spring(response: 0.3),
                        value: isActive ? audioLevel : 0
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 生长阶段图标

struct GrowthIcon: View {
    let stage: GrowthStage
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            switch stage {
            case .seed:
                Ellipse()
                    .fill(TreeholeColors.growthSeed)
                    .frame(width: size * 0.6, height: size * 0.7)
                Circle()
                    .fill(TreeholeColors.accentPrimary)
                    .frame(width: size * 0.15, height: size * 0.15)
                    .offset(y: -size * 0.25)

            case .sprout:
                VStack(spacing: 0) {
                    HStack(spacing: 2) {
                        LeafShape()
                            .fill(TreeholeColors.accentPrimary)
                            .frame(width: size * 0.3, height: size * 0.35)
                            .rotationEffect(.degrees(-30))
                        LeafShape()
                            .fill(TreeholeColors.accentPrimary)
                            .frame(width: size * 0.3, height: size * 0.35)
                            .rotationEffect(.degrees(30))
                    }
                    Rectangle()
                        .fill(TreeholeColors.accentPrimary)
                        .frame(width: size * 0.08, height: size * 0.4)
                }

            case .sapling:
                VStack(spacing: 0) {
                    Circle()
                        .fill(TreeholeColors.growthSapling)
                        .frame(width: size * 0.5, height: size * 0.5)
                    Rectangle()
                        .fill(TreeholeColors.growthSapling)
                        .frame(width: size * 0.1, height: size * 0.4)
                }

            case .tree:
                VStack(spacing: 0) {
                    Circle()
                        .fill(TreeholeColors.growthTree)
                        .frame(width: size * 0.6, height: size * 0.55)
                    Rectangle()
                        .fill(TreeholeColors.growthTree)
                        .frame(width: size * 0.14, height: size * 0.35)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 叶子形状

private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.midY)
        )
        return path
    }
}
