import Foundation
import Combine
import SwiftUI
import StoreKit

// MARK: - 应用状态管理（网络版 · 含灵叶额度系统 + App Store IAP）

@MainActor
class AppStore: ObservableObject {

    // MARK: - 数据源

    @Published var mySeeds: [VoiceSeed] = []
    @Published var notifications: [TreeholeNotification] = []
    @Published var selectedTab: Tab = .home

    // MARK: - 用户系统

    @Published var userProfile: UserProfile?
    @Published var devices: [DeviceInfo] = []
    @Published var isRegistered = false
    @Published var showOnboarding = false
    @Published var showRecovery = false
    @Published var showProfile = false

    // MARK: - 树洞状态

    @Published var currentRandomSeed: VoiceSeed?
    @Published var seenSeedUUIDs: [String] = []
    @Published var treeholeStats: (public: Int, total: Int) = (0, 0)

    // MARK: - 灵叶额度

    @Published var credits: Int = 0
    @Published var dailyUploads: Int = 0
    @Published var dailyRetrievals: Int = 0
    @Published var maxDailyUploads: Int = 1
    @Published var maxDailyRetrievals: Int = 1
    @Published var costExtraUpload: Int = 10
    @Published var costExtraRetrieval: Int = 5

    /// 是否显示灵叶商店
    @Published var showStore = false

    // MARK: - 加载状态

    @Published var isLoadingSeeds = false
    @Published var isLoadingTreehole = false
    @Published var isLoadingNotifications = false
    @Published var isUploading = false

    // MARK: - 录音相关

    @Published var isRecording = false
    @Published var showSaveDialog = false
    @Published var isPlaying = false
    @Published var pendingPrivacy: VoicePrivacy = .private

    @ObservedObject var recorder = AudioRecorder.shared
    @ObservedObject var player   = AudioPlayer.shared

    // MARK: - Toast

    @Published var toastMessage: String?
    @Published var showToast = false

    // MARK: - 计算属性

    var totalSeeds: Int { mySeeds.count }
    var sproutedSeeds: Int { mySeeds.filter { $0.growthStage != .seed }.count }
    var unreadNotifications: Int { notifications.filter { !$0.isRead }.count }

    /// 免费上传是否已用完
    var uploadQuotaExhausted: Bool { dailyUploads >= maxDailyUploads }

    /// 免费获取是否已用完
    var retrievalQuotaExhausted: Bool { dailyRetrievals >= maxDailyRetrievals }

    /// 是否有足够灵叶再来一次上传
    var canAffordExtraUpload: Bool { credits >= costExtraUpload }

    /// 是否有足够灵叶再来一次获取
    var canAffordExtraRetrieval: Bool { credits >= costExtraRetrieval }

    var formattedElapsedTime: String {
        AudioRecorder.formatTime(recorder.elapsedTime)
    }

    // MARK: - 初始化与数据加载

    private let api = APIClient.shared
    private let iapManager = IAPManager.shared
    private var refreshTask: Task<Void, Never>?
    private var iapObserver: NSObjectProtocol?

    init() {
        Task {
            await checkRegistration()
            await loadAllData()
        }

        // 监听 IAP 充值成功通知（外部交易 / 恢复购买）
        iapObserver = NotificationCenter.default.addObserver(
            forName: .iapCreditsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let credits = notification.userInfo?["credits"] as? Int
            let added = notification.userInfo?["added"] as? Int
            Task { @MainActor in
                if let credits {
                    self.credits = credits
                }
                if let added, added > 0 {
                    self.showToast("充值成功！获得 \(added) 灵叶 🍃")
                }
            }
        }
    }

    // MARK: - 用户注册与资料

    /// 检查是否已注册，未注册则显示引导页
    func checkRegistration() async {
        let registered = UserDefaults.standard.bool(forKey: "com.timetreehole.registered")
        if registered {
            isRegistered = true
            await fetchUserProfile()
        } else {
            showOnboarding = true
        }
    }

    /// 首次注册匿名账号
    func registerUser(nickname: String? = nil, avatarColor: Int? = nil) async {
        do {
            let profile = try await api.registerUser(nickname: nickname, avatarColor: avatarColor)
            UserDefaults.standard.set(true, forKey: "com.timetreehole.registered")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                userProfile = profile
                isRegistered = true
                credits = profile.credits
            }
            showOnboarding = false
            showToast("欢迎来到时间树洞 🌱")
        } catch {
            // 注册失败仍然允许使用（离线模式）
            showOnboarding = false
            isRegistered = true
            UserDefaults.standard.set(true, forKey: "com.timetreehole.registered")
        }
    }

    /// 获取用户资料
    func fetchUserProfile() async {
        do {
            let profile = try await api.getUserProfile()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                userProfile = profile
                credits = profile.credits
            }
        } catch { /* 静默失败 */ }
    }

    /// 更新用户资料
    func updateUserProfile(nickname: String? = nil, avatarColor: Int? = nil, bio: String? = nil) async {
        do {
            let profile = try await api.updateUserProfile(nickname: nickname, avatarColor: avatarColor, bio: bio)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                userProfile = profile
            }
            showToast("资料已更新")
        } catch {
            showToast("更新失败，请稍后再试")
        }
    }

    /// 通过恢复码恢复账号
    func recoverAccount(recoveryCode: String) async -> Bool {
        do {
            let profile = try await api.recoverAccount(recoveryCode: recoveryCode)
            UserDefaults.standard.set(true, forKey: "com.timetreehole.registered")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                userProfile = profile
                credits = profile.credits
                isRegistered = true
            }
            showRecovery = false
            await loadAllData()
            showToast("账号恢复成功！欢迎回来 🌿")
            return true
        } catch let error as APIError {
            if case .httpError(let code, _) = error, code == 409 {
                // 需要确认覆盖
                showToast("当前设备已有数据，确认覆盖？")
                return false
            } else if case .httpError(let code, _) = error, code == 404 {
                showToast("恢复码无效，请检查后重试")
            } else {
                showToast("恢复失败，请稍后再试")
            }
            return false
        } catch {
            showToast("网络不可用")
            return false
        }
    }

    /// 确认恢复（覆盖当前设备数据）
    func confirmRecovery(recoveryCode: String) async -> Bool {
        do {
            let profile = try await api.confirmRecovery(recoveryCode: recoveryCode)
            UserDefaults.standard.set(true, forKey: "com.timetreehole.registered")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                userProfile = profile
                credits = profile.credits
            }
            showRecovery = false
            await loadAllData()
            showToast("账号恢复成功！")
            return true
        } catch {
            showToast("恢复失败，请稍后再试")
            return false
        }
    }

    /// 获取设备列表
    func fetchDevices() async {
        do {
            let devs = try await api.getDevices()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                devices = devs
            }
        } catch { /* 静默 */ }
    }

    /// 解绑设备
    func unbindDevice(_ device: DeviceInfo) async {
        do {
            try await api.unbindDevice(deviceId: device.id)
            withAnimation {
                devices.removeAll { $0.id == device.id }
            }
            showToast("设备已解绑")
        } catch {
            showToast("解绑失败，请稍后再试")
        }
    }

    // MARK: - 举报 / 屏蔽 / 账号删除

    /// 举报当前公共树洞种子
    func reportCurrentSeed(reason: String? = nil) async {
        guard let seed = currentRandomSeed, let uuid = seed.serverUUID else {
            showToast("当前没有可举报的内容")
            return
        }
        do {
            try await api.reportSeed(seedUuid: uuid, reason: reason)
            showToast("举报已提交，我们会尽快处理")
        } catch {
            showToast("举报提交失败，请稍后再试")
        }
    }

    /// 屏蔽当前公共树洞种子的作者
    func blockCurrentSeedAuthor() async {
        guard let seed = currentRandomSeed, let authorId = seed.authorUserId else {
            showToast("无法获取作者信息")
            return
        }
        do {
            try await api.blockUser(userId: authorId)
            currentRandomSeed = nil
            showToast("已屏蔽该用户，换一颗听听吧")
            await fetchRandomSeed()
        } catch {
            showToast("屏蔽失败，请稍后再试")
        }
    }

    /// 删除账号并清空本地状态
    func deleteAccount() async -> Bool {
        do {
            try await api.deleteAccount()
            // 清理本地状态
            UserDefaults.standard.removeObject(forKey: "com.timetreehole.registered")
            mySeeds = []
            notifications = []
            userProfile = nil
            devices = []
            credits = 0
            currentRandomSeed = nil
            isRegistered = false
            showOnboarding = true
            showToast("账号已删除，感谢曾经的陪伴 🍂")
            return true
        } catch {
            showToast("账号删除失败，请稍后再试")
            return false
        }
    }

    /// 首次加载 / 下拉刷新
    func loadAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchMySeeds() }
            group.addTask { await self.fetchNotifications() }
            group.addTask { await self.fetchTreeholeStats() }
            group.addTask { await self.fetchQuota() }
            group.addTask { await self.fetchUserProfile() }
        }
    }

    // MARK: - 灵叶额度

    func fetchQuota() async {
        do {
            let info = try await api.fetchQuota()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                credits           = info.credits
                dailyUploads      = info.dailyUploads
                dailyRetrievals   = info.dailyRetrievals
                maxDailyUploads   = info.maxDailyUploads
                maxDailyRetrievals = info.maxDailyRetrievals
                costExtraUpload   = info.costExtraUpload
                costExtraRetrieval = info.costExtraRetrieval
            }
        } catch {
            // 网络失败时保持上次缓存的额度
        }
    }

    /// 通过 App Store IAP 充值灵叶
    /// - Parameters:
    ///   - packageId: 后端套餐 ID（small / medium / large）
    ///   - product: 对应的 StoreKit Product（含价格等本地化信息）
    func purchaseIAP(packageId: String, product: Product) async {
        // 触发购买
        await iapManager.purchase(product: product)

        // 根据购买结果处理 UI 反馈
        switch iapManager.purchaseState {
        case .success(let credits, let total):
            self.credits = total
            showToast("充值成功！获得 \(credits) 灵叶 🍃")
            iapManager.reset()

        case .failed(let reason):
            showToast(reason)
            iapManager.reset()

        case .restored(let count):
            showToast("已恢复 \(count) 笔购买记录")
            await fetchQuota()
            iapManager.reset()

        default:
            break
        }
    }

    /// 恢复购买
    func restorePurchases() async {
        await iapManager.restorePurchases()

        switch iapManager.purchaseState {
        case .restored(let count):
            if count > 0 {
                await fetchQuota()
                showToast("已恢复 \(count) 笔购买")
            } else {
                showToast("没有可恢复的购买记录")
            }
            iapManager.reset()

        case .failed(let reason):
            showToast(reason)
            iapManager.reset()

        default:
            break
        }
    }

    /// 加载 IAP 产品
    func loadIAPProducts() async {
        await iapManager.loadProducts()
    }

    // MARK: - 旧版模拟充值（保留兼容）

    func rechargeCredits(packageId: String) async {
        do {
            let result = try await api.recharge(packageId: packageId)
            if result.success {
                credits = result.totalCredits ?? credits
                showToast("充值成功！获得 \(result.addedCredits ?? 0) 灵叶 🍃")
            } else {
                showToast("充值失败，请稍后再试")
            }
        } catch {
            showToast("网络不可用，充值失败")
        }
    }

    // MARK: - 拉取我的种子

    func fetchMySeeds() async {
        isLoadingSeeds = true
        defer { isLoadingSeeds = false }

        do {
            let seeds = try await api.fetchMySeeds()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                mySeeds = seeds
            }
        } catch {
            if mySeeds.isEmpty {
                mySeeds = VoiceSeed.samples
                showToast("网络不可用，显示本地数据")
            }
        }
    }

    // MARK: - 录音操作

    func beginRecording() {
        Task {
            let granted = await recorder.requestPermission()
            if granted {
                recorder.startRecording(title: "语音种子")
                isRecording = true
            } else {
                showToast("需要麦克风权限才能录音，请在设置中开启")
            }
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        recorder.stopRecording()
        isRecording = false
        showSaveDialog = true
    }

    /// 保存语音种子（上传到服务器，含额度校验）
    func saveRecording(title: String, privacy: VoicePrivacy) {
        guard let fileURL = recorder.recordedFileURL else {
            showToast("录音保存失败")
            return
        }

        Task {
            isUploading = true
            showSaveDialog = false

            do {
                let audioData = try Data(contentsOf: fileURL)
                let result = try await api.uploadSeed(
                    audioData: audioData,
                    title: title.isEmpty ? "语音种子" : title,
                    duration: recorder.elapsedTime,
                    privacy: privacy
                )

                // 保存音频到本地缓存
                let docsDir = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)
                    .first!
                    .appendingPathComponent("VoiceSeeds", isDirectory: true)
                try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
                let localURL = docsDir.appendingPathComponent("\(result.uuid).m4a")
                try? audioData.write(to: localURL)

                let seed = VoiceSeed(
                    id: UUID(),
                    title: title.isEmpty ? "语音种子" : title,
                    duration: recorder.elapsedTime,
                    privacy: privacy,
                    replyCount: 0,
                    createdAt: Date(),
                    audioURL: localURL,
                    serverUUID: result.uuid
                )

                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    mySeeds.insert(seed, at: 0)
                }

                recorder.reset()
                pendingPrivacy = .private

                // 刷新额度和统计
                await fetchQuota()
                await fetchTreeholeStats()

                // 提示信息区分免费/付费
                if privacy == .public, let creditsUsed = result.creditsUsed, creditsUsed > 0 {
                    showToast("种子已种下 🌱 (消耗 \(creditsUsed) 灵叶)")
                } else {
                    showToast("种子已种下 🌱")
                }

            } catch let error as APIError {
                if case .httpError(let code, _) = error, code == 402 {
                    // 402 → 额度不足，引导充值
                    showToast("灵叶不足！前往商店充值 →")
                    showStore = true
                    recSaveLocalFallback(title: title, privacy: privacy, fileURL: fileURL)
                } else {
                    recSaveLocalFallback(title: title, privacy: privacy, fileURL: fileURL)
                }
            } catch {
                recSaveLocalFallback(title: title, privacy: privacy, fileURL: fileURL)
            }

            isUploading = false
        }
    }

    /// 上传失败的本地兜底保存
    private func recSaveLocalFallback(title: String, privacy: VoicePrivacy, fileURL: URL) {
        let docsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("VoiceSeeds", isDirectory: true)
        try? FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        let localURL = docsDir.appendingPathComponent(fileURL.lastPathComponent)
        try? FileManager.default.moveItem(at: fileURL, to: localURL)

        let seed = VoiceSeed(
            id: UUID(),
            title: title.isEmpty ? "语音种子" : title,
            duration: recorder.elapsedTime,
            privacy: privacy,
            replyCount: 0,
            createdAt: Date(),
            audioURL: localURL
        )

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            mySeeds.insert(seed, at: 0)
        }

        recorder.reset()
        pendingPrivacy = .private
        showToast("已保存到本地，连接恢复后自动上传")
    }

    func discardRecording() {
        recorder.cancelRecording()
        isRecording = false
        showSaveDialog = false
        pendingPrivacy = .private
    }

    // MARK: - 语音播放

    func playVoice(seed: VoiceSeed) {
        guard let url = seed.audioURL else {
            showToast("音频文件不存在")
            return
        }

        if !FileManager.default.fileExists(atPath: url.path), let serverUUID = seed.serverUUID {
            Task {
                do {
                    let data = try await api.downloadAudio(uuid: serverUUID)
                    try? data.write(to: url)
                    playLocalFile(at: url)
                } catch {
                    showToast("音频加载失败")
                }
            }
            return
        }

        playLocalFile(at: url)
    }

    private func playLocalFile(at url: URL) {
        if player.status == .playing, player.currentURL == url {
            player.pause()
            isPlaying = false
            return
        }
        if player.status == .paused, player.currentURL == url {
            player.resume()
            isPlaying = true
            return
        }
        player.play(url: url)
        isPlaying = true
    }

    func stopPlayback() {
        player.stop()
        isPlaying = false
    }

    // MARK: - 删除种子

    func deleteSeed(_ seed: VoiceSeed) {
        if let url = seed.audioURL {
            try? FileManager.default.removeItem(at: url)
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            mySeeds.removeAll { $0.id == seed.id }
        }

        if let serverUUID = seed.serverUUID {
            Task {
                try? await api.deleteSeed(uuid: serverUUID)
            }
        }
    }

    // MARK: - 修改种子私密/公域属性

    /// 切换种子的私密/公域属性
    /// - 私密 → 公域：重新走上传配额（扣 10 灵叶 或 用每日免费额度），失败引导充值
    /// - 公域 → 私密：直接改，不退回灵叶
    func setSeedPrivacy(seed: VoiceSeed, privacy: VoicePrivacy) async {
        guard let uuid = seed.serverUUID else {
            showToast("该种子尚未上传，无法修改属性")
            return
        }

        // 属性未变化
        if seed.privacy == privacy { return }

        do {
            let result = try await api.updateSeedPrivacy(uuid: uuid, privacy: privacy)

            if result.success {
                // 更新本地列表中的该种子属性
                if let idx = mySeeds.firstIndex(where: { $0.id == seed.id }) {
                    mySeeds[idx].privacy = privacy
                }
                // 私密→公域可能扣了灵叶，刷新余额与配额
                await fetchQuota()

                if let msg = result.message, !msg.isEmpty {
                    showToast(msg)
                } else {
                    showToast(privacy == .public ? "种子已发布到公共域 🌿" : "已收回为私密种子 🔒")
                }
            } else {
                showToast(result.message ?? "修改失败，请稍后再试")
            }
        } catch let error as APIError {
            if case .httpError(let code, _) = error, code == 402 {
                // 额度不足，引导充值
                showToast("灵叶不足！前往商店充值 →")
                showStore = true
            } else {
                showToast("修改失败，请稍后再试")
            }
        } catch {
            showToast("网络不可用，修改失败")
        }
    }

    // MARK: - 树洞（公共域）

    /// 随机获取一颗种子（含额度检查）
    func fetchRandomSeed() async {
        isLoadingTreehole = true
        defer { isLoadingTreehole = false }

        do {
            if let seed = try await api.fetchRandomSeed(excludeUUIDs: seenSeedUUIDs) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    currentRandomSeed = seed
                }
                if let uuid = seed.serverUUID {
                    seenSeedUUIDs.append(uuid)
                }
                // 刷新额度（免费或扣费后更新）
                await fetchQuota()
            } else {
                showToast("树洞里暂时没有新的种子了")
            }
        } catch let error as APIError {
            if case .httpError(let code, _) = error, code == 402 {
                // 额度不足
                showToast("灵叶不足！前往商店充值 →")
                showStore = true
            } else {
                showToast("网络不可用，请稍后再试")
            }
        } catch {
            showToast("网络不可用，请稍后再试")
        }
    }

    /// 匿名评论
    func replyToSeed(seed: VoiceSeed, audioData: Data) async {
        guard let serverUUID = seed.serverUUID else {
            showToast("无法评论：种子数据异常")
            return
        }

        do {
            let success = try await api.replyToSeed(seedUUID: serverUUID, audioData: audioData)
            if success {
                showToast("评论已投递到树洞 🌿")
                if let updated = try? await api.fetchSeed(uuid: serverUUID) {
                    currentRandomSeed = updated
                }
            } else {
                showToast("评论发送失败")
            }
        } catch {
            showToast("网络不可用，评论发送失败")
        }
    }

    /// 树洞统计
    func fetchTreeholeStats() async {
        do {
            let stats = try await api.fetchTreeholeStats()
            treeholeStats = (stats.totalPublic, stats.totalSeeds)
        } catch { /* 静默失败 */ }
    }

    // MARK: - 通知

    func fetchNotifications() async {
        isLoadingNotifications = true
        defer { isLoadingNotifications = false }

        do {
            let notifs = try await api.fetchNotifications()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                notifications = notifs
            }
        } catch {
            if notifications.isEmpty {
                notifications = TreeholeNotification.samples
            }
        }
    }

    func markNotificationRead(_ notification: TreeholeNotification) {
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
    }

    func markAllNotificationsRead() {
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        Task {
            try? await api.markAllRead()
        }
    }

    // MARK: - 推送注册

    func registerPushToken(_ token: String) {
        Task {
            try? await api.registerPushToken(token)
        }
    }

    // MARK: - Toast

    func showToast(_ message: String) {
        toastMessage = message
        showToast = true
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation {
                showToast = false
                toastMessage = nil
            }
        }
    }
}

// MARK: - Tab 枚举

enum Tab: String, CaseIterable {
    case home     = "录音"
    case treehole = "树洞"
    case messages = "消息"
    case garden   = "我的"

    var iconName: String {
        switch self {
        case .home:     return "mic.fill"
        case .treehole: return "leaf.fill"
        case .messages: return "bell.fill"
        case .garden:   return "person.fill"
        }
    }
}
