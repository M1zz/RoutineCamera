//
//  StoreKitManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/12/25.
//

import Foundation
import StoreKit
import Combine

// Task 타입 충돌 방지를 위한 typealias
fileprivate typealias AsyncTask = _Concurrency.Task

@MainActor
class StoreKitManager: NSObject, ObservableObject {
    static let shared = StoreKitManager()

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isPurchasing = false

    // Product ID - App Store Connect에서 설정한 것과 동일해야 함
    private let tipProductID = "com.yourcompany.routinecamera.tip1dollar"

    private var updateListenerTask: AsyncTask<Void, Error>?

    private override init() {
        super.init()

        // 거래 업데이트 리스너 시작
        updateListenerTask = listenForTransactions()

        // 상품 로드
        AsyncTask {
            await loadProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // 상품 로드
    func loadProducts() async {
        do {
            let products = try await Product.products(for: [tipProductID])
            self.products = products
            print("✅ [StoreKit] 상품 로드 성공: \(products.count)개")
        } catch {
            print("❌ [StoreKit] 상품 로드 실패: \(error.localizedDescription)")
        }
    }

    // 구매 처리
    func purchase(_ product: Product) async throws -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // 거래 검증
                let transaction = try checkVerified(verification)

                // 거래 완료 처리
                await transaction.finish()

                print("✅ [StoreKit] 구매 성공: \(product.displayName)")
                return true

            case .userCancelled:
                print("ℹ️ [StoreKit] 사용자가 구매 취소")
                return false

            case .pending:
                print("⏳ [StoreKit] 구매 대기 중")
                return false

            @unknown default:
                print("❌ [StoreKit] 알 수 없는 결과")
                return false
            }
        } catch {
            print("❌ [StoreKit] 구매 실패: \(error.localizedDescription)")
            throw error
        }
    }

    // 거래 검증 (nonisolated로 변경)
    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // 거래 업데이트 리스너
    private func listenForTransactions() -> AsyncTask<Void, Error> {
        return AsyncTask.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // 거래 완료
                    await transaction.finish()

                    await MainActor.run {
                        print("✅ [StoreKit] 거래 업데이트: \(transaction.productID)")
                    }
                } catch {
                    print("❌ [StoreKit] 거래 검증 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    // 이전 구매 복원 (필요한 경우)
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            print("✅ [StoreKit] 구매 복원 완료")
        } catch {
            print("❌ [StoreKit] 구매 복원 실패: \(error.localizedDescription)")
        }
    }
}
