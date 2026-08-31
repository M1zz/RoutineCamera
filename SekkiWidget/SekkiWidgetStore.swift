//
//  SekkiWidgetStore.swift
//  SekkiWidget (위젯 익스텐션 타깃)
//
//  위젯이 App Group 공유 저장소를 읽고("오늘 상태"), 앱 없이 "다 먹음"을 대기열에 쌓는다.
//  표시/판단 로직은 RoutineCameraCore(WidgetStateResolver)에 있고 여기서는 저장소 입출력만 한다.
//

import Foundation
import AppIntents
import WidgetKit
import RoutineCameraCore

enum SekkiWidgetStore {
    // ⚠️ 앱 본체 AppGroup 의 값들과 반드시 동일
    static let groupID = "group.com.ysoup.RoutineCamera"
    static let dietRecordsKey = "DietMealRecords"
    static let pendingAteAllKey = "pendingAteAll"
    static let widgetSnapshotKey = "widgetSnapshot"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    // 이미지 데이터는 선언하지 않아 디코딩되지 않음 → 위젯 메모리 절약 (스냅샷 없을 때의 폴백용)
    private struct LightMeal: Decodable {
        let date: Date
        let mealType: String
        let capturedAt: Date?
    }

    /// 위젯이 화면에 그릴 현재 상태 (스냅샷 + 아직 앱에 반영 안 된 대기열)
    static func currentState(now: Date = Date()) -> ResolvedWidgetState {
        WidgetStateResolver.resolve(snapshot: loadSnapshot(),
                                    pending: loadPending(),
                                    fallbackTodayCount: fallbackTodayCount(now: now),
                                    now: now)
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: widgetSnapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// 스냅샷이 없을 때만 쓰는 폴백 — 오늘 남긴 기록 수
    static func fallbackTodayCount(now: Date = Date()) -> Int {
        guard let data = defaults.data(forKey: dietRecordsKey),
              let meals = try? JSONDecoder().decode([LightMeal].self, from: data) else { return 0 }
        return meals.filter { Calendar.current.isDate($0.capturedAt ?? $0.date, inSameDayAs: now) }.count
    }

    static func loadPending() -> [PendingAteAll] {
        guard let data = defaults.data(forKey: pendingAteAllKey),
              let items = try? JSONDecoder().decode([PendingAteAll].self, from: data) else { return [] }
        return items
    }

    static func appendPending(_ item: PendingAteAll) {
        var items = loadPending()
        items.append(item)
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: pendingAteAllKey)
        }
    }

    /// 지금 "다 먹음"을 누르면 어떤 기록에 붙어야 하는지 (먹는 중이면 그 기록 마감, 없으면 추론 끼니에 새로)
    static func pendingItemForNow(_ now: Date = Date()) -> PendingAteAll {
        WidgetStateResolver.pendingItem(snapshot: loadSnapshot(), now: now)
    }
}

/// 위젯 버튼 → 앱 없이 "다 먹음"을 대기열에 쌓는다. 앱이 다음에 활성화될 때 실제 기록으로 반영.
struct LogAteAllWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "다 먹음"
    static var description = IntentDescription("방금 먹은 걸 '다 먹음'으로 남깁니다.")

    func perform() async throws -> some IntentResult {
        SekkiWidgetStore.appendPending(SekkiWidgetStore.pendingItemForNow())
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
