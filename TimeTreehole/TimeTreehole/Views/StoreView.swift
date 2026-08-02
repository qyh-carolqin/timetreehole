import SwiftUI
import StoreKit

// MARK: - 灵叶商店 · 充值页面（App Store IAP）

struct StoreView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var iap = IAPManager.shared

    @State private var purchasingPackageId: String?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // 标题
                    VStack(alignment: .leading, spacing: 4) {
                        Text("灵叶商店")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(TreeholeColors.textPrimary)
                        Text("灵叶是树洞的能量，用来播种和发现更多故事")
                            .font(.system(size: 14))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }
                    .padding(.top, 12)

                    // 余额卡片
                    balanceCard

                    // 今日配额
                    dailyQuotaSection

                    // 充值套餐
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("充值灵叶")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(TreeholeColors.textPrimary)

                            Spacer()

                            // 恢复购买按钮
                            Button(action: {
                                Task { await store.restorePurchases() }
                            }) {
                                Text("恢复购买")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(TreeholeColors.accentPrimary)
                            }
                            .disabled(isBusy)
                        }

                        if case .loading = iap.purchaseState {
                            // 加载中
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: TreeholeColors.accentPrimary))
                                Text("加载商品信息...")
                                    .font(.system(size: 14))
                                    .foregroundColor(TreeholeColors.textSecondary)
                                Spacer()
                            }
                            .padding(.vertical, 32)
                        } else if case .failed(let reason) = iap.purchaseState, iap.loadedProducts.isEmpty {
                            // 加载失败
                            VStack(spacing: 8) {
                                Text(reason)
                                    .font(.system(size: 14))
                                    .foregroundColor(TreeholeColors.textSecondary)
                                    .multilineTextAlignment(.center)

                                Button("重试") {
                                    Task { await iap.loadProducts() }
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(TreeholeColors.accentPrimary)
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                        } else {
                            // 显示产品列表
                            ForEach(sortedProducts(), id: \.id) { product in
                                productCard(product)
                            }
                        }
                    }

                    // 说明文字
                    VStack(alignment: .leading, spacing: 6) {
                        Text("灵叶使用规则")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TreeholeColors.textSecondary)

                        VStack(alignment: .leading, spacing: 4) {
                            ruleRow("🌱", "上传种子到公共域：10 灵叶 / 次")
                            ruleRow("🔍", "从公共域获取种子：5 灵叶 / 次")
                            ruleRow("🎁", "每天免费上传 1 次 + 获取 1 次")
                            ruleRow("🔄", "每日免费额度每天 0:00 重置")
                        }
                    }
                    .padding(16)
                    .background(TreeholeColors.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }

            // Toast
            if store.showToast, let msg = store.toastMessage {
                toastOverlay(message: msg)
            }
        }
        .background(TreeholeColors.bgPrimary.ignoresSafeArea())
        .task {
            // 首次进入商店时加载产品
            await iap.loadProducts()
        }
    }

    // MARK: - 余额卡片

    private var balanceCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的灵叶")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(TreeholeColors.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(store.credits)")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(TreeholeColors.accentPrimary)

                        Text("灵叶")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(TreeholeColors.textSecondary)
                    }
                }

                Spacer()

                // 装饰叶子
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(TreeholeColors.accentPrimary.opacity(0.6))
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [
                    TreeholeColors.accentPrimary.opacity(0.12),
                    TreeholeColors.bgSurface,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: TreeholeRadius.lg)
                .stroke(TreeholeColors.accentPrimary.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 每日配额

    private var dailyQuotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日配额")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(TreeholeColors.textPrimary)

            VStack(spacing: 10) {

                quotaRow(
                    label: "上传到公共域",
                    icon: "arrow.up.circle.fill",
                    used: store.dailyUploads,
                    max: store.maxDailyUploads,
                    cost: store.costExtraUpload
                )

                Divider().background(TreeholeColors.borderSubtle)

                quotaRow(
                    label: "从公共域获取",
                    icon: "arrow.down.circle.fill",
                    used: store.dailyRetrievals,
                    max: store.maxDailyRetrievals,
                    cost: store.costExtraRetrieval
                )
            }
            .padding(16)
            .background(TreeholeColors.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
        }
    }

    private func quotaRow(label: String, icon: String, used: Int, max: Int, cost: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(
                    used >= max
                        ? TreeholeColors.accentSecondary
                        : TreeholeColors.accentPrimary
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(TreeholeColors.textPrimary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(TreeholeColors.borderSubtle)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                used >= max
                                    ? TreeholeColors.accentSecondary
                                    : TreeholeColors.accentPrimary
                            )
                            .frame(width: geo.size.width * CGFloat(min(used, max)) / CGFloat(max), height: 6)
                            .animation(.spring(response: 0.5), value: used)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text("\(used)/\(max) 次免费")
                        .font(.system(size: 11))
                        .foregroundColor(TreeholeColors.textMuted)

                    Spacer()

                    if used >= max {
                        Text("再次需 \(cost) 灵叶")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TreeholeColors.accentSecondary)
                    }
                }
            }
        }
    }

    // MARK: - 产品卡片（使用 StoreKit Product 数据）

    private func productCard(_ product: Product) -> some View {
        let isPopular = IAPProduct.match(productID: product.id)?.packageId == "medium"
        let isThisPurchasing = purchasingPackageId == product.id && isBusy

        return Button(action: {
            purchase(product)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(TreeholeColors.textPrimary)

                        if isPopular {
                            Text("热门")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(TreeholeColors.bgPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(TreeholeColors.accentSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                        }
                    }

                    Text(product.description)
                        .font(.system(size: 13))
                        .foregroundColor(TreeholeColors.textSecondary)
                }

                Spacer()

                if isThisPurchasing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: TreeholeColors.accentPrimary))
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(TreeholeColors.accentPrimary)

                        if let credits = IAPProduct.match(productID: product.id)?.credits {
                            Text("\(credits) 灵叶")
                                .font(.system(size: 12))
                                .foregroundColor(TreeholeColors.textMuted)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                isPopular
                    ? TreeholeColors.accentPrimary.opacity(0.08)
                    : TreeholeColors.bgSurface
            )
            .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: TreeholeRadius.md)
                    .stroke(
                        isPopular
                            ? TreeholeColors.accentPrimary.opacity(0.3)
                            : TreeholeColors.borderSubtle,
                        lineWidth: 1
                    )
            )
        }
        .disabled(isBusy)
        .opacity(isBusy && !isThisPurchasing ? 0.6 : 1.0)
    }

    // MARK: - 购买

    private var isBusy: Bool {
        if case .purchasing = iap.purchaseState { return true }
        if case .verifying = iap.purchaseState { return true }
        return false
    }

    private func purchase(_ product: Product) {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        purchasingPackageId = product.id

        Task {
            await store.purchaseIAP(
                packageId: IAPProduct.match(productID: product.id)?.packageId ?? "small",
                product: product
            )
            purchasingPackageId = nil
        }
    }

    /// 按价格排序产品，未加载时用静态数据兜底
    private func sortedProducts() -> [Product] {
        if !iap.loadedProducts.isEmpty {
            return iap.loadedProducts.sorted { $0.price < $1.price }
        }
        // Fallback: 显示静态占位（产品尚未加载完）
        return []
    }

    // MARK: - 辅助组件

    private func ruleRow(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 13))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(TreeholeColors.textSecondary)
        }
    }

    private func toastOverlay(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(TreeholeColors.bgPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(TreeholeColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: TreeholeRadius.pill))
                .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                .padding(.bottom, 120)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - 充值套餐模型（静态兜底 + 后端套餐映射）

struct RechargePackage: Identifiable {
    let id: String
    let name: String
    let credits: Int
    let price: Int
    let desc: String
    let popular: Bool

    static let samples: [RechargePackage] = [
        RechargePackage(id: "small",  name: "一袋灵叶", credits: 50,  price: 6,  desc: "50 灵叶 · ¥6",   popular: false),
        RechargePackage(id: "medium", name: "一捧灵叶", credits: 120, price: 12, desc: "120 灵叶 · ¥12", popular: true),
        RechargePackage(id: "large",  name: "一篮灵叶", credits: 300, price: 25, desc: "300 灵叶 · ¥25", popular: false),
    ]
}
