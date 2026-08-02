import Foundation
import AVFoundation
import Combine

// MARK: - 语音录制引擎

@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    // MARK: - 发布属性

    /// 当前录音状态
    @Published var status: RecordStatus = .idle

    /// 已录制时长（秒）
    @Published var elapsedTime: TimeInterval = 0

    /// 当前音量级别 0.0~1.0
    @Published var audioLevel: Float = 0

    /// 录制完成后的文件 URL
    @Published var recordedFileURL: URL?

    /// 权限是否已授权
    @Published var isPermissionGranted = false

    // MARK: - 私有属性

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var meteringTimer: Timer?
    private var recordingURL: URL?

    /// 最大录制时长 180 秒
    private let maxDuration: TimeInterval = 180

    // MARK: - 状态枚举

    enum RecordStatus: Equatable {
        case idle            // 空闲
        case preparing       // 准备中
        case recording       // 录��中
        case paused          // 暂停
        case finished(URL)   // 完成
        case error(String)   // 出错
    }

    // MARK: - 单例

    static let shared = AudioRecorder()

    private override init() {
        super.init()
    }

    // MARK: - 权限

    /// 请求麦克风权限
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            isPermissionGranted = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            isPermissionGranted = granted
            return granted
        case .denied, .restricted:
            isPermissionGranted = false
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - 开始录制

    func startRecording(title: String = "语音记录") {
        guard status != .recording else { return }

        // 准备文件路径
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeTreehole", isDirectory: true)

        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordingURL = fileURL

        // 音频会话配置
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            status = .error("音频会话初始化失败: \(error.localizedDescription)")
            return
        }

        // 录音参数：AAC 128kbps, 44.1kHz
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder?.delegate = self
            recorder?.isMeteringEnabled = true
            recorder?.record(forDuration: maxDuration)

            if recorder?.record() == true {
                status = .recording
                elapsedTime = 0
                audioLevel = 0
                recordedFileURL = nil

                // 时长计时器
                timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.elapsedTime = self.recorder?.currentTime ?? 0
                    }
                }

                // 音量表更新计时器
                meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.recorder?.updateMeters()
                        let level = self.recorder?.averagePower(forChannel: 0) ?? -160
                        // 将分贝转为 0~1 比例（-60dB 约等于静音）
                        let normalized = max(0, min(1, (level + 60) / 60))
                        self.audioLevel = normalized
                    }
                }
            } else {
                status = .error("录音启动失败")
            }
        } catch {
            status = .error("录音器创建失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 停止录制

    func stopRecording() {
        guard status == .recording || status == .paused else { return }

        recorder?.stop()
        recorder = nil

        timer?.invalidate()
        timer = nil

        meteringTimer?.invalidate()
        meteringTimer = nil

        // 停用音频会话
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let url = recordingURL {
            recordedFileURL = url
            status = .finished(url)
        }
    }

    // MARK: - 暂停 / 恢复

    func pauseRecording() {
        guard status == .recording else { return }
        recorder?.pause()
        status = .paused
        timer?.invalidate()
        meteringTimer?.invalidate()
    }

    func resumeRecording() {
        guard status == .paused else { return }
        recorder?.record()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.elapsedTime = self.recorder?.currentTime ?? 0
            }
        }

        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.recorder?.updateMeters()
                let level = self.recorder?.averagePower(forChannel: 0) ?? -160
                let normalized = max(0, min(1, (level + 60) / 60))
                self.audioLevel = normalized
            }
        }

        status = .recording
    }

    // MARK: - 取消录制（丢弃）

    func cancelRecording() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil

        timer?.invalidate()
        timer = nil

        meteringTimer?.invalidate()
        meteringTimer = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        recordingURL = nil
        recordedFileURL = nil
        elapsedTime = 0
        audioLevel = 0
        status = .idle
    }

    // MARK: - 重置

    func reset() {
        timer?.invalidate()
        meteringTimer?.invalidate()
        recorder = nil
        recordingURL = nil
        recordedFileURL = nil
        elapsedTime = 0
        audioLevel = 0
        status = .idle
    }

    // MARK: - 格式化时间

    static func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.timer?.invalidate()
            self.timer = nil
            self.meteringTimer?.invalidate()
            self.meteringTimer = nil

            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

            if flag, let url = self.recordingURL {
                self.recordedFileURL = url
                self.status = .finished(url)
            } else {
                self.status = .error("录制未成功完成")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.status = .error(error?.localizedDescription ?? "编码错误")
        }
    }
}
