import Foundation
import AVFoundation
import Combine

// MARK: - 语音播放引擎

@MainActor
final class AudioPlayer: NSObject, ObservableObject {

    // MARK: - 发布属性

    @Published var status: PlayStatus = .idle

    /// 当前播放进度 (0.0 ~ 1.0)
    @Published var progress: Double = 0

    /// 当前播放时间（秒）
    @Published var currentTime: TimeInterval = 0

    /// 总时长（秒）
    @Published var duration: TimeInterval = 0

    /// 音量级别 0.0~1.0（播放时模拟显示）
    @Published var audioLevel: Float = 0

    // MARK: - 私有属性

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private var levelTimer: Timer?
    private var currentURL: URL?

    // MARK: - 状态枚举

    enum PlayStatus: Equatable {
        case idle
        case loading
        case playing
        case paused
        case finished
        case error(String)
    }

    // MARK: - 单例

    static let shared = AudioPlayer()

    private override init() {
        super.init()
    }

    // MARK: - 播放

    /// 加载并播��指定 URL 的音频
    func play(url: URL) {
        // 如果已经在播同一个文件，则暂停
        if let current = currentURL, current == url, status == .playing {
            pause()
            return
        }

        // 停止当前播放
        stop()

        currentURL = url

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.isMeteringEnabled = true
            player?.prepareToPlay()

            duration = player?.duration ?? 0

            guard player?.play() == true else {
                status = .error("播放失败")
                return
            }

            status = .playing

            // 进度更新计时器
            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    guard let player = self.player else { return }
                    self.currentTime = player.currentTime
                    self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
                }
            }

            // 音量表更新（模拟波形动画）
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.player?.updateMeters()
                    let level = self.player?.averagePower(forChannel: 0) ?? -160
                    let normalized = max(0, min(1, (level + 60) / 60))
                    self.audioLevel = normalized
                }
            }
        } catch {
            status = .error("无法播放: \(error.localizedDescription)")
        }
    }

    // MARK: - 暂停

    func pause() {
        guard status == .playing else { return }
        player?.pause()
        status = .paused
        progressTimer?.invalidate()
        levelTimer?.invalidate()
    }

    // MARK: - 恢复播放

    func resume() {
        guard status == .paused else { return }
        player?.play()
        status = .playing

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let player = self.player else { return }
                self.currentTime = player.currentTime
                self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
            }
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.player?.updateMeters()
                let level = self.player?.averagePower(forChannel: 0) ?? -160
                let normalized = max(0, min(1, (level + 60) / 60))
                self.audioLevel = normalized
            }
        }
    }

    // MARK: - 停止

    func stop() {
        player?.stop()
        player = nil
        currentURL = nil

        progressTimer?.invalidate()
        progressTimer = nil

        levelTimer?.invalidate()
        levelTimer = nil

        progress = 0
        currentTime = 0
        duration = 0
        audioLevel = 0

        if status != .finished {
            status = .idle
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 跳转到指定位置

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
        progress = duration > 0 ? time / duration : 0
    }

    // MARK: - 格式化时间

    static func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.progressTimer?.invalidate()
            self.progressTimer = nil
            self.levelTimer?.invalidate()
            self.levelTimer = nil

            self.progress = 1.0
            self.currentTime = self.duration
            self.status = flag ? .finished : .error("播放异常终止")

            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.status = .error(error?.localizedDescription ?? "解码错误")
        }
    }
}
