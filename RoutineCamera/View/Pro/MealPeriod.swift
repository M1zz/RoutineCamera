//
//  MealPeriod.swift
//  RoutineCamera
//
//  내보내기(PDF · 사진 한꺼번에 저장)에서 고르는 기간.
//

import Foundation
import RoutineCameraCore

enum MealPeriod: String, CaseIterable, Identifiable {
    case thisWeek, lastWeek, thisMonth, lastMonth, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisWeek:  return String(localized: "이번 주")
        case .lastWeek:  return String(localized: "지난 주")
        case .thisMonth: return String(localized: "이번 달")
        case .lastMonth: return String(localized: "지난 달")
        case .all:       return String(localized: "전체", comment: "Export period: every record")
        }
    }

    /// 그 기간. 전체는 nil.
    func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .thisWeek:  return calendar.dateInterval(of: .weekOfYear, for: now)
        case .lastWeek:  return calendar.date(byAdding: .weekOfYear, value: -1, to: now).flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        case .thisMonth: return calendar.dateInterval(of: .month, for: now)
        case .lastMonth: return calendar.date(byAdding: .month, value: -1, to: now).flatMap { calendar.dateInterval(of: .month, for: $0) }
        case .all:       return nil
        }
    }
}

extension Array where Element == MealRecord {
    /// 남긴 기록만, 기간 안의 것만, 먹은 순서대로
    func completed(in interval: DateInterval?) -> [MealRecord] {
        filter { record in
            guard record.isComplete else { return false }
            guard let interval else { return true }
            return interval.start <= record.date && record.date < interval.end
        }
        .sorted { $0.sortDate < $1.sortDate }
    }
}

extension MealRecord {
    /// 사진 (식전 → 식후 순서)
    var photos: [Data] { [beforeImageData, afterImageData].compactMap { $0 } }
}
