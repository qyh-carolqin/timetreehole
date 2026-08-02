import SwiftUI

// MARK: - 种子形录制按钮（含长按录音手势）

struct SeedButton: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var recorder = AudioRecorder.shared

    /// 最小录制时长要求（秒），短于此时间视为无效
    private let minRecordDuration: TimeInterval = 1.0

    var body: some View {
        VStack(spacing: 18) {
            // ---- 录音时长显示 ----
            if recorder.status == .recording || recorder.status == .paused {
                VStack(spacing: 6) {
                    Text(store.formattedElapsedTime)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(TreeholeColors.accentPrimary)
                        .contentTransition(.numericText())

                    // 实时音量指示器
                    HStack(spacing: 4) {
                        ForEach(0..<20, id: \.self) { i in
                            let threshold = Float(i) / 20.0
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(
                                    recorder.audioLevel > threshold
                                        ? TreeholeColors.accentPrimary
                                        : TreeholeColors.accentPrimary.opacity(0.2)
                                )
                                .frame(width: 2.5, height: 10 + CGFloat(i % 5) * 4)
                        }
                    }
                    .animation(.easeOut(duration: 0.05), value: recorder.audioLevel)
                }
                .transition(.scale.combined(with: .opacity))
            }

            // ---- 种子主体按钮 ----
            ZStack {
                // 外发光（录制中时脉冲动画）
                if recorder.status == .recording {
                    PulsingGlow()
                        .frame(width: 150, height: 150)
                } else {
                    Circle()
                        .fill(TreeholeColors.accentPrimary.opacity(0.2))
                        .frame(width: 130, height: 130)
                        .blur(radius: 18)
                }

                // 主体椭圆
                Ellipse()
                    .fill(
                        recorder.status == .recording
                            ? LinearGradient.recordingPulse
                            : LinearGradient.seedGlow
                    )
                    .frame(width: 78, height: 100)
                    .scaleEffect(recorder.status == .recording ? 1.05 : 1.0)
                    .animation(
                        recorder.status == .recording
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .spring(response: 0.3, dampingFraction: 0.6),
                        value: recorder.status
                    )

                // 高光
                Ellipse()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 40, height: 20)
                    .offset(y: -18)
                    .blur(radius: 4)

                // 麦克风图标
                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundColor(
                        recorder.status == .recording
                            ? Color.white
                            : TreeholeColors.textPrimary
                    )
                    .scaleEffect(recorder.status == .recording ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: recorder.status)
            }
            .shadow(
                color: recorder.status == .recording
                    ? TreeholeColors.accentPrimary.opacity(0.6)
                    : TreeholeColors.accentPrimary.opacity(0.35),
                radius: recorder.status == .recording ? 48 : 36
            )
            // ---- 长按手势 ----
            .gesture(
                LongPressGesture(minimumDuration: 0.15)
                    .onEnded { _ in
                        let feedback = UIImpactFeedbackGenerator(style: .medium)
                        feedback.impactOccurred()
                        store.beginRecording()
                    }
                    .sequenced(before: DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            // 松手 → 停止录制
                            if recorder.elapsedTime < minRecordDuration {
                                // 太短，自动放弃
                                store.discardRecording()
                                store.showToast("录制时间太短，已取消")
                            } else {
                                store.finishRecording()
                            }
                        }
                    )
            )

            // ---- 提示文字 ----
            VStack(spacing: 4) {
                switch recorder.status {
                case .idle:
                    Text("按住录制")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.textSecondary)

                case .preparing:
                    Text("准备中…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.accentPrimary)

                case .recording:
                    Text("松手完成录制")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.accentPrimary)

                case .paused:
                    Text("已暂停 · 松手完成")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.accentSecondary)

                case .finished:
                    Text("录制完成 ✓")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.accentPrimary)

                case .error(let msg):
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(TreeholeColors.statusDanger)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: recorder.status)
    }

    // MARK: - 根据状态切换图标

    private var iconName: String {
        switch recorder.status {
        case .idle, .preparing:
            return "mic.fill"
        case .recording:
            return "waveform"
        case .paused:
            return "pause.fill"
        case .finished:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - 脉冲发光动画

private struct PulsingGlow: View {
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.4

    var body: some View {
        Circle()
            .fill(TreeholeColors.accentPrimary)
            .opacity(opacity)
            .scaleEffect(scale)
            .blur(radius: 20)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.15
                    opacity = 0.15
                }
            }
    }
}
