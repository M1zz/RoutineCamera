//
//  SubscriptionManager.swift
//  RoutineCamera
//
//  세끼 플러스 · 프로 — 두 등급, 등급마다 월간 · 연간 구독과 평생 이용권.
//  플러스는 나 혼자 쓰는 기능, 프로는 플러스 전부에 기록을 지도 · 리포트 · 파일로 꺼내는 기능을 더한다.
//  StoreKit 2 엔진(상품 로드·구매·복원·권한 추적·트랜잭션 리스너·오프라인 캐시)은 LeeoKit 의 LeeoStore 가 맡고,
//  여기서는 앱 시작 때 스토어를 띄워 두고 "이 기능을 지금 쓸 수 있나" 만 답한다.
//  무엇이 무료이고 무엇이 프로인지는 RoutineCameraSpec 의 gate 한 곳에 있다.
//

import SwiftUI
import Combine
import LeeoKit

/// 유료로 여는 기능. rawValue 는 RoutineCameraSpec 의 gate 키와 같다.
/// 어느 등급이 여는지는 `plusFeatures` · `proFeatures` 한 곳에 있다.
enum ProFeature: String, LeeoProFeature, CaseIterable, Identifiable {
    var id: String { rawValue }

    // 플러스
    case groupCreate   // 그룹 여러 개 만들기 (무료 1개)
    case insights      // 자세한 통계 — 전후 비교, 자주 먹은 음식
    case appLock       // Face ID 잠금
    case habitHistory  // 지난 달 달력 · 스탬프별 이어 온 날과 횟수 (이번 달 달력과 기록은 무료)
    case customStamps  // 나만의 스탬프 만들기 (기본 스탬프는 무료)
    // 프로
    case mealMap       // 찍은 곳을 지도에 모아 보기
    case weeklyReport  // 지난 주를 한 장으로 + 월요일 알림
    case pdfExport     // 기간을 골라 PDF 로 내보내기
    case bulkSave      // 기간을 골라 사진앱에 한꺼번에 저장

    static let plusFeatures: [ProFeature] = [.groupCreate, .insights, .appLock, .habitHistory, .customStamps]
    static let proFeatures: [ProFeature] = [.mealMap, .weeklyReport, .pdfExport, .bulkSave]

    /// 이 기능을 여는 등급 이름 (배지 · 안내용)
    var tierName: String {
        Self.plusFeatures.contains(self)
            ? String(localized: "플러스", comment: "Paid tier name (lower)")
            : String(localized: "프로", comment: "Paid tier name (higher)")
    }

    var leeoTitle: String {
        switch self {
        case .groupCreate: return String(localized: "그룹을 여러 개 만들어요")
        case .insights:    return String(localized: "자세한 통계를 봐요")
        case .appLock:     return String(localized: "Face ID로 잠가요")
        case .habitHistory: return String(localized: "지난 달력과 스탬프 기록을 돌아봐요")
        case .customStamps: return String(localized: "나만의 스탬프를 만들어요")
        case .mealMap:      return String(localized: "어디서 먹었는지 지도로 봐요")
        case .weeklyReport: return String(localized: "지난 주를 한 장으로 받아 봐요")
        case .pdfExport:    return String(localized: "기록을 PDF로 내보내요")
        case .bulkSave:     return String(localized: "사진을 한꺼번에 저장해요")
        }
    }

    var leeoDetail: String {
        switch self {
        case .groupCreate: return String(localized: "가족, 회사, 운동 모임처럼 함께 먹는 사람마다 그룹을 따로 둘 수 있어요.")
        case .insights:    return String(localized: "몇 주 전과 지금의 식사를 나란히 보고, 자주 먹은 음식을 모아 봐요.")
        case .appLock:     return String(localized: "앱을 열 때 Face ID나 Touch ID로 내 식단 기록을 지켜요.")
        case .habitHistory: return String(localized: "지난 달 달력을 넘겨 보고, 스탬프마다 몇 번 찍었는지와 며칠째 이어 가는지 봐요.")
        case .customStamps: return String(localized: "기본 스탬프에 없는 음식이나 습관을 이모지와 이름으로 만들어 찍어요.")
        case .mealMap:      return String(localized: "찍은 곳을 남긴 기록을 지도 위에 모아 봐요.")
        case .weeklyReport: return String(localized: "월요일 아침마다 지난 주에 언제 무엇을 먹었는지 정리해 알려 드려요.")
        case .pdfExport:    return String(localized: "기간을 골라 사진, 시각, 메모를 PDF로 만들어 영양사나 트레이너에게 보내요.")
        case .bulkSave:     return String(localized: "기간을 골라 그동안 찍은 사진을 사진앱에 한 번에 저장해요.")
        }
    }

    var leeoIcon: String {
        switch self {
        case .groupCreate: return "person.3.fill"
        case .insights:    return "chart.bar.xaxis"
        case .appLock:     return "faceid"
        case .habitHistory: return "calendar"
        case .customStamps: return "seal.fill"
        case .mealMap:      return "map.fill"
        case .weeklyReport: return "calendar.badge.clock"
        case .pdfExport:    return "doc.richtext"
        case .bulkSave:     return "square.and.arrow.down.on.square"
        }
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // 상품 ID — App Store Connect 에 등록한 뒤로는 절대 바꾸지 않는다 (한 번 쓴 ID 는 다시 못 쓴다).
    // 구독 넷은 한 구독 그룹(Sekki Pro)에 넣고 프로를 플러스보다 위 레벨로 둔다 — 올리고 내릴 때 App Store 가 정산한다.
    // 평생은 비소모성. 1.2.3 까지 판 프로 상품(pro.*)은 그대로 프로다 — 이미 산 사람은 계속 모든 기능을 쓴다.
    static let plusYearlyID = "com.ysoup.routinecamera.plus.yearly"
    static let plusMonthlyID = "com.ysoup.routinecamera.plus.monthly"
    static let plusLifetimeID = "com.ysoup.routinecamera.plus.lifetime"
    static let yearlySubscriptionID = "com.ysoup.routinecamera.pro.yearly"
    static let monthlySubscriptionID = "com.ysoup.routinecamera.pro.monthly"
    static let lifetimeID = "com.ysoup.routinecamera.pro.lifetime"

    /// 등급별 상품. 결제 화면에 보이는 순서 = 이 순서, 첫 상품이 기본 선택 —
    /// 연간을 맨 위 · 기본으로 두고 평생은 맨 아래에 둬서 구독 쪽으로 이끈다.
    static let plusProductIDs = [plusYearlyID, plusMonthlyID, plusLifetimeID]
    static let proProductIDs = [yearlySubscriptionID, monthlySubscriptionID, lifetimeID]
    static let productIDs = plusProductIDs + proProductIDs

    /// 프로 선물 — 소모성 상품. 받는 사람은 평생(`lifetimeID`)을 산 것과 같아진다(`RoutineCameraSpec.monetization`).
    /// ⚠️ `productIDs` 에 넣지 않는다. 넣으면 선물을 산 사람 자신이 프로가 된다.
    static let giftProductID = "com.ysoup.routinecamera.gift.pro"

    /// 팁(개발자 응원하기) — 소모성 상품 셋, 작은 것부터. 기능을 열지 않는다.
    /// ⚠️ `productIDs` 에 넣지 않는다. 넣으면 팁을 낸 사람이 프로가 된다.
    static let tipProductIDs = [
        "com.ysoup.routinecamera.tip.small",
        "com.ysoup.routinecamera.tip.medium",
        "com.ysoup.routinecamera.tip.large",
    ]

    let store: LeeoStore
    private var cancellable: AnyCancellable?

    private init() {
        #if DEBUG
        // 시뮬레이터 검증 · 스크린샷용: UNLOCK_PRO_FOR_TEST=1 이면 프로(모든 기능)로 연다
        if ProcessInfo.processInfo.environment["UNLOCK_PRO_FOR_TEST"] == "1" {
            store = LeeoStore(config: RoutineCameraSpec.paywall!, unlockOverride: { true })
        } else {
            store = LeeoStore(config: RoutineCameraSpec.paywall!)
        }
        #else
        store = LeeoStore(config: RoutineCameraSpec.paywall!)
        #endif
        cancellable = store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// 플러스든 프로든 유료 등급이 하나라도 있는지
    var isPro: Bool { store.hasPro }

    /// 가진 등급 (없으면 nil)
    var tier: LeeoTier? { store.currentTier }

    /// 가장 높은 등급(프로)인지
    var isTopTier: Bool { store.gate.isUnlocked }

    /// 프로 선물 엔진. 받은 선물은 LeeoStore 가 권한에 합치므로 `isPro` 가 그대로 따라온다.
    var gift: LeeoGiftStore? { store.gift }

    /// 팁 엔진. 상품 로드·결제 갱신은 LeeoStore 가 맡는다.
    var tipJar: LeeoTipJar? { store.tipJar }

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

    /// 다른 기기 · 다시 설치한 뒤 산 것을 되찾는다. 되찾은 등급이 있으면 true
    func restore() async -> Bool {
        await store.restore()
        return store.hasPro
    }

    /// 앱이 다시 앞으로 올 때 — 다른 기기 구매·환불·만료를 반영한다
    func refresh() async {
        await store.refreshEntitlements()
    }
}

extension View {
    /// 세끼 플러스 · 프로 페이월. lead 가 있으면 "방금 막힌 그 기능" 과 그 기능을 여는 등급을 앞세운다.
    func proPaywall(isPresented: Binding<Bool>, lead: ProFeature? = nil) -> some View {
        // 머리말 없이 기능 그림을 넘겨 본다(LeeoKit `LeeoShowcasePaywall`). 고른 등급의 장만, 막힌 기능이 맨 앞.
        leeoPaywallSheet(RoutineCameraSpec.self,
                         isPresented: isPresented,
                         leadFeature: lead,
                         showcases: ProFeature.showcases(leading: lead))
    }
}
