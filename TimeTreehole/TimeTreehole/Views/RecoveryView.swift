import SwiftUI

// MARK: - 设备恢复页（通过恢复码找回账号）

struct RecoveryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var codePart1: String = ""
    @State private var codePart2: String = ""
    @State private var isRecovering = false
    @State private var errorMsg: String?

    private var recoveryCode: String {
        "\(codePart1.uppercased())-\(codePart2.uppercased())"
    }

    private var isValid: Bool {
        codePart1.count == 4 && codePart2.count == 4
    }

    var body: some View {
        NavigationView {
            ZStack {
                TreeholeColors.bgPrimary.ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    // 图标
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(TreeholeColors.accentSecondary.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 34))
                                .foregroundColor(TreeholeColors.accentSecondary)
                        }

                        Text("恢复账号")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(TreeholeColors.textPrimary)

                        Text("输入你的恢复码，将账号绑定到当前设备")
                            .font(.system(size: 13))
                            .foregroundColor(TreeholeColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    // 恢复码输入
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            // 第一段
                            codeInputField(text: $codePart1, placeholder: "XXXX")

                            Text("-")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(TreeholeColors.textMuted)

                            // 第二段
                            codeInputField(text: $codePart2, placeholder: "XXXX")
                        }

                        if let errorMsg = errorMsg {
                            Text(errorMsg)
                                .font(.system(size: 12))
                                .foregroundColor(TreeholeColors.danger)
                                .transition(.opacity)
                        }
                    }

                    // 恢复按钮
                    Button(action: recover) {
                        HStack {
                            if isRecovering {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("恢复账号")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [TreeholeColors.accentSecondary, Color(hex: "C47E2E")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                        .shadow(color: TreeholeColors.accentSecondary.opacity(0.3), radius: 12)
                    }
                    .disabled(!isValid || isRecovering)
                    .opacity(!isValid ? 0.5 : 1)

                    Spacer()

                    // 说明
                    VStack(alignment: .leading, spacing: 6) {
                        Label("恢复码格式：XXXX-XXXX（8位字母数字）", systemImage: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(TreeholeColors.textMuted)
                        Text("恢复后，当前设备将绑定到原账号，灵叶和种子记录将恢复。")
                            .font(.system(size: 12))
                            .foregroundColor(TreeholeColors.textMuted)
                            .lineSpacing(3)
                    }
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(TreeholeColors.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - 输入框组件

    private func codeInputField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .foregroundColor(TreeholeColors.textPrimary)
            .multilineTextAlignment(.center)
            .textCase(.uppercase)
            .frame(width: 100, height: 56)
            .background(TreeholeColors.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: TreeholeRadius.md)
                    .stroke(isValid ? TreeholeColors.accentPrimary.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .textInputAutocapitalization(.characters)
            .disableAutocorrection(true)
            .onChange(of: text.wrappedValue) { newValue in
                let filtered = newValue.filter { $0.isLetter || $0.isNumber }.uppercased()
                text.wrappedValue = String(filtered.prefix(4))
            }
    }

    // MARK: - 恢复操作

    private func recover() {
        isRecovering = true
        errorMsg = nil
        Task {
            let success = await store.recoverAccount(recoveryCode: recoveryCode)
            isRecovering = false
            if !success {
                withAnimation { errorMsg = "恢复码无效或恢复失败，请检查后重试" }
            }
        }
    }
}
