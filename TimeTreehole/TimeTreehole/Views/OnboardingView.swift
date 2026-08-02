import SwiftUI

// MARK: - 首次启动引导页

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore

    @State private var nickname: String = ""
    @State private var selectedColor: Int = 0
    @State private var isRegistering = false

    private let nicknameSuggestions = [
        "萤火旅人", "晨雾漫步者", "星苔拾光者", "林溪听风者",
        "风铃寄信人", "月穗种树人", "松果拾叶人", "露珠寻声者",
    ]

    var body: some View {
        ZStack {
            TreeholeColors.bgPrimary.ignoresSafeArea()

            // 背景装饰
            VStack {
                Spacer()
                Circle()
                    .fill(TreeholeColors.accentPrimary.opacity(0.06))
                    .frame(width: 300, height: 300)
                    .offset(x: 80, y: 100)
            }

            ScrollView {
                VStack(spacing: 28) {
                    // Logo / 标题
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [TreeholeColors.accentPrimary, TreeholeColors.growthSapling],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 72, height: 72)
                                .shadow(color: TreeholeColors.accentPrimary.opacity(0.4), radius: 20)

                            Image(systemName: "leaf.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 40)

                        Text("时间树洞")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(TreeholeColors.textPrimary)

                        Text("在森林深处，种下你的声音")
                            .font(.system(size: 14))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }

                    // 昵称选择
                    VStack(alignment: .leading, spacing: 12) {
                        Text("给自己起个名字")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TreeholeColors.textPrimary)

                        HStack(spacing: 10) {
                            // 头像预览
                            AvatarView(nickname: nickname.isEmpty ? "?" : nickname, avatarColor: selectedColor, size: 48)

                            // 输入框
                            HStack {
                                TextField("输入昵称", text: $nickname)
                                    .font(.system(size: 16))
                                    .foregroundColor(TreeholeColors.textPrimary)
                                    .submitLabel(.done)

                                if !nickname.isEmpty {
                                    Button(action: { nickname = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(TreeholeColors.textMuted)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(TreeholeColors.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
                        }

                        // 随机昵称建议
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(nicknameSuggestions, id: \.self) { suggestion in
                                    Button(action: { nickname = suggestion }) {
                                        Text(suggestion)
                                            .font(.system(size: 12))
                                            .foregroundColor(TreeholeColors.textSecondary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(TreeholeColors.bgSurface)
                                            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                                    }
                                }
                            }
                        }
                    }

                    // 头像色选择
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选一个头像色")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(TreeholeColors.textPrimary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ForEach(AvatarColorSet.palette) { colorSet in
                                Button(action: { selectedColor = colorSet.id }) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [colorSet.primary, colorSet.secondary],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 52, height: 52)

                                        if selectedColor == colorSet.id {
                                            Circle()
                                                .stroke(Color.white, lineWidth: 3)
                                                .frame(width: 52, height: 52)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 恢复码说明
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 13))
                                .foregroundColor(TreeholeColors.accentSecondary)
                            Text("恢复码")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(TreeholeColors.accentSecondary)
                        }
                        Text("注册后将自动生成恢复码，用于换设备时找回账号。请妥善保管。")
                            .font(.system(size: 12))
                            .foregroundColor(TreeholeColors.textSecondary)
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .background(TreeholeColors.accentSecondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))

                    // 进入按钮
                    Button(action: register) {
                        HStack {
                            if isRegistering {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("进入树洞")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
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
                    .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty || isRegistering)
                    .opacity(nickname.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

                    // 恢复账号入口
                    Button(action: { store.showRecovery = true }) {
                        Text("已有账号？输入恢复码找回")
                            .font(.system(size: 13))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func register() {
        guard !nickname.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isRegistering = true
        Task {
            await store.registerUser(nickname: nickname.trimmingCharacters(in: .whitespaces), avatarColor: selectedColor)
            isRegistering = false
        }
    }
}
