import SwiftUI

// MARK: - 身份确认页（稳定身份 · 从 UI 上杜绝"昵称每次都变"的困惑）

/// 首次注册后或在「我的」里打开，集中展示：专属昵称（可改）、设备恢复码、稳定提示。
/// 配合后端 `formatProfile` 昵称落库（commit 55c8952）与 device_id Keychain 持久化（b01650e），
/// 明确告诉用户"这是你在这台设备上的固定身份"，不再产生名字随机变化的疑惑。
struct IdentityView: View {
    @EnvironmentObject var store: AppStore

    /// 主按钮动作：首次引导后"进入树洞" / 个人资料里"完成"
    var onEnter: () -> Void
    /// 主按钮文案
    var enterTitle: String = "进入时间树洞"
    /// 稳定提示副标题（不同入口可传不同措辞）
    var subtitle: String = "登录后昵称保持不变"

    @State private var isEditingNickname = false
    @State private var editNickname = ""
    @State private var showCopiedToast = false

    private var profile: UserProfile? { store.userProfile }

    var body: some View {
        ZStack {
            TreeholeColors.bgPrimary.ignoresSafeArea()

            // 背景柔光
            VStack {
                Spacer()
                Circle()
                    .fill(TreeholeColors.accentPrimary.opacity(0.06))
                    .frame(width: 320, height: 320)
                    .offset(x: 90, y: 120)
            }

            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    nicknameCard
                    helperText
                    recoveryCard
                    Spacer(minLength: 24)
                    enterButton
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { editNickname = profile?.nickname ?? "" }
        .overlay(alignment: .top) { copiedToast }
    }

    // MARK: - 头部

    private var headerSection: some View {
        VStack(spacing: 14) {
            AvatarView(
                nickname: profile?.nickname ?? "?",
                avatarColor: profile?.avatarColor ?? 0,
                size: 88
            )
            .overlay(
                Circle()
                    .stroke(TreeholeColors.accentGlow.opacity(0.5), lineWidth: 2)
            )

            Text("你的身份")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(TreeholeColors.textPrimary)

            Label {
                Text(subtitle)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(TreeholeColors.accentPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(TreeholeColors.accentPrimary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
        }
    }

    // MARK: - 昵称卡片

    private var nicknameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("昵称")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TreeholeColors.textSecondary)
                Spacer()
                if isEditingNickname {
                    Button("保存") { saveNickname() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(TreeholeColors.accentPrimary)
                } else {
                    Button { isEditingNickname = true } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 15))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }
                }
            }

            if isEditingNickname {
                TextField("昵称", text: $editNickname)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(TreeholeColors.textPrimary)
                    .submitLabel(.done)
                    .onSubmit { saveNickname() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(TreeholeColors.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.sm))
            } else {
                HStack(spacing: 12) {
                    AvatarView(
                        nickname: profile?.nickname ?? "?",
                        avatarColor: profile?.avatarColor ?? 0,
                        size: 36
                    )
                    Text(profile?.nickname ?? "匿名旅人")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(TreeholeColors.textPrimary)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(TreeholeColors.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
    }

    private var helperText: some View {
        Text("这是你的专属昵称，可随时修改")
            .font(.system(size: 12))
            .foregroundColor(TreeholeColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 恢复码卡片

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13))
                    .foregroundColor(TreeholeColors.accentSecondary)
                Text("设备恢复码")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TreeholeColors.textSecondary)
                Spacer()
            }

            HStack(spacing: 12) {
                if let code = profile?.recoveryCode, !code.isEmpty {
                    Text(code)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
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
                    Button(action: { Task { await store.fetchUserProfile() } }) {
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

    // MARK: - 主按钮

    private var enterButton: some View {
        Button(action: onEnter) {
            Text(enterTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [TreeholeColors.accentPrimary, TreeholeColors.growthSapling],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                .shadow(color: TreeholeColors.accentPrimary.opacity(0.3), radius: 12)
        }
    }

    private var footer: some View {
        Text("匿名账号 · 同一设备始终是你")
            .font(.system(size: 11))
            .foregroundColor(TreeholeColors.textMuted)
    }

    // MARK: - 复制提示

    private var copiedToast: some View {
        Group {
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

    // MARK: - 操作

    private func saveNickname() {
        let trimmed = editNickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isEditingNickname = false
        Task { await store.updateUserProfile(nickname: trimmed) }
    }

    private func copyRecoveryCode() {
        let code = profile?.recoveryCode ?? ""
        UIPasteboard.general.string = code
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showCopiedToast = false }
        }
    }
}
