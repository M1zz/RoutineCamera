import Foundation
import LeeoKit

enum RoutineCameraSpec: LeeoAppSpec {
    static let appName = "세끼"
    static let developerEmail = "mizzking75@gmail.com"
    static let feedback = LeeoFeedbackConfig(containerIdentifier: "iCloud.com.Ysoup.FeedbackHub", appIdentifier: "com.ysoup.RoutineCamera")

    // 월간 구독(매달 99코인 충전)을 프로 권한으로 판정한다. 상품 ID 는 절대 변경하지 않는다.
    static let paywall = LeeoPaywallConfig(
        productIDs: [SubscriptionManager.monthlySubscriptionID]
    )
}
