//
//  CoinManager.swift
//  RoutineCamera
//
//  코인 기반 식단 분석 시스템 — 파사드
//  - 한 달에 99코인 제공 (구독 시)
//  - 1회 분석 = 1코인 차감
//
//  코인 "잔액"의 저장/차감/충전 및 중단된 소비성 트랜잭션 복구는 이제 LeeoKit 의
//  LeeoConsumableStore 가 공용으로 담당한다. 이 파일은 그 위에 앱 고유의 월 단위
//  자동 충전 정책만 얹은 얇은 파사드로, 기존 호출부(currentCoins/consumeCoin 등)는
//  그대로 동작한다.
//
//  ⚠️ 잔액 보존: 예전엔 코인을 UserDefaults.standard 의 "analysisCoins" 키에 직접 저장했다.
//  LeeoConsumableStore 는 자체 키("leeo.consumable.balance")를 쓰므로, 최초 1회
//  기존 잔액을 새 스토어로 옮긴다(아래 마이그레이션). 기존 사용자의 코인은 유실되지 않는다.
//

import Foundation
import Combine
import LeeoKit

class CoinManager: ObservableObject {
    static let shared = CoinManager()

    /// 기존 코인 잔액 저장 키(마이그레이션 원본).
    private static let legacyBalanceKey = "analysisCoins"
    /// 마이그레이션 완료 플래그.
    private static let migrationFlagKey = "coinBalance.migratedToLeeoKit.v1"

    /// 공용 소비성 결제/잔액 엔진.
    /// 이 앱은 코인을 소비성 IAP 로 팔지 않고 구독으로 충전하므로 판매 상품은 없다.
    /// (잔액 저장·차감·충전·중단 트랜잭션 복구를 위해 사용한다.)
    private let store: LeeoConsumableStore
    private var cancellable: AnyCancellable?

    /// 현재 코인 잔액 (LeeoConsumableStore 가 소유·영속화).
    var currentCoins: Int { store.balance }

    @Published private(set) var isSubscribed: Bool {
        didSet {
            UserDefaults.standard.set(isSubscribed, forKey: "isSubscribed")
            print("💳 [CoinManager] 구독 상태 변경: \(isSubscribed)")
        }
    }

    private var lastRechargeDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "lastCoinRechargeDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastCoinRechargeDate")
        }
    }

    private init() {
        store = LeeoConsumableStore(config: LeeoConsumableConfig(products: []))
        self.isSubscribed = UserDefaults.standard.bool(forKey: "isSubscribed")

        // 기존 잔액을 공용 스토어로 1회 이전 (기존 사용자 코인 보존).
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.migrationFlagKey) {
            let legacy = defaults.object(forKey: Self.legacyBalanceKey) as? Int ?? 0
            if legacy > 0 { store.credit(legacy) }
            defaults.set(true, forKey: Self.migrationFlagKey)
            print("🔀 [CoinManager] 코인 잔액 마이그레이션 완료: \(legacy)개 이전")
        }

        // 잔액 변화(구매 복구 등)를 뷰에 전파.
        cancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        print("💰 [CoinManager] 초기화 완료")
        print("   - 현재 코인: \(currentCoins)개")
        print("   - 구독 상태: \(isSubscribed)")
        print("   - 마지막 충전일: \(lastRechargeDate?.description ?? "없음")")

        // 앱 실행 시 자동 충전 체크
        checkAndAutoRecharge()
    }

    // MARK: - 코인 사용

    /// 분석에 필요한 코인이 있는지 확인
    func hasEnoughCoins() -> Bool {
        return store.canAfford(1)
    }

    /// 분석 시 코인 차감
    func consumeCoin() -> Bool {
        guard store.spend(1) else {
            print("❌ [CoinManager] 코인 부족")
            return false
        }
        print("✅ [CoinManager] 코인 차감 완료 (남은 코인: \(currentCoins)개)")
        return true
    }

    // MARK: - 코인 충전

    /// 수동 코인 충전 (구독 결제 완료 시)
    func rechargeCoins(amount: Int = 99) {
        store.credit(amount)
        lastRechargeDate = Date()
        print("✅ [CoinManager] 코인 충전 완료: +\(amount)개 (총: \(currentCoins)개)")
    }

    /// 매달 자동 충전 체크 (구독자만)
    func checkAndAutoRecharge() {
        guard isSubscribed else {
            print("ℹ️ [CoinManager] 구독자 아님 - 자동 충전 건너뜀")
            return
        }

        let calendar = Calendar.current
        let now = Date()

        // 마지막 충전일이 없으면 첫 구독
        guard let lastRecharge = lastRechargeDate else {
            print("🎉 [CoinManager] 첫 구독 - 99코인 지급")
            rechargeCoins(amount: 99)
            return
        }

        // 다른 달인지 확인
        let lastMonth = calendar.component(.month, from: lastRecharge)
        let lastYear = calendar.component(.year, from: lastRecharge)
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        if currentYear > lastYear || (currentYear == lastYear && currentMonth > lastMonth) {
            print("📅 [CoinManager] 새로운 달 - 99코인 자동 충전")
            rechargeCoins(amount: 99)
        } else {
            print("ℹ️ [CoinManager] 이번 달 이미 충전됨")
        }
    }

    // MARK: - 구독 관리

    /// 구독 활성화 (StoreKit 결제 완료 후 호출)
    func activateSubscription() {
        isSubscribed = true
        checkAndAutoRecharge() // 즉시 코인 충전
        print("✅ [CoinManager] 구독 활성화 완료")
    }

    /// 구독 취소
    func deactivateSubscription() {
        isSubscribed = false
        print("⚠️ [CoinManager] 구독 취소됨 (코인은 유지)")
    }

    // MARK: - 디버그/개발용

    #if DEBUG
    /// 테스트용 코인 추가
    func addTestCoins(_ amount: Int) {
        store.credit(amount)
        print("🧪 [CoinManager] 테스트 코인 추가: +\(amount)개")
    }

    /// 테스트용 초기화
    func resetForTesting() {
        store.spend(store.balance) // 잔액을 0으로
        isSubscribed = false
        lastRechargeDate = nil
        print("🔄 [CoinManager] 테스트용 초기화 완료")
    }
    #endif

    // MARK: - 정보 조회

    /// 다음 충전까지 남은 일수
    func daysUntilNextRecharge() -> Int? {
        guard isSubscribed, let lastRecharge = lastRechargeDate else {
            return nil
        }

        let calendar = Calendar.current
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: lastRecharge),
              let startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) else {
            return nil
        }

        let components = calendar.dateComponents([.day], from: Date(), to: startOfNextMonth)
        return components.day
    }
}
