//
//  MealReminderPlanner.swift
//  RoutineCameraCore
//
//  식사 전 촬영 알림을 언제 걸지 정한다.
//  매일 반복 알림 하나를 두고 "기록하면 지우는" 방식은 한 번 지우면 다음 날 알림까지 사라졌다.
//  그래서 앞으로 며칠 치를 날짜별로 따로 계산해 건다 — 오늘 기록한 끼니는 오늘 것만 빠진다.
//

import Foundation

/// 알림을 받을 끼니 하나와 그 식사 시각
public struct MealReminderSlot: Equatable, Sendable {
    public let mealKey: String
    public let hour: Int
    public let minute: Int

    public init(mealKey: String, hour: Int, minute: Int) {
        self.mealKey = mealKey
        self.hour = hour
        self.minute = minute
    }
}

/// 실제로 걸 알림 하나
public struct PlannedMealReminder: Equatable, Sendable {
    public let identifier: String
    public let mealKey: String
    /// 그 끼니가 속한 날 (자정)
    public let day: Date
    public let mealTime: Date
    public let fireDate: Date
}

public enum MealReminderPlanner {
    public static let identifierPrefix = "mealreminder-"
    public static let defaultDays = 7

    /// - Parameters:
    ///   - leadMinutes: 식사 시각 몇 분 전에 알릴지 (0 이면 정각)
    ///   - days: 오늘부터 며칠 치를 걸지. iOS 는 앱당 대기 알림을 64개까지만 두므로 넉넉히 작게.
    ///   - recordedToday: 오늘 이미 기록한 끼니 — 오늘 알림만 빠지고 내일부터는 그대로 건다
    /// - Returns: 울릴 시각 순. 이미 지난 시각은 빠진다 (늦게 울리지 않는다).
    public static func plan(slots: [MealReminderSlot],
                            leadMinutes: Int,
                            now: Date,
                            days: Int = defaultDays,
                            recordedToday: Set<String> = [],
                            calendar: Calendar = .current) -> [PlannedMealReminder] {
        let today = calendar.startOfDay(for: now)
        let lead = max(0, leadMinutes)
        var result: [PlannedMealReminder] = []

        for offset in 0..<max(0, days) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for slot in slots {
                if offset == 0 && recordedToday.contains(slot.mealKey) { continue }
                guard let mealTime = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day),
                      let fireDate = calendar.date(byAdding: .minute, value: -lead, to: mealTime),
                      fireDate > now else { continue }
                result.append(PlannedMealReminder(
                    identifier: identifier(mealKey: slot.mealKey, day: day, calendar: calendar),
                    mealKey: slot.mealKey,
                    day: day,
                    mealTime: mealTime,
                    fireDate: fireDate
                ))
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    /// 같은 날·같은 끼니는 늘 같은 식별자 — 다시 걸면 덮어쓰고, 오늘 것만 골라 지울 수 있다
    public static func identifier(mealKey: String, day: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        func pad(_ value: Int?) -> String {
            let number = value ?? 0
            return number < 10 ? "0\(number)" : "\(number)"
        }
        return "\(identifierPrefix)\(mealKey)-\(components.year ?? 0)-\(pad(components.month))-\(pad(components.day))"
    }
}
