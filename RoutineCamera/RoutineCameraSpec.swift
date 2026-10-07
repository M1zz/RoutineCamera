import Foundation
import LeeoKit

enum RoutineCameraSpec: LeeoAppSpec {
    static let appName = "세끼"
    static let developerEmail = "mizzking75@gmail.com"
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

    /// 수익모델 — 무료로 쓰다가 월간 구독(매달 99코인 충전)으로 프로 권한.
    /// 상품 ID 는 절대 변경하지 않는다. (팁·코인은 LeeoConsumableStore 가 따로 다룬다.)
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: [SubscriptionManager.monthlySubscriptionID],
            termsURL: URL(string: "https://m1zz.github.io/RoutineCamera/terms.html")!
        )
    )
}
