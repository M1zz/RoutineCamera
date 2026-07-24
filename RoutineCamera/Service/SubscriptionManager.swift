//
//  SubscriptionManager.swift
//  RoutineCamera
//
//  StoreKit 기반 구독 관리 — 파사드
//  - 월 $2 구독으로 매달 99코인 충전
//
//  StoreKit 2 엔진(상품 로드·구매·복원·권한 추적·트랜잭션 리스너·검증·오프라인 캐시)은
//  이제 LeeoKit 의 LeeoStore 가 공용으로 담당한다. 이 파일은 그 위에 앱 고유의
//  "구독 활성 ↔ CoinManager 월 충전" 연결만 얹은 얇은 파사드로, 기존 호출부는
//  그대로 동작한다. (구독 상품 ID·코인 지급 정책은 변경 없음.)
//

import Foundation
import StoreKit
import Combine
import LeeoKit

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // 구독 상품 ID (App Store Connect에서 설정한 ID) — 절대 변경 금지
    static let monthlySubscriptionID = "com.ysoup.routinecamera.monthly.99coins"

    enum SubscriptionStatus {
        case notSubscribed
        case subscribed
        case expired
        case loading
    }

    /// 공용 StoreKit 엔진. 구독 권한(entitlement) 판정을 담당한다.
    private let store: LeeoStore
    private var cancellable: AnyCancellable?
    /// CoinManager 로 이미 반영한 구독 상태(전이 감지용).
    private var lastSyncedSubscribed: Bool?

    private init() {
        store = LeeoStore(config: RoutineCameraSpec.paywall!)
        // 공용 스토어의 상태 변화를 뷰에 전파하고, 구독 활성 여부를 코인 시스템에 반영한다.
        cancellable = store.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            self.syncCoinSubscription()
        }
        syncCoinSubscription()
    }

    // MARK: - 공개 상태 (기존 API 유지)

    var products: [Product] { store.products }

    var purchasedSubscriptions: [Product] {
        store.products.filter { store.purchasedProductIDs.contains($0.id) }
    }

    var subscriptionStatus: SubscriptionStatus {
        store.hasPro ? .subscribed : .notSubscribed
    }

    var isSubscribed: Bool { store.hasPro }

    var monthlyProduct: Product? {
        store.products.first(where: { $0.id == Self.monthlySubscriptionID })
    }

    // MARK: - 상품 로드 / 구매 / 복원 (LeeoStore 로 위임)

    func loadProducts() async {
        await store.loadProducts()
    }

    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        await store.purchase(product)
    }

    func restorePurchases() async {
        await store.restore()
    }

    /// 현재 유효한 구독 권한을 다시 확인하고 코인 시스템에 반영한다.
    func updateSubscriptionStatus() async {
        await store.refreshEntitlements()
        syncCoinSubscription()
    }

    // MARK: - 구독 ↔ 코인 시스템 연결

    /// 구독이 활성/비활성으로 "전이"될 때만 CoinManager 에 알린다.
    /// activateSubscription() 은 월 단위로 멱등(같은 달 재충전 안 함)하므로 안전하다.
    private func syncCoinSubscription() {
        let subscribed = store.hasPro
        guard subscribed != lastSyncedSubscribed else { return }
        lastSyncedSubscribed = subscribed
        if subscribed {
            CoinManager.shared.activateSubscription()
        } else {
            CoinManager.shared.deactivateSubscription()
        }
    }
}
