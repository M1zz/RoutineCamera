//
//  MealPace.swift
//  RoutineCameraCore
//
//  밥 먹는 데 걸린 시간과 권하는 식사 시간.
//  천천히 먹어야 적게 먹어도 배가 부르다 — 이 앱이 열량 대신 보는 습관 가운데 하나다.
//

import Foundation

public enum MealPace {

    /// 권하는 식사 시간(분). 배부르다는 신호가 닿는 데 20분쯤 걸린다고 흔히 안내한다
    public static let recommendedMinutes = 20

    /// 식사 시간으로 믿을 수 있는 길이.
    /// 2분보다 짧으면 다 먹고 나서 사진 두 장을 이어 남긴 것이고, 2시간보다 길면 마감을 잊었다가 뒤늦게 누른 것이다.
    public static let trustedSeconds: ClosedRange<TimeInterval> = 120...7200

    /// 이보다 길게 잰 식사는 다 먹고 한참 뒤에 마감을 누른 것일 수 있다 — 그대로 남길지 사용자에게 묻는다
    public static let confirmAboveMinutes = 60

    /// 방금 잰 식사 시간을 그대로 남기기 전에 물어야 하는지
    public static func needsConfirmation(minutes: Int) -> Bool { minutes > confirmAboveMinutes }

    /// 시작 · 끝 시각으로 잰 식사 시간(분, 반올림). 믿을 수 없는 길이면 nil
    public static func minutes(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end else { return nil }
        let seconds = end.timeIntervalSince(start)
        guard trustedSeconds.contains(seconds) else { return nil }
        return Int((seconds / 60).rounded())
    }

    /// 먹는 중인 식사가 시작하고 지난 시간(분). 2시간이 넘으면 마감을 잊은 것으로 보고 nil
    public static func elapsedMinutes(since start: Date?, now: Date) -> Int? {
        guard let start else { return nil }
        let seconds = now.timeIntervalSince(start)
        guard seconds >= 0, seconds <= trustedSeconds.upperBound else { return nil }
        return Int(seconds / 60)
    }

    public struct Summary: Equatable, Sendable {
        /// 식사 시간을 잰 끼니 수
        public let mealCount: Int
        /// 보통 걸리는 시간(분) — 가운데 값. 한 번 길게 먹은 회식에 끌려가지 않는다
        public let usualMinutes: Int
        /// 끼니별 보통 시간(분)
        public let usualByMeal: [MealType: Int]
        /// 권하는 시간 이상 천천히 먹은 끼니 수
        public let unhurriedCount: Int

        /// 권하는 시간까지 모자란 분 (채웠으면 0)
        public var minutesToSlowDown: Int { max(MealPace.recommendedMinutes - usualMinutes, 0) }
        public var isUnhurried: Bool { minutesToSlowDown == 0 }
    }

    /// 식사 시간을 잰 끼니가 하나도 없으면 nil
    public static func summary(of records: [MealRecord]) -> Summary? {
        let timed = records.compactMap { record in record.eatingMinutes.map { (record.mealType, $0) } }
        guard !timed.isEmpty else { return nil }
        let byMeal = Dictionary(grouping: timed, by: \.0).mapValues { median($0.map(\.1)) }
        return Summary(mealCount: timed.count,
                       usualMinutes: median(timed.map(\.1)),
                       usualByMeal: byMeal,
                       unhurriedCount: timed.filter { $0.1 >= recommendedMinutes }.count)
    }

    /// 가운데 값. 짝수 개면 가운데 둘의 평균(반올림)
    static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        return Int((Double(sorted[mid - 1] + sorted[mid]) / 2).rounded())
    }
}
