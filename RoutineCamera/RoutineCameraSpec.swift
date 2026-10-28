import Foundation
import LeeoKit

enum RoutineCameraSpec: LeeoAppSpec {
    static let appName = "세끼"
    static let developerEmail = "mizzking75@gmail.com"
    /// App Store 앱 ID — 친구 초대 링크·리뷰 요청이 쓴다
    static let appStoreID: String? = "6755164924"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.ysoup.RoutineCamera")

    /// 법적·지원 링크 — docs/ 의 GitHub Pages.
    /// 친구 기능용 계정을 만든다(친구 화면 > 계정 설정 > 회원 탈퇴). 삭제 안내는 지원 페이지 FAQ 에 있다.
    static let legal = LeeoLegalConfig(
        privacyURL: URL(string: "https://m1zz.github.io/RoutineCamera/privacy.html")!,
        supportURL: URL(string: "https://m1zz.github.io/RoutineCamera/")!,
        termsURL: URL(string: "https://m1zz.github.io/RoutineCamera/terms.html")!,
        dataDeletionURL: URL(string: "https://m1zz.github.io/RoutineCamera/")!,
        createsAccounts: true
    )

    /// 수익모델 — 기록·위젯·친구 공유·그룹 참여는 무료, 세끼 프로(연간·월간 구독 또는 평생)로 기능 묶음을 연다.
    /// 상품 ID 는 절대 변경하지 않는다. 기능 키는 SubscriptionManager.swift 의 ProFeature 와 같다.
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: SubscriptionManager.productIDs,   // 연간(기본 선택) · 월간 · 평생
            termsURL: URL(string: "https://m1zz.github.io/RoutineCamera/terms.html")!,
            gate: LeeoGatePolicy(
                freeLimits: [ProFeature.groupCreate.rawValue: 1],   // 그룹은 하나까지 무료로 만든다 (참여는 제한 없음)
                proOnly: [ProFeature.insights.rawValue, ProFeature.appLock.rawValue]
            ),
            // 프로 선물하기. 보내는 사람은 소모성 선물 상품을 사고, 받는 사람은 평생 프로를 산 것과 같아진다.
            // 선물 기록은 피드백과 같은 허브 컨테이너의 공개 DB 에 둔다. entitlements 에 이미 있다.
            // ⚠️ 선물 상품은 productIDs · entitlementIDs 에 넣지 않는다. 넣으면 선물을 산 사람이 프로가 된다.
            gift: LeeoGiftConfig(
                productID: SubscriptionManager.giftProductID,
                grantsProductID: SubscriptionManager.lifetimeID,
                containerIdentifier: "iCloud.com.Ysoup.FeedbackHub"
            )
        )
    )

    /// 익명 사용 통계·구독 퍼널 → FeedbackHub. 없으면 bootstrap 이 스냅샷·app_open 을 건너뛴다.
    static let analytics: any LeeoAnalytics = LeeoUsageAnalytics(spec: RoutineCameraSpec.self)
}
