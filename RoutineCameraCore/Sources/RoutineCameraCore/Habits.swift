//
//  Habits.swift
//  RoutineCameraCore
//
//  열량을 세지 않고 스스로 식단을 조절하도록 돕는 기록.
//  - 스탬프: 내가 정한 습관. 챙길 것(연어, 채소…)은 먹은 날에, 줄일 것(설탕, 야식…)은 참은 날에 찍는다.
//  - 수분 · 카페인: 잔 수만 센다.
//  - 먹은 양: 끼니마다 다 / 절반 / 조금.
//  스탬프와 잔 수는 끼니가 아니라 하루에 붙는다 — 사진을 찍지 않은 날에도 남길 수 있다.
//

import Foundation

/// 스탬프 한 종류.
public struct Stamp: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 챙길 것 — 먹은 날에 찍는다
        case more
        /// 줄일 것 — 참은 날에 찍는다
        case less
    }

    /// 기본 스탬프는 고정 id(예: "salmon"), 직접 만든 스탬프는 "custom-<UUID>".
    public let id: String
    public var symbol: String
    /// 직접 만든 스탬프의 이름. 기본 스탬프는 nil 이고 앱이 사용자 언어로 이름을 붙인다.
    public var name: String?
    public var kind: Kind

    public init(id: String, symbol: String, name: String? = nil, kind: Kind) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.kind = kind
    }

    public var isCustom: Bool { id.hasPrefix(Self.customPrefix) }

    public static let customPrefix = "custom-"

    public static func custom(symbol: String, name: String, kind: Kind) -> Stamp {
        Stamp(id: customPrefix + UUID().uuidString, symbol: symbol, name: name, kind: kind)
    }

    /// 처음 쓰는 사람에게 깔아 두는 스탬프. 순서대로 보인다.
    public static let defaults: [Stamp] = [
        Stamp(id: "vegetables", symbol: "🥗", kind: .more),
        Stamp(id: "fish", symbol: "🐟", kind: .more),
        Stamp(id: "avocado", symbol: "🥑", kind: .more),
        Stamp(id: "fruit", symbol: "🍎", kind: .more),
        Stamp(id: "nuts", symbol: "🥜", kind: .more),
        Stamp(id: "nosugar", symbol: "🍬", kind: .less),
        Stamp(id: "nolatesnack", symbol: "🌙", kind: .less),
        Stamp(id: "noalcohol", symbol: "🍺", kind: .less),
    ]

    /// 고를 수 있는 기본 스탬프 전부 (지운 것을 다시 넣을 때)
    public static let catalog: [Stamp] = defaults + [
        Stamp(id: "eggs", symbol: "🥚", kind: .more),
        Stamp(id: "beans", symbol: "🫘", kind: .more),
        Stamp(id: "wholegrain", symbol: "🍚", kind: .more),
        Stamp(id: "yogurt", symbol: "🥛", kind: .more),
        Stamp(id: "nofried", symbol: "🍟", kind: .less),
        Stamp(id: "noflour", symbol: "🍞", kind: .less),
        Stamp(id: "nosoda", symbol: "🥤", kind: .less),
        Stamp(id: "noovereating", symbol: "🍽️", kind: .less),
    ]
}

/// 하루의 기록. 저장 키는 DayKey(yyyy-MM-dd).
public struct DayLog: Codable, Equatable, Sendable {
    public var stamps: Set<String>
    public var water: Int
    public var caffeine: Int

    public init(stamps: Set<String> = [], water: Int = 0, caffeine: Int = 0) {
        self.stamps = stamps
        self.water = water
        self.caffeine = caffeine
    }

    public var isEmpty: Bool { stamps.isEmpty && water == 0 && caffeine == 0 }

    /// 잔 수를 바꾼다. 0 아래로 내려가지 않고, 잘못 눌러 끝없이 늘지 않게 하루 30잔에서 멈춘다.
    public static func clampedCups(_ value: Int) -> Int { min(max(value, 0), 30) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stamps = try c.decodeIfPresent(Set<String>.self, forKey: .stamps) ?? []
        water = try c.decodeIfPresent(Int.self, forKey: .water) ?? 0
        caffeine = try c.decodeIfPresent(Int.self, forKey: .caffeine) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case stamps, water, caffeine }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // 순서를 고정해 같은 내용이면 같은 바이트가 되게 한다 (동기화 지문)
        try c.encode(stamps.sorted(), forKey: .stamps)
        try c.encode(water, forKey: .water)
        try c.encode(caffeine, forKey: .caffeine)
    }
}

/// 끼니 하나를 얼마나 먹었는지.
public enum MealPortion: String, Codable, CaseIterable, Sendable {
    case all
    case half
    case little
}

/// 스탬프 · 잔 수를 돌아보는 계산. 날짜 키(yyyy-MM-dd)로 된 기록을 받는다.
public enum HabitStats {
    /// 이 스탬프를 찍은 날 수 (기간 안)
    public static func count(of stampID: String, in logs: [String: DayLog], from start: Date, to end: Date) -> Int {
        let lower = DayKey.string(from: start), upper = DayKey.string(from: end)
        return logs.filter { $0.key >= lower && $0.key <= upper && $0.value.stamps.contains(stampID) }.count
    }

    /// 오늘(또는 어제)까지 이어서 찍은 날 수. 오늘 아직 안 찍었으면 어제까지를 센다 — 하루가 끝나기 전엔 끊긴 게 아니다.
    public static func currentStreak(of stampID: String, in logs: [String: DayLog],
                                     today: Date = Date(), calendar: Calendar = .current) -> Int {
        func stamped(_ date: Date) -> Bool { logs[DayKey.string(from: date)]?.stamps.contains(stampID) == true }
        var day = calendar.startOfDay(for: today)
        if !stamped(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while stamped(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// 가장 길게 이어서 찍은 날 수
    public static func longestStreak(of stampID: String, in logs: [String: DayLog], calendar: Calendar = .current) -> Int {
        let days = logs.filter { $0.value.stamps.contains(stampID) }
            .compactMap { DayKey.date(from: $0.key).map { calendar.startOfDay(for: $0) } }
            .sorted()
        var longest = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }

    /// 기간 안 끼니들의 먹은 양 비율 — 양을 남긴 끼니만 센다.
    public static func portionCounts(of records: [MealRecord]) -> [MealPortion: Int] {
        records.reduce(into: [:]) { counts, record in
            if let portion = record.portion { counts[portion, default: 0] += 1 }
        }
    }
}
