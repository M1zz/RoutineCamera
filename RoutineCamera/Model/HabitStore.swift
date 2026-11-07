//
//  HabitStore.swift
//  RoutineCamera
//
//  하루에 붙는 기록(스탬프 · 수분 · 카페인)과 내 스탬프 목록을 보관한다.
//  끼니 기록과 따로 두어 사진 없이도 남길 수 있다. 크기가 작아 App Group 저장소에 JSON 으로 둔다.
//  iCloud 백업은 MealCloudSync 가 끼니 기록과 함께 맡는다.
//

import SwiftUI
import Combine
import RoutineCameraCore
import os

final class HabitStore: ObservableObject {
    static let shared = HabitStore()

    /// 내가 쓰는 스탬프 (보이는 순서)
    @Published private(set) var stamps: [Stamp]
    /// 날짜 키(yyyy-MM-dd) → 그날 기록. 빈 날은 두지 않는다.
    @Published private(set) var logs: [String: DayLog]

    /// 스탬프 목록을 마지막으로 고친 시각 (기기끼리 맞출 때 나중 것이 이긴다)
    private(set) var stampsModifiedAt: Date

    private let defaults: UserDefaults
    private static let stampsKey = "habitStamps_v1"
    private static let stampsModifiedKey = "habitStampsModifiedAt_v1"
    private static let logsKey = "habitDayLogs_v1"

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        stamps = Self.decode([Stamp].self, defaults.data(forKey: Self.stampsKey)) ?? Stamp.defaults
        logs = Self.decode([String: DayLog].self, defaults.data(forKey: Self.logsKey)) ?? [:]
        stampsModifiedAt = defaults.object(forKey: Self.stampsModifiedKey) as? Date ?? .distantPast
    }

    // MARK: - 읽기

    func log(on date: Date) -> DayLog {
        logs[DayKey.string(from: date)] ?? DayLog()
    }

    /// 지운 스탬프라도 지난 기록에 남아 있으면 이름을 보여 줄 수 있게 기본 목록에서도 찾는다
    func stamp(id: String) -> Stamp? {
        stamps.first { $0.id == id } ?? Stamp.catalog.first { $0.id == id }
    }

    // MARK: - 하루 기록

    func toggle(_ stamp: Stamp, on date: Date) {
        update(date) { log in
            if log.stamps.remove(stamp.id) == nil { log.stamps.insert(stamp.id) }
        }
    }

    func addWater(_ delta: Int, on date: Date) {
        update(date) { $0.water = DayLog.clampedCups($0.water + delta) }
    }

    func addCaffeine(_ delta: Int, on date: Date) {
        update(date) { $0.caffeine = DayLog.clampedCups($0.caffeine + delta) }
    }

    private func update(_ date: Date, _ change: (inout DayLog) -> Void) {
        let key = DayKey.string(from: date)
        var log = logs[key] ?? DayLog()
        change(&log)
        guard log != logs[key] ?? DayLog() else { return }
        logs[key] = log.isEmpty ? nil : log
        saveLogs()
    }

    // MARK: - 내 스탬프

    func setStamps(_ newValue: [Stamp]) {
        guard newValue != stamps else { return }
        stamps = newValue
        stampsModifiedAt = Date()
        saveStamps()
    }

    func add(_ stamp: Stamp) {
        guard !stamps.contains(where: { $0.id == stamp.id }) else { return }
        setStamps(stamps + [stamp])
    }

    func remove(_ stamp: Stamp) {
        setStamps(stamps.filter { $0.id != stamp.id })
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = stamps
        reordered.move(fromOffsets: source, toOffset: destination)
        setStamps(reordered)
    }

    // MARK: - iCloud 동기화

    /// 동기화할 문서: 날짜마다 하나, 스탬프 목록 하나. 값은 JSON.
    var syncDocuments: [String: Data] {
        var documents: [String: Data] = [:]
        for (day, log) in logs {
            documents[HabitSyncName.day(day)] = Self.encode(log)
        }
        if stampsModifiedAt != .distantPast {
            documents[HabitSyncName.stamps] = Self.encode(stamps)
        }
        return documents
    }

    /// 문서 하나만 (레코드를 하나씩 만들 때 — 전부 다시 만들지 않게)
    func syncDocument(named name: String) -> Data? {
        if let day = HabitSyncName.dayKey(of: name) { return logs[day].map { Self.encode($0) } }
        if name == HabitSyncName.stamps, stampsModifiedAt != .distantPast { return Self.encode(stamps) }
        return nil
    }

    /// 스탬프 목록은 고친 시각을 따로 기억한다 (날짜 기록은 nil — 동기화가 지금 시각을 쓴다)
    func syncModifiedAt(of name: String) -> Date? {
        name == HabitSyncName.stamps ? stampsModifiedAt : nil
    }

    /// 다른 기기 · iCloud 에서 받은 것을 반영한다. 다시 올라가지 않게 iCloud 에 알리지 않는다.
    func applySyncDocuments(saves: [String: Data], deletes: [String], stampsModifiedAt remoteStampsDate: Date?) {
        var newLogs = logs
        var logsChanged = false
        for name in deletes {
            if let day = HabitSyncName.dayKey(of: name), newLogs.removeValue(forKey: day) != nil { logsChanged = true }
        }
        for (name, data) in saves {
            if let day = HabitSyncName.dayKey(of: name) {
                guard let log = Self.decode(DayLog.self, data) else { continue }
                newLogs[day] = log.isEmpty ? nil : log
                logsChanged = true
            } else if name == HabitSyncName.stamps, let remote = Self.decode([Stamp].self, data) {
                stamps = remote
                stampsModifiedAt = remoteStampsDate ?? Date()
                saveStamps()
            }
        }
        if logsChanged {
            logs = newLogs
            persistLogs()
        }
    }

    #if DEBUG
    /// 스크린샷용: 최근 며칠에 그럴듯한 스탬프 · 잔 수를 채운다 (기존 하루 기록은 지움)
    func seedForScreenshots(days: Int) {
        stamps = Stamp.defaults
        var seeded: [String: DayLog] = [:]
        let today = Calendar.current.startOfDay(for: Date())
        for offset in 0..<days {
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) else { continue }
            var log = DayLog(water: 4 + (offset * 3) % 5, caffeine: 1 + offset % 2)
            if offset % 2 == 0 { log.stamps.insert("vegetables") }
            if offset % 3 == 0 { log.stamps.insert("fish") }
            if offset % 4 == 1 { log.stamps.insert("avocado") }
            if offset < 6 || offset % 3 != 2 { log.stamps.insert("nosugar") }
            if offset % 5 != 4 { log.stamps.insert("nolatesnack") }
            seeded[DayKey.string(from: day)] = log
        }
        logs = seeded
        persistLogs()
        saveStamps()
    }
    #endif

    // MARK: - 저장

    private func saveLogs() {
        persistLogs()
        MealCloudSync.shared.localRecordsChanged()
    }

    private func persistLogs() {
        defaults.set(Self.encode(logs), forKey: Self.logsKey)
    }

    private func saveStamps() {
        defaults.set(Self.encode(stamps), forKey: Self.stampsKey)
        defaults.set(stampsModifiedAt, forKey: Self.stampsModifiedKey)
        MealCloudSync.shared.localRecordsChanged()
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return try encoder.encode(value)
        } catch {
            Log.store.fault("하루 기록을 JSON 으로 만들지 못함: \(String(describing: error))")
            return Data()
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// iCloud 레코드 이름. 끼니 칸(meal_…)과 겹치지 않는다.
enum HabitSyncName {
    static let stamps = "habit_stamps"
    private static let dayPrefix = "habit_day_"

    static func day(_ key: String) -> String { dayPrefix + key }

    static func dayKey(of name: String) -> String? {
        guard name.hasPrefix(dayPrefix) else { return nil }
        let key = String(name.dropFirst(dayPrefix.count))
        return DayKey.date(from: key) == nil ? nil : key
    }

    static func isHabit(_ name: String) -> Bool { name == stamps || dayKey(of: name) != nil }
}

// MARK: - 기본 스탬프 이름

extension Stamp {
    /// 화면에 보이는 이름. 기본 스탬프는 사용자 언어로, 직접 만든 스탬프는 적은 그대로.
    var displayName: String {
        if let name { return name }
        switch id {
        case "vegetables": return String(localized: "채소", comment: "Stamp: ate vegetables")
        case "fish": return String(localized: "생선", comment: "Stamp: ate fish such as salmon")
        case "avocado": return String(localized: "아보카도", comment: "Stamp: ate avocado")
        case "fruit": return String(localized: "과일", comment: "Stamp: ate fruit")
        case "nuts": return String(localized: "견과류", comment: "Stamp: ate nuts")
        case "eggs": return String(localized: "달걀", comment: "Stamp: ate eggs")
        case "beans": return String(localized: "콩", comment: "Stamp: ate beans or tofu")
        case "wholegrain": return String(localized: "잡곡", comment: "Stamp: ate whole grains")
        case "yogurt": return String(localized: "요거트", comment: "Stamp: ate yogurt")
        case "nosugar": return String(localized: "단 것 안 먹음", comment: "Stamp: went without sweets today")
        case "nolatesnack": return String(localized: "야식 안 먹음", comment: "Stamp: no late-night eating today")
        case "noalcohol": return String(localized: "술 안 마심", comment: "Stamp: no alcohol today")
        case "nofried": return String(localized: "튀김 안 먹음", comment: "Stamp: no fried food today")
        case "noflour": return String(localized: "밀가루 안 먹음", comment: "Stamp: no refined flour today")
        case "nosoda": return String(localized: "탄산 안 마심", comment: "Stamp: no soda today")
        case "noovereating": return String(localized: "과식 안 함", comment: "Stamp: did not overeat today")
        default: return symbol
        }
    }
}

extension Stamp.Kind {
    var title: String {
        switch self {
        case .more: return String(localized: "챙길 것", comment: "Stamp group: foods to eat more of")
        case .less: return String(localized: "줄일 것", comment: "Stamp group: things to cut down on")
        }
    }

    var hint: String {
        switch self {
        case .more: return String(localized: "먹은 날에 찍어요", comment: "Stamp group hint: stamp on days you ate it")
        case .less: return String(localized: "참은 날에 찍어요", comment: "Stamp group hint: stamp on days you went without it")
        }
    }

    var color: Color {
        switch self {
        case .more: return .green
        case .less: return .orange
        }
    }
}

extension MealPortion {
    var title: String {
        switch self {
        case .all: return String(localized: "다", comment: "Portion: ate all of it")
        case .half: return String(localized: "절반", comment: "Portion: ate about half")
        case .little: return String(localized: "조금", comment: "Portion: ate a little")
        }
    }

    var tagTitle: String {
        switch self {
        case .all: return String(localized: "다 먹었어요", comment: "Meal tag: ate all of it")
        case .half: return String(localized: "절반 먹었어요", comment: "Meal tag: ate about half")
        case .little: return String(localized: "조금 먹었어요", comment: "Meal tag: ate a little")
        }
    }
}
