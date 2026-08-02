import StoreKit
import Foundation

// MARK: - App Store IAP 管理器 · StoreKit 2

/// 产品 ID 与后端套餐 ID 的映射
struct IAPProduct: Identifiable, Equatable {
    let id: String            // Apple 产品 ID，如 com.timetreehole.credits.small
    let packageId: String     // 后端套餐 ID：small / medium / large
    let credits: Int
    let displayName: String

    static let all: [IAPProduct] = [
        IAPProduct(id: "com.timetreehole.credits.small",  packageId: "small",  credits: 50,  displayName: "一袋灵叶"),
        IAPProduct(id: "com.timetreehole.credits.medium", packageId: "medium", credits: 120, displayName: "一捧灵叶"),
        IAPProduct(id: "com.timetreehole.credits.large",  packageId: "large",  credits: 300, displayName: "一篮灵叶"),
    ]

    /// 根据 Apple productID 查找对应 IAPProduct
    static func match(productID: String) -> IAPProduct? {
        all.first { $0.id == productID }
    }

    /// 根据后端套餐 ID 查找
    static func match(packageId: String) -> IAPProduct? {
        all.first { $0.packageId == packageId }
    }
}

// MARK: - 购买状态

enum IAPPurchaseState {
    case idle
    case loading                            // 加载产品中
    case ready([Product])                   // 产品已加载，可购买
    case purchasing(String)                 // 正在购买，参数为 productID
    case verifying                          // 服务端正验证收据
    case success(credits: Int, total: Int)  // 购买成功
    case failed(String)                     // 购买失败，原因
    case restored(Int)                      // 已恢复 N 笔购买
}

// MARK: - IAP 管理器

@MainActor
final class IAPManager: ObservableObject {

    static let shared = IAPManager()

    @Published var purchaseState: IAPPurchaseState = .idle
    @Published var loadedProducts: [Product] = []

    private let api = APIClient.shared

    /// 更新监听任务（处理外部购买 / 未完成交易）
    private var updateListenerTask: Task<Void, Error>?

    private init() {
        // 启动交易监听器 — 监听 App Store 推送的更新（如家庭共享购买、退款等）
        updateListenerTask = listenForTransactions()
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - 加载产品

    /// 从 App Store Connect 加载产品信息
    func loadProducts() async {
        purchaseState = .loading

        let productIDs = IAPProduct.all.map { $0.id }

        do {
            let products = try await Product.products(for: productIDs)
            loadedProducts = products.sorted { $0.price < $1.price }

            if products.isEmpty {
                purchaseState = .failed("无法加载商品信息，请检查网络连接")
            } else {
                purchaseState = .ready(products)
                print("✅ [IAP] 加载了 \(products.count) 个产品")
            }
        } catch {
            purchaseState = .failed("加载商品失败: \(error.localizedDescription)")
            print("❌ [IAP] 加载产品失败: \(error)")
        }
    }

    // MARK: - 购买

    /// 发起购买
    func purchase(product: Product) async {
        guard case .ready = purchaseState else {
            purchaseState = .failed("商品尚未就绪")
            return
        }

        purchaseState = .purchasing(product.id)

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // 验证交易
                await handlePurchaseSuccess(verification: verification)

            case .userCancelled:
                purchaseState = .idle
                print("👤 [IAP] 用户取消购买")

            case .pending:
                purchaseState = .idle
                print("⏳ [IAP] 购买挂起（等待家长批准等）")

            @unknown default:
                purchaseState = .failed("未知的购买结果")
            }

        } catch {
            purchaseState = .failed("购买失败: \(error.localizedDescription)")
            print("❌ [IAP] 购买出错: \(error)")
        }
    }

    /// 处理购买成功的交易
    private func handlePurchaseSuccess(verification: VerificationResult<Transaction>) async {
        // StoreKit 自动验证 JWS 签名
        guard case .verified(let transaction) = verification else {
            purchaseState = .failed("交易验证失败 — JWS 签名无效")
            print("❌ [IAP] JWS 验证未通过")
            return
        }

        let productID = transaction.productID
        guard let iapProduct = IAPProduct.match(productID: productID) else {
            purchaseState = .failed("未知产品: \(productID)")
            await transaction.finish()
            return
        }

        print("💰 [IAP] 购买成功: \(productID) (transaction_id: \(transaction.id))")

        // 提取收据数据发给后端验证
        purchaseState = .verifying

        do {
            // 获取 App Store 收据
            guard let receiptData = await fetchReceiptData() else {
                purchaseState = .failed("无法获取收据数据")
                await transaction.finish()
                return
            }

            // 发送到后端验证并充值
            let result = try await api.verifyReceipt(
                receiptData: receiptData,
                packageId: iapProduct.packageId,
                transactionId: String(transaction.id),
                productId: productID
            )

            if result.success {
                purchaseState = .success(
                    credits: result.addedCredits ?? iapProduct.credits,
                    total: result.totalCredits ?? 0
                )
                print("✅ [IAP] 后端验证成功，获得 \(result.addedCredits ?? 0) 灵叶")

                // 完成交易（通知 App Store）
                await transaction.finish()
            } else {
                // 后端拒绝（可能是收据重复、无效等）
                purchaseState = .failed(result.message ?? "充值验证失败")
                await transaction.finish()
            }

        } catch let error as APIError {
            if case .httpError(let code, _) = error, code == 409 {
                // 409 → 交易已处理过（重复提交），仍视作成功
                purchaseState = .success(credits: 0, total: 0)
            } else {
                purchaseState = .failed("验证失败: \(error.localizedDescription)")
            }
            await transaction.finish()

        } catch {
            purchaseState = .failed("网络错误，验证失败")
            // ⚠️ 不 finish 交易 — 下次启动时重新验证
            print("⚠️ [IAP] 后端验证网络错误，交易保留待重试: \(transaction.id)")
        }
    }

    // MARK: - 恢复购买

    /// 恢复用户之前购买过的非消耗型产品（灵叶是消耗型，但可用于找回遗漏的交易）
    func restorePurchases() async {
        purchaseState = .loading

        var restoredCount = 0

        // 遍历所有未完成的交易
        for await verification in Transaction.unfinished {
            guard case .verified(let transaction) = verification else { continue }

            let productID = transaction.productID
            guard let iapProduct = IAPProduct.match(productID: productID) else {
                await transaction.finish()
                continue
            }

            print("🔄 [IAP] 恢复未完成交易: \(productID)")

            guard let receiptData = await fetchReceiptData() else {
                continue
            }

            do {
                let result = try await api.verifyReceipt(
                    receiptData: receiptData,
                    packageId: iapProduct.packageId,
                    transactionId: String(transaction.id),
                    productId: productID
                )

                if result.success {
                    restoredCount += 1
                }

                await transaction.finish()
            } catch {
                print("⚠️ [IAP] 恢复交易验证失败: \(error)")
            }
        }

        if restoredCount > 0 {
            purchaseState = .restored(restoredCount)
            print("✅ [IAP] 恢复了 \(restoredCount) 笔交易")
        } else {
            purchaseState = .failed("没有可恢复的购买记录")
        }
    }

    // MARK: - 交易监听器（常驻）

    /// 监听 App Store 推送的交易更新
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await verification in Transaction.updates {
                guard let self = self else { break }

                guard case .verified(let transaction) = verification else {
                    print("❌ [IAP] 外部交易 JWS 验证失败")
                    continue
                }

                await MainActor.run {
                    print("📨 [IAP] 收到 App Store 推送交易: \(transaction.productID)")
                }

                // 处理遗漏的交易
                if let iapProduct = IAPProduct.match(productID: transaction.productID) {
                    if let receiptData = await MainActor.run(body: { self.fetchReceiptDataSync() }) {
                        do {
                            let result = try await self.api.verifyReceipt(
                                receiptData: receiptData,
                                packageId: iapProduct.packageId,
                                transactionId: String(transaction.id),
                                productId: transaction.productID
                            )

                            if result.success {
                                print("✅ [IAP] 外部交易验证成功: +\(result.addedCredits ?? 0) 灵叶")

                                await MainActor.run {
                                    // 通知 AppStore 刷新
                                    NotificationCenter.default.post(
                                        name: .iapCreditsUpdated,
                                        object: nil,
                                        userInfo: [
                                            "credits": result.totalCredits ?? 0,
                                            "added": result.addedCredits ?? 0
                                        ]
                                    )
                                }
                            }

                            await transaction.finish()
                        } catch {
                            print("⚠️ [IAP] 外部交易验证失败: \(error)")
                        }
                    }
                } else {
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - 收据提取

    /// 异步获取 App Store 收据 (base64)
    private func fetchReceiptData() async -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else {
            // 尝试刷新收据
            do {
                _ = try await AppStore.sync()
                // 刷新后重试
                guard let url = Bundle.main.appStoreReceiptURL,
                      FileManager.default.fileExists(atPath: url.path) else {
                    return nil
                }
                return try? Data(contentsOf: url).base64EncodedString()
            } catch {
                print("❌ [IAP] 刷新收据失败: \(error)")
                return nil
            }
        }

        return try? Data(contentsOf: receiptURL).base64EncodedString()
    }

    /// 同步获取收据（仅在已知收据存在时使用）
    nonisolated private func fetchReceiptDataSync() -> String? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else {
            return nil
        }
        return try? Data(contentsOf: receiptURL).base64EncodedString()
    }

    // MARK: - 辅助

    /// 根据后端套餐 ID 查找对应的 StoreKit Product
    func product(for packageId: String) -> Product? {
        guard let iapProduct = IAPProduct.match(packageId: packageId) else { return nil }
        return loadedProducts.first { $0.id == iapProduct.id }
    }

    /// 重置状态
    func reset() {
        purchaseState = .idle
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let iapCreditsUpdated = Notification.Name("com.timetreehole.iap.creditsUpdated")
}
