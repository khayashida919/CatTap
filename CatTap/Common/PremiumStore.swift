import Foundation
import StoreKit

/// プレミアム（買い切り）の購入状態を管理する
///
/// 購入したかどうかは端末に保存せず、起動時と購入状況が変わったときに
/// StoreKit の購入記録（`Transaction.currentEntitlements`）から判定する。
/// 状態の書き換えと変更の通知はメインスレッドで行う。
final class PremiumStore {

    static let shared = PremiumStore()

    /// App Store Connect に登録する課金アイテムの商品ID
    static let productID = "kayashida.CatTap.premium"

    /// 購入状態か商品情報が変わったときにメインスレッドで送る通知
    static let didChangeNotification = Notification.Name("PremiumStore.didChange")

    enum PurchaseResult {
        /// 購入が終わった
        case purchased
        /// 保護者の承認待ちなどで、まだ終わっていない
        case pending
        /// 利用者が取り消した
        case cancelled
    }

    enum StoreError: LocalizedError {
        case productUnavailable
        case failedVerification

        var errorDescription: String? {
            switch self {
            case .productUnavailable: return "商品の情報を App Store から読み込めませんでした。通信状況を確かめて、しばらくしてからもう一度お試しください。"
            case .failedVerification: return "購入の確認に失敗しました。"
            }
        }
    }

    /// プレミアムを持っているか
    private(set) var isPremium = false
    /// App Store から読み込んだ商品。読み込めていないときは nil
    private(set) var product: Product?
    /// 商品の読み込みを一度でも試し終えたか
    private(set) var didLoadProduct = false

    private var updatesTask: Task<Void, Never>?

    private init() {}

    /// 起動時に一度呼ぶ。購入状況の変化を見張り、今の状態を読み込む
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await PremiumStore.shared.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    /// 商品情報（表示用の価格など）を読み込む
    func loadProduct() async {
        let product = try? await Product.products(for: [Self.productID]).first
        await MainActor.run {
            if let product {
                self.product = product
            }
            self.didLoadProduct = true
            self.notifyChange()
        }
    }

    /// 購入記録からプレミアムを持っているかを判定し直す
    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        let isPremium = owned || Self.isDebugUnlocked
        await MainActor.run {
            guard self.isPremium != isPremium else { return }
            self.isPremium = isPremium
            self.notifyChange()
        }
    }

    /// プレミアムを購入する
    func purchase() async throws -> PurchaseResult {
        if product == nil {
            await loadProduct()
        }
        guard let product else {
            throw StoreError.productUnavailable
        }
        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw StoreError.failedVerification
            }
            await transaction.finish()
            await refreshEntitlement()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// 以前の購入を復元する。App Store へのサインインを求められることがある
    func restore() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// 開発用ビルドで、起動引数 `-PremiumDebugUnlock` を付けたときだけプレミアムを解放する。
    /// シミュレータで見た目と動きを確かめるためのもので、App Store に出すビルドでは常に false
    private static var isDebugUnlocked: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-PremiumDebugUnlock")
        #else
        return false
        #endif
    }
}
