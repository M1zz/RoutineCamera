//
//  SubscriptionManager.swift
//  RoutineCamera
//
//  StoreKit 기반 구독 관리
//  - 월 $2 구독으로 매달 99코인 충전
//

import Foundation
import StoreKit
import Combine

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // 구독 상품 ID (App Store Connect에서 설정한 ID)
    static let monthlySubscriptionID = "com.ysoup.routinecamera.monthly.99coins"

    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedSubscriptions: [Product] = []
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .notSubscribed

    enum SubscriptionStatus {
        case notSubscribed
        case subscribed
        case expired
        case loading
    }

    private var updateListenerTask: Task<Void, Error>?

    private init() {
        // 구독 상태 변경 리스너 시작
        updateListenerTask = listenForTransactions()

        // 상품 로드
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - 상품 로드

    func loadProducts() async {
        do {
            print("🛒 [SubscriptionManager] 상품 로드 중...")
            let storeProducts = try await Product.products(for: [Self.monthlySubscriptionID])
            products = storeProducts
            print("✅ [SubscriptionManager] 상품 로드 완료: \(storeProducts.count)개")

            for product in storeProducts {
                print("   - \(product.displayName): \(product.displayPrice)")
            }
        } catch {
            print("❌ [SubscriptionManager] 상품 로드 실패: \(error)")
        }
    }

    // MARK: - 구독 구매

    func purchase(_ product: Product) async throws -> Bool {
        print("💳 [SubscriptionManager] 구매 시도: \(product.displayName)")

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // 구매 성공 - 트랜잭션 검증
            let transaction = try checkVerified(verification)
            await transaction.finish()

            // 구독 활성화
            await updateSubscriptionStatus()

            print("✅ [SubscriptionManager] 구매 성공")
            return true

        case .userCancelled:
            print("⚠️ [SubscriptionManager] 사용자가 구매 취소")
            return false

        case .pending:
            print("⏳ [SubscriptionManager] 구매 대기 중 (승인 필요)")
            return false

        @unknown default:
            print("❓ [SubscriptionManager] 알 수 없는 구매 결과")
            return false
        }
    }

    // MARK: - 구독 복원

    func restorePurchases() async {
        print("🔄 [SubscriptionManager] 구독 복원 시작...")

        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            print("✅ [SubscriptionManager] 구독 복원 완료")
        } catch {
            print("❌ [SubscriptionManager] 구독 복원 실패: \(error)")
        }
    }

    // MARK: - 구독 상태 업데이트

    func updateSubscriptionStatus() async {
        print("🔍 [SubscriptionManager] 구독 상태 확인 중...")

        var activeSubscriptions: [Product] = []

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // 구독 상품인지 확인
                if let product = products.first(where: { $0.id == transaction.productID }) {
                    activeSubscriptions.append(product)
                }
            } catch {
                print("❌ [SubscriptionManager] 트랜잭션 검증 실패: \(error)")
            }
        }

        purchasedSubscriptions = activeSubscriptions

        // 구독 상태 업데이트
        if !activeSubscriptions.isEmpty {
            subscriptionStatus = .subscribed
            CoinManager.shared.activateSubscription()
            print("✅ [SubscriptionManager] 활성 구독 확인됨")
        } else {
            subscriptionStatus = .notSubscribed
            CoinManager.shared.deactivateSubscription()
            print("ℹ️ [SubscriptionManager] 활성 구독 없음")
        }
    }

    // MARK: - 트랜잭션 검증

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }

    enum StoreError: Error {
        case failedVerification
    }

    // MARK: - 트랜잭션 리스너

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await transaction.finish()
                    await self.updateSubscriptionStatus()
                    print("🔔 [SubscriptionManager] 트랜잭션 업데이트 감지")
                } catch {
                    print("❌ [SubscriptionManager] 트랜잭션 처리 실패: \(error)")
                }
            }
        }
    }

    // MARK: - 구독 정보

    var isSubscribed: Bool {
        return subscriptionStatus == .subscribed
    }

    var monthlyProduct: Product? {
        return products.first(where: { $0.id == Self.monthlySubscriptionID })
    }
}
