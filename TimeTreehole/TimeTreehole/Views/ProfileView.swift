import SwiftUI

// MARK: - 个人资料 / 设置页

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editNickname = ""
    @State private var editAvatarColor = 0
    @State private var editBio = ""
    @State private var showCopiedToast = false
    @State private var showDeleteAccountConfirm = false
    @State private var accountDeleted = false

    var body: some View {
        NavigationView {
            ZStack {
                TreeholeColors.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 头像 + 昵称区
                        profileHeader

                        // 恢复码卡片
                        recoveryCodeCard

                        // 灵叶余额
                        creditsCard

                        // 设备列表
                        devicesSection

                        // 账号安全
                        deleteAccountSection

                        // 设置项
                        settingsSection

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(TreeholeColors.textSecondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("保存") { saveProfile() }
                            .foregroundColor(TreeholeColors.accentPrimary)
                            .font(.system(size: 15, weight: .semibold))
                    } else {
                        Button("编辑") { startEditing() }
                            .foregroundColor(TreeholeColors.accentPrimary)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("删除账号？", isPresented: $showDeleteAccountConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                Task {
                    let success = await store.deleteAccount()
                    if success {
                        accountDeleted = true
                        dismiss()
                    }
                }
            }
        } message: {
            Text("此操作将永久删除你的账号、所有语音种子、回复、设备和消费记录，且无法恢复。")
        }
        .onAppear {
            if store.devices.isEmpty {
                Task { await store.fetchDevices() }
            }
        }
        .overlay(alignment: .top) {
            if showCopiedToast {
                Text("已复制恢复码")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(TreeholeColors.accentPrimary.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                    .padding(.top, 50)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - 头像 + 昵称

    private var profileHeader: some View {
        VStack(spacing: 14) {
            if isEditing {
                // 编辑模式：可点击换色
                AvatarView(nickname: editNickname.isEmpty ? "?" : editNickname, avatarColor: editAvatarColor, size: 80)
                    .onTapGesture {
                        editAvatarColor = (editAvatarColor + 1) % AvatarColorSet.palette.count
                    }

                TextField("昵称", text: $editNickname)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TreeholeColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(TreeholeColors.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))

                // 色彩选择器
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(AvatarColorSet.palette) { colorSet in
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [colorSet.primary, colorSet.secondary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: editAvatarColor == colorSet.id ? 2 : 0)
                                )
                                .onTapGesture { editAvatarColor = colorSet.id }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                TextField("写一句介绍…", text: $editBio, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundColor(TreeholeColors.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(TreeholeColors.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
            } else {
                // 展示模式
                let profile = store.userProfile
                AvatarView(
                    nickname: profile?.nickname ?? "匿名",
                    avatarColor: profile?.avatarColor ?? 0,
                    size: 80
                )

                Text(profile?.nickname ?? "匿名旅人")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(TreeholeColors.textPrimary)

                if let bio = profile?.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 13))
                        .foregroundColor(TreeholeColors.textSecondary)
                        .multilineTextAlignment(.center)
                }

                if let createdAt = profile?.createdAt {
                    Text("加入于 \(createdAt.prefix(10))")
                        .font(.system(size: 11))
                        .foregroundColor(TreeholeColors.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(TreeholeColors.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.lg))
    }

    // MARK: - 恢复码卡片

    private var recoveryCodeCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13))
                    .foregroundColor(TreeholeColors.accentSecondary)
                Text("你的恢复码")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TreeholeColors.textSecondary)
                Spacer()
            }

            HStack(spacing: 12) {
                if let code = store.userProfile?.recoveryCode, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(TreeholeColors.accentSecondary)
                        .tracking(2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Spacer()

                    Button(action: copyRecoveryCode) {
                        Label("复制", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TreeholeColors.accentPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(TreeholeColors.accentPrimary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                    }
                } else {
                    Text("恢复码未生成")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(TreeholeColors.textSecondary)

                    Spacer()

                    Button(action: {
                        Task { await store.fetchUserProfile() }
                    }) {
                        Label("重新获取", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(TreeholeColors.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                    }
                }
            }
            .frame(minHeight: 44)

            Text("换设备时输入此码可找回账号")
                .font(.system(size: 11))
                .foregroundColor(TreeholeColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(TreeholeColors.accentSecondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
    }

    // MARK: - 灵叶余额

    private var creditsCard: some View {
        Button(action: { dismiss(); store.showStore = true }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("灵叶余额")
                        .font(.system(size: 12))
                        .foregroundColor(TreeholeColors.textMuted)
                    Text("🍃 \(store.credits)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(TreeholeColors.accentPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(TreeholeColors.textMuted)
            }
            .padding(16)
            .background(TreeholeColors.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
        }
    }

    // MARK: - 设备列表

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已绑定的设备")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TreeholeColors.textPrimary)
                Spacer()
                Text("\(store.devices.count)")
                    .font(.system(size: 13))
                    .foregroundColor(TreeholeColors.textMuted)
            }

            if store.devices.isEmpty {
                Text("加载中…")
                    .font(.system(size: 13))
                    .foregroundColor(TreeholeColors.textMuted)
            } else {
                ForEach(store.devices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: device.platform == "ios" ? "iphone" : "laptopcomputer")
                            .font(.system(size: 18))
                            .foregroundColor(device.isCurrent ? TreeholeColors.accentPrimary : TreeholeColors.textSecondary)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(device.model ?? device.platform)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(TreeholeColors.textPrimary)
                                if device.isCurrent {
                                    Text("当前")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(TreeholeColors.accentPrimary)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            Text("最近活跃：\(device.lastActiveAt.prefix(16))")
                                .font(.system(size: 11))
                                .foregroundColor(TreeholeColors.textMuted)
                        }

                        Spacer()

                        if !device.isCurrent {
                            Button(action: { Task { await store.unbindDevice(device) } }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundColor(TreeholeColors.danger.opacity(0.7))
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(TreeholeColors.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
                }
            }
        }
    }

    // MARK: - 账号安全（删除账号入口，置于此处便于 Apple 审核员发现）

    private var deleteAccountSection: some View {
        Button(action: { showDeleteAccountConfirm = true }) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(TreeholeColors.statusDanger)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("删除账号")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TreeholeColors.textPrimary)
                    Text("清除所有数据并退出应用")
                        .font(.system(size: 12))
                        .foregroundColor(TreeholeColors.textMuted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(TreeholeColors.textMuted)
            }
            .padding(16)
            .background(TreeholeColors.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
        }
    }

    // MARK: - 设置项

    private var settingsSection: some View {
        VStack(spacing: 0) {
            settingsRow(icon: "arrow.triangle.2.circlepath", title: "恢复账号", subtitle: "换设备时使用") {
                dismiss()
                store.showRecovery = true
            }
            Divider().background(TreeholeColors.borderSubtle)
            settingsRow(icon: "hand.raised.fill", title: "隐私政策", subtitle: nil) {}
            Divider().background(TreeholeColors.borderSubtle)
            settingsRow(icon: "doc.text.fill", title: "用户协议", subtitle: nil) {}
            Divider().background(TreeholeColors.borderSubtle)
            settingsRow(icon: "info.circle.fill", title: "关于时间树洞", subtitle: "v1.0.0") {}
        }
        .background(TreeholeColors.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
    }

    private func settingsRow(icon: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(TreeholeColors.textSecondary)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(TreeholeColors.textPrimary)

                Spacer()

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(TreeholeColors.textMuted)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(TreeholeColors.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - 操作

    private func startEditing() {
        editNickname = store.userProfile?.nickname ?? ""
        editAvatarColor = store.userProfile?.avatarColor ?? 0
        editBio = store.userProfile?.bio ?? ""
        isEditing = true
    }

    private func saveProfile() {
        isEditing = false
        Task {
            await store.updateUserProfile(
                nickname: editNickname,
                avatarColor: editAvatarColor,
                bio: editBio
            )
        }
    }

    private func copyRecoveryCode() {
        let code = store.userProfile?.recoveryCode ?? ""
        UIPasteboard.general.string = code
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showCopiedToast = false }
        }
    }
}
