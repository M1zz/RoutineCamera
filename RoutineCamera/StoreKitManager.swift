//
//  StoreKitManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/12/25.
//
//  팁($1 소비성) 결제 — 파사드
//  StoreKit 2 엔진(상품 로드·구매·검증·트랜잭션 리스너)은 이제 LeeoKit 의
//  LeeoConsumableStore 가 공용으로 담당한다. 팁은 코인을 지급하지 않으므로 grants: 0.
//  (이 매니저는 현재 앱 어디에서도 사용되지 않지만, 공개 API 는 그대로 유지한다.)
//

import Foundation
import StoreKit
import Combine
import LeeoKit

@MainActor
class StoreKitManager: NSObject, ObservableObject {
    static let shared = StoreKitManager()

    @Published private(set) var products: [Product] = []
    /// 소비성 결제는 권한이 남지 않는다 — API 유지를 위한 빈 집합.
    @Published private(set) var purchasedProductIDs: Set<String> = []

    // Product ID - App Store Connect에서 설정한 것과 동일해야 함 (변경 금지)
    private let tipProductID = "com.yourcompany.routinecamera.tip1dollar"

    private let store: LeeoConsumableStore
    private var cancellable: AnyCancellable?

    var isPurchasing: Bool { store.purchasingProductID != nil }

    private override init() {
        // 팁 자는 코인 원장과 별개다 — ledgerID 로 잔액 저장 키를 분리해 코인 잔액과 섞이지 않게 한다.
        store = LeeoConsumableStore(config: LeeoConsumableConfig(
            products: [.init(id: tipProductID, grants: 0)],
            ledgerID: "tip"
        ))
        super.init()

        cancellable = store.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.products = self.store.products
            self.objectWillChange.send()
        }

        Task { await loadProducts() }
    }

    // 상품 로드
    func loadProducts() async {
        await store.loadProducts()
        products = store.products
    }

    // 구매 처리
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        await store.purchase(product)
    }

    // 이전 구매 복원 (소비성은 복원 대상이 아니지만 API 유지를 위해 계정 동기화만 수행)
    func restorePurchases() async {
        try? await AppStore.sync()
    }
}
