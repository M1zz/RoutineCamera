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
    /// 식단·운동 모두 그날 하나라도 완료된 기록이 있으면 인정한다.
    /// (운동을 대표 슬롯 breakfast로만 인정하던 탓에 저녁 운동이 통계에서 빠졌다)
    public static func isDayRecorded(_ date: Date, in records: [MealRecord], exerciseMode: Bool = false, calendar: Calendar = .current) -> Bool {
        self.records(on: date, in: records, calendar: calendar).contains { $0.isComplete }
    }

    /// 완료된 기록이 하나라도 있는 날들 (그날 0시)
    public static func recordedDays(in records: [MealRecord], calendar: Calendar = .current) -> Set<Date> {
        Set(records.lazy.filter(\.isComplete).map { calendar.startOfDay(for: $0.date) })
    }

    /// 현재 연속 기록 일수. 오늘이 아직 미기록이면 '진행 중'으로 보고 끊지 않는다.
    /// 기록을 한 번만 훑는다 (예전에는 거슬러 올라가는 날마다 전체 기록을 다시 훑었다).
    public static func currentStreak(records: [MealRecord], today: Date = Date(), exerciseMode: Bool = false, calendar: Calendar = .current) -> Int {
        let days = recordedDays(in: records, calendar: calendar)
        var current = calendar.startOfDay(for: today)
        if !days.contains(current), let yesterday = calendar.date(byAdding: .day, value: -1, to: current) {
            current = yesterday
        }
        var streak = 0
        while days.contains(current) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else { break }
            current = previous
        }
        return streak
    }

    /// 최고 연속 기록 일수
    public static func maxStreak(records: [MealRecord], exerciseMode: Bool = false, calendar: Calendar = .current) -> Int {
        var best = 0, run = 0
        var previous: Date?
        for day in recordedDays(in: records, calendar: calendar).sorted() {
            if let previous, let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    /// 지금까지 기록한 날 수 (절대 줄지 않는 누적)
    public static func totalRecordedDays(records: [MealRecord], calendar: Calendar = .current) -> Int {
        recordedDays(in: records, calendar: calendar).count
    }

    /// 순간 피드 정렬용 시각. 촬영 시각 없으면 끼니 대표 시각으로 합성 → 같은 날 시간 흐름대로.
    public static func feedSortValue(_ record: MealRecord, calendar: Calendar = .current) -> Date {
        if let c = record.capturedAt { return c }
        let base = calendar.startOfDay(for: record.date)
        return calendar.date(byAdding: .hour, value: record.mealType.typicalHour, to: base) ?? base
    }
}
