//
//  MealStats.swift
//  RoutineCameraCore
//
//  기록 통계·스트릭·정렬의 순수 로직. 저장소/설정과 분리되어 단위 테스트 가능.
//

import Foundation

public enum MealStats {

    /// 특정 날짜의 기록들
    public static func records(on date: Date, in records: [MealRecord], calendar: Calendar = .current) -> [MealRecord] {
        records.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// 하루가 "연속 기록에 포함되는 날"인지.
    /// 식단: 어떤 끼니든 하나라도 완료 / 운동: 대표 슬롯(breakfast) 완료.
    public static func isDayRecorded(_ date: Date, in records: [MealRecord], exerciseMode: Bool = false, calendar: Calendar = .current) -> Bool {
        let day = self.records(on: date, in: records, calendar: calendar)
        if exerciseMode {
            return day.contains { $0.mealType == .breakfast && $0.isComplete }
        }
        return day.contains { $0.isComplete }
    }

    /// 현재 연속 기록 일수. 오늘이 아직 미기록이면 '진행 중'으로 보고 끊지 않는다.
    public static func currentStreak(records: [MealRecord], today: Date = Date(), exerciseMode: Bool = false, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: today)
        let todayRecorded = isDayRecorded(start, in: records, exerciseMode: exerciseMode, calendar: calendar)

        var streak = 0
        var current = start
        while true {
            if isDayRecorded(current, in: records, exerciseMode: exerciseMode, calendar: calendar) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: current) else { break }
                current = prev
            } else {
                if calendar.isDate(current, inSameDayAs: start) && !todayRecorded {
                    guard let prev = calendar.date(byAdding: .day, value: -1, to: current) else { break }
                    current = prev
                    continue
                }
                break
            }
        }
        return streak
    }

    /// 최고 연속 기록 일수
    public static func maxStreak(records: [MealRecord], exerciseMode: Bool = false, calendar: Calendar = .current) -> Int {
        var maxS = 0, cur = 0
        let sorted = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !sorted.isEmpty else { return 0 }

        for (i, date) in sorted.enumerated() {
            if isDayRecorded(date, in: records, exerciseMode: exerciseMode, calendar: calendar) {
                if i > 0,
                   let prev = sorted[safe: i - 1],
                   let next = calendar.date(byAdding: .day, value: 1, to: prev),
                   calendar.isDate(next, inSameDayAs: date) {
                    cur += 1
                } else {
                    cur = 1
                }
                maxS = max(maxS, cur)
            } else {
                cur = 0
            }
        }
        return maxS
    }

    /// 지금까지 기록한 날 수 (절대 줄지 않는 누적)
    public static func totalRecordedDays(records: [MealRecord], calendar: Calendar = .current) -> Int {
        Set(records.filter { $0.isComplete }.map { calendar.startOfDay(for: $0.date) }).count
    }

    /// 순간 피드 정렬용 시각. 촬영 시각 없으면 끼니 대표 시각으로 합성 → 같은 날 시간 흐름대로.
    public static func feedSortValue(_ record: MealRecord, calendar: Calendar = .current) -> Date {
        if let c = record.capturedAt { return c }
        let base = calendar.startOfDay(for: record.date)
        return calendar.date(byAdding: .hour, value: record.mealType.typicalHour, to: base) ?? base
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
