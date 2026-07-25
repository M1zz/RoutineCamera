//
//  SekkiWidgetStore.swift
//  SekkiWidget (위젯 익스텐션 타깃)
//
//  위젯이 App Group 공유 저장소를 읽고("오늘 기록 수"), 앱 없이 "다 먹음"을 대기열에 쌓는다.
//  앱 본체의 AppGroup.swift / PendingAteAll 과 동일한 식별자·포맷을 사용한다(경량 중복).
//

import Foundation
import AppIntents
import WidgetKit

enum SekkiWidgetStore {
    // ⚠️ 앱 본체 AppGroup.identifier 와 반드시 동일
    static let groupID = "group.com.ysoup.RoutineCamera"
    static let dietRecordsKey = "DietMealRecords"
    static let pendingAteAllKey = "pendingAteAll"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    // 앱의 PendingAteAll 과 동일 포맷
    struct PendingItem: Codable {
        let mealType: String
        let date: TimeInterval
    }

    // 이미지 데이터는 선언하지 않아 디코딩되지 않음 → 위젯 메모리 절약
    struct LightMeal: Decodable {
        let date: Date
        let mealType: String
        let capturedAt: Date?
    }

    /// 오늘 남긴 기록 수 (저장된 기록 + 아직 반영 안 된 대기열)
    static func todayRecordCount() -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var count = 0
        if let data = defaults.data(forKey: dietRecordsKey),
           let meals = try? JSONDecoder().decode([LightMeal].self, from: data) {
            count += meals.filter { cal.isDate($0.capturedAt ?? $0.date, inSameDayAs: today) }.count
        }
        count += loadPending().filter { cal.isDate(Date(timeIntervalSince1970: $0.date), inSameDayAs: today) }.count
        return count
    }

    static func loadPending() -> [PendingItem] {
        guard let data = defaults.data(forKey: pendingAteAllKey),
              let items = try? JSONDecoder().decode([PendingItem].self, from: data) else { return [] }
        return items
    }

    static func appendPending(_ item: PendingItem) {
        var items = loadPending()
        items.append(item)
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: pendingAteAllKey)
        }
    }

    /// 현재 시각으로 끼니 추론 (앱의 MealType.inferred 와 동일 규칙, rawValue 문자열 반환)
    static func inferredMealType() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5...10:  return "아침"
        case 11...15: return "점심"
        case 16...21: return "저녁"
        default:      return "간식1"
        }
    }
}

/// 위젯 버튼 → 앱 없이 "다 먹음"을 대기열에 쌓는다. 앱이 다음에 활성화될 때 실제 기록으로 반영.
struct LogAteAllWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "다 먹음"
    static var description = IntentDescription("방금 먹은 걸 '다 먹음'으로 남깁니다.")

    func perform() async throws -> some IntentResult {
        SekkiWidgetStore.appendPending(
            .init(mealType: SekkiWidgetStore.inferredMealType(),
                  date: Date().timeIntervalSince1970)
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
