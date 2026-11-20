//
//  MealShareFingerprint.swift
//  RoutineCameraCore
//
//  친구 공유(공개 DB)에 무엇을 다시 올릴지 정한다: 날짜별 지문을 저장해 두고, 지문이 달라진 날만 올린다.
//  지문은 실행이 바뀌어도 같은 값이어야 한다 — 실행마다 달라지면 앱을 켤 때마다 모든 날짜가 다시 올라간다
//  (실제로 났던 버그다. 테스트가 값을 고정한다).
//

import Foundation

public enum MealShareFingerprint {

    /// 날짜(yyyy-MM-dd)별 지문. 사진은 바이트 수만 보므로 계산이 가볍다.
    public static func byDay(_ records: [MealRecord]) -> [String: Int] {
        var grouped: [String: [MealRecord]] = [:]
        for record in records {
            grouped[DayKey.string(from: record.date), default: []].append(record)
        }
        var result: [String: Int] = [:]
        for (day, records) in grouped {
            var hasher = StableHasher()
            for record in records.sorted(by: { $0.mealType.rawValue < $1.mealType.rawValue }) {
                hasher.combine(record.mealType.rawValue)
                hasher.combine(record.memo ?? "")
                hasher.combine(record.beforeImageData?.count ?? 0)
                hasher.combine(record.afterImageData?.count ?? 0)
                hasher.combine(record.ateAll)
                hasher.combine(record.capturedAt?.timeIntervalSince1970 ?? 0)
            }
            result[day] = hasher.finalize()
        }
        return result
    }

    /// 다시 올려야 하는 날: 내용이 바뀐 날 + 기록이 모두 지워진 날(서버에서도 지운다).
    public static func changedDays(current: [String: Int], stored: [String: Int]) -> Set<String> {
        var days = Set<String>()
        for (day, hash) in current where stored[day] != hash { days.insert(day) }
        for day in stored.keys where current[day] == nil { days.insert(day) }
        return days
    }
}
