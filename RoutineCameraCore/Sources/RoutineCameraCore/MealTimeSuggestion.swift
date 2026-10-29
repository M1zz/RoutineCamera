//
//  MealTimeSuggestion.swift
//  RoutineCameraCore
//
//  기록 화면이 미리 채워 두는 "언제 먹었는지". 사용자가 바꿀 수 있고, 안 바꾸면 이 값으로 저장된다.
//  (점심을 깜빡하고 저녁에 남겨도 피드·위젯에서 오늘 저녁이 아니라 점심 자리에 놓이도록)
//

import Foundation

public enum MealTimeSuggestion {

    /// 기록 시각 제안.
    /// - 오늘, 지금 시간대의 끼니 → 지금
    /// - 그 외 → 그 날짜의 끼니 대표 시각 (아침 8시·점심 12시 …). 단 아직 오지 않은 시각이면 지금.
    public static func capturedAt(day: Date, mealType: MealType, now: Date, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now), MealType.inferred(at: now, calendar: calendar) == mealType {
            return now
        }
        let start = calendar.startOfDay(for: day)
        let typical = calendar.date(bySettingHour: mealType.typicalHour, minute: 0, second: 0, of: start) ?? start
        return min(typical, now)
    }

    /// 사용자가 고른 날짜(day)에 고른 시각(time 의 시·분)을 붙인다. 미래가 되면 지금으로 자른다.
    public static func combine(day: Date, time: Date, now: Date, calendar: Calendar = .current) -> Date {
        let hm = calendar.dateComponents([.hour, .minute], from: time)
        let combined = calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0,
                                     of: calendar.startOfDay(for: day)) ?? day
        return min(combined, now)
    }
}
