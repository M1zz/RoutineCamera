//
//  TipAskBanner.swift
//  RoutineCamera
//
//  "계속 만들 수 있게 힘을 보태 주세요" 카드. 끼니를 기록하고 돌아온 홈 위쪽(기록 유도 배너 자리)에 한 장 선다.
//
//  누구에게: **이미 세끼 프로인 사람**에게만. 아직 아닌 사람에게는 페이월이 맞는 길이다.
//  언제: 기록이 쌓인 것이 숫자로 보이는 순간(`SekkiTipMoments`). 기록을 마치면 숫자가 늘고, 넘어선 순간이 생기면 선다.
//  얼마나 드물게: LeeoKit 의 규칙(`LeeoTipAskPolicy`). 물으면 60일 쉬고, 낸 사람은 180일, '다음에' 세 번이면 끝.
//
//  ⚠️ 모달이 아니다. 목록 위에 얹힐 뿐 기록을 막지 않는다.
//

import SwiftUI
import LeeoKit

// MARK: - 순간 (순수)

enum SekkiTipMoments {
    /// 기록한 날 수(한 번 올라가면 줄지 않는다). 큰 것부터.
    static let days = [365, 100, 30]
    /// 마친 기록 수. 큰 것부터.
    static let records = [1000, 300, 100]

    /// 넘어선 순간, **인상적인 것부터**. 날 수가 앞이다(꾸준히 쓴 것이 가장 분명하다).
    static func reached(recordedDays: Int, recordCount: Int) -> [LeeoTipMoment] {
        let byDays = days.filter { recordedDays >= $0 }.map { threshold in
            LeeoTipMoment(id: "days.\(threshold)",
                          message: String(localized: "지금까지 \(recordedDays)일을 기록했어요",
                                          comment: "Tip ask card: total days with records so far"))
        }
        let byRecords = records.filter { recordCount >= $0 }.map { threshold in
            LeeoTipMoment(id: "records.\(threshold)",
                          message: String(localized: "지금까지 기록 \(recordCount)개를 남겼어요",
                                          comment: "Tip ask card: total completed records so far"))
        }
        return byDays + byRecords
    }

    @MainActor
    static func reachedNow(_ store: MealRecordStore) -> [LeeoTipMoment] {
        reached(recordedDays: store.getTotalRecordedDays(), recordCount: store.getTotalRecordCount())
    }
}

// MARK: - 카드 자리

/// 프로이고 팁 상품이 있을 때만 `LeeoTipAskSlot` 을 세운다. 물을지·물은 기록은 슬롯이 정한다.
/// ⚠️ LeeoKit 3.25.0 의 슬롯은 카드가 없을 때 빈 `Group` 이라 `onAppear` 가 불리지 않아 아직 카드가 서지 않는다.
///    LeeoKit 이 고쳐지면 이 자리 그대로 살아난다.
struct TipAskBanner: View {
    @ObservedObject var mealStore: MealRecordStore
    @ObservedObject private var subscription = SubscriptionManager.shared

    var body: some View {
        if subscription.isPro, let tipJar = subscription.tipJar {
            LeeoTipAskSlot<RoutineCameraSpec>(tipJar: tipJar, reached: SekkiTipMoments.reachedNow(mealStore))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
        }
    }
}
