//
//  CoinManager.swift
//  RoutineCamera
//
//  코인 기반 식단 분석 시스템
//  - 한 달에 99코인 제공 (구독 시)
//  - 1회 분석 = 1코인 차감
//

import Foundation
import Combine

class CoinManager: ObservableObject {
    static let shared = CoinManager()

    @Published private(set) var currentCoins: Int {
        didSet {
            UserDefaults.standard.set(currentCoins, forKey: "analysisCoins")
            print("💰 [CoinManager] 코인 변경: \(currentCoins)개")
        }
    }

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
        // 저장된 코인 불러오기
        self.currentCoins = UserDefaults.standard.object(forKey: "analysisCoins") as? Int ?? 0
        self.isSubscribed = UserDefaults.standard.bool(forKey: "isSubscribed")

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
        return currentCoins > 0
    }

    /// 분석 시 코인 차감
    func consumeCoin() -> Bool {
        guard currentCoins > 0 else {
            print("❌ [CoinManager] 코인 부족")
            return false
        }

        currentCoins -= 1
        print("✅ [CoinManager] 코인 차감 완료 (남은 코인: \(currentCoins)개)")
        return true
    }

    // MARK: - 코인 충전

    /// 수동 코인 충전 (구독 결제 완료 시)
    func rechargeCoins(amount: Int = 99) {
        currentCoins += amount
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
        currentCoins += amount
        print("🧪 [CoinManager] 테스트 코인 추가: +\(amount)개")
    }

    /// 테스트용 초기화
    func resetForTesting() {
        currentCoins = 0
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
