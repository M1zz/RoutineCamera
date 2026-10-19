//
//  SubscriptionManager.swift
//  RoutineCamera
//
//  세끼 프로 — 월간 구독 하나로 여는 기능 묶음.
//  StoreKit 2 엔진(상품 로드·구매·복원·권한 추적·트랜잭션 리스너·오프라인 캐시)은 LeeoKit 의 LeeoStore 가 맡고,
//  여기서는 앱 시작 때 스토어를 띄워 두고 "이 기능을 지금 쓸 수 있나" 만 답한다.
//  무엇이 무료이고 무엇이 프로인지는 RoutineCameraSpec 의 gate 한 곳에 있다.
//

import SwiftUI
import Combine
import LeeoKit

/// 프로로 여는 기능. rawValue 는 RoutineCameraSpec 의 gate 키와 같다.
enum ProFeature: String, LeeoProFeature, CaseIterable {
    case groupCreate   // 그룹 여러 개 만들기 (무료 1개)
    case insights      // 자세한 통계 — 전후 비교, 자주 먹은 음식
    case appLock       // Face ID 잠금

    var leeoTitle: String {
        switch self {
        case .groupCreate: return String(localized: "그룹을 여러 개 만들어요")
        case .insights:    return String(localized: "자세한 통계를 봐요")
        case .appLock:     return String(localized: "Face ID로 잠가요")
        }
    }

    var leeoDetail: String {
        switch self {
        case .groupCreate: return String(localized: "가족, 회사, 운동 모임처럼 함께 먹는 사람마다 그룹을 따로 둘 수 있어요.")
        case .insights:    return String(localized: "몇 주 전과 지금의 식사를 나란히 보고, 자주 먹은 음식을 모아 봐요.")
        case .appLock:     return String(localized: "앱을 열 때 Face ID나 Touch ID로 내 식단 기록을 지켜요.")
        }
    }

    var leeoIcon: String {
        switch self {
        case .groupCreate: return "person.3.fill"
        case .insights:    return "chart.bar.xaxis"
        case .appLock:     return "faceid"
        }
    }

    /// 페이월 혜택 목록 — 모든 프로 기능
    static var paywallBullets: [String] { allCases.map(\.leeoTitle) }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // 세끼 프로 상품 ID — App Store Connect 에 등록한 뒤로는 절대 바꾸지 않는다 (한 번 쓴 ID 는 다시 못 쓴다).
    // 연간·월간은 같은 구독 그룹(Sekki Pro), 평생은 비소모성. 무엇을 사든 같은 프로 권한이다.
    static let yearlySubscriptionID = "com.ysoup.routinecamera.pro.yearly"
    static let monthlySubscriptionID = "com.ysoup.routinecamera.pro.monthly"
    static let lifetimeID = "com.ysoup.routinecamera.pro.lifetime"

    /// 결제 화면에 보이는 순서 = 이 순서. 첫 상품이 기본 선택이다 —
    /// 연간을 맨 위·기본으로 두고 평생은 맨 아래에 둬서 구독 쪽으로 이끈다.
    static let productIDs = [yearlySubscriptionID, monthlySubscriptionID, lifetimeID]

    let store: LeeoStore
    private var cancellable: AnyCancellable?

    private init() {
        store = LeeoStore(config: RoutineCameraSpec.paywall!)
        cancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var isPro: Bool { store.hasPro }

    /// 개수 제한이 있는 기능 — current 는 지금까지 쓴 개수
    func evaluate(_ feature: ProFeature, current: Int = 0) -> LeeoGateDecision {
        store.gate.evaluate(feature.rawValue, current: current)
    }

    func allows(_ feature: ProFeature) -> Bool {
        store.gate.allows(feature.rawValue)
    }

    /// 하나 더 써도 되는지 (개수 제한 기능) — current 는 지금까지 쓴 개수
    func allows(_ feature: ProFeature, current: Int) -> Bool {
        evaluate(feature, current: current).isAllowed
    }

    /// 앱이 다시 앞으로 올 때 — 다른 기기 구매·환불·만료를 반영한다
    func refresh() async {
        await store.refreshEntitlements()
    }
}

extension View {
    /// 세끼 프로 페이월. lead 가 있으면 "방금 막힌 그 기능" 을 앞세운다.
    func proPaywall(isPresented: Binding<Bool>, lead: ProFeature? = nil) -> some View {
        leeoPaywallSheet(RoutineCameraSpec.self,
                         isPresented: isPresented,
                         title: lead == nil ? String(localized: "세끼 프로") : nil,
                         subtitle: lead == nil ? String(localized: "함께 먹는 사람이 많아질수록 더 편해져요.") : nil,
                         features: ProFeature.paywallBullets,
                         leadFeature: lead)
    }
}
