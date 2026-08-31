//
//  AppGroup.swift
//  RoutineCamera
//
//  앱과 위젯 익스텐션이 데이터를 공유하기 위한 App Group 저장소.
//  위젯이 최근 순간을 읽고, 위젯/알림에서 "다 먹음"을 쓸 수 있게 한다.
//

import Foundation

enum AppGroup {
    /// Xcode Signing & Capabilities > App Groups 에 등록한 식별자와 반드시 동일해야 한다.
    static let identifier = "group.com.ysoup.RoutineCamera"

    /// 공유 UserDefaults. suite 생성 실패 시(식별자 미등록 등) 표준 저장소로 폴백.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    // 식단/운동 기록 저장 키 (MealRecordStore와 공유 — 위젯에서도 동일 키로 읽음)
    static let dietRecordsKey = "DietMealRecords"
    static let exerciseRecordsKey = "ExerciseMealRecords"

    // 위젯/알림에서 앱 없이 남긴 "다 먹음"을 앱이 반영하기 전까지 쌓아두는 대기열 키
    static let pendingAteAllKey = "pendingAteAll"

    // 위젯이 읽는 경량 스냅샷 키 (사진 데이터를 디코딩하지 않도록 앱이 미리 요약해 둔다)
    static let widgetSnapshotKey = "widgetSnapshot"
}

/// 위젯 표시용 경량 스냅샷. 위젯은 사진이 담긴 기록 전체를 디코딩하지 않고 이것만 읽는다.
/// 앱이 기록을 저장할 때마다 갱신한다.
/// ⚠️ 위젯은 이 JSON을 RoutineCameraCore 의 `WidgetSnapshot` 으로 디코딩한다 — 필드 이름을 바꾸면
/// 위젯이 조용히 빈 상태가 된다. 계약은 WidgetSharedStateTests.testSnapshot_decodesAppSideJSON 이 고정한다.
struct WidgetSnapshot: Codable {
    let todayCount: Int              // 오늘 남긴 기록 수
    let inProgressMealType: String?  // 오늘 "먹는 중"인 끼니 (식전만 찍힌 것) — 없으면 nil
    let inProgressSince: Date?       // 그 기록의 촬영 시각
    let lastRecordedAt: Date?        // 오늘 마지막 기록 시각
    let needsRecordCount: Int        // 날이 지나 "기록 필요"로 남은 기록 수
    let generatedAt: Date
}

/// 앱을 실행하지 않고 위젯에서 "다 먹음"을 눌렀을 때 공유 저장소에 쌓이는 항목.
/// 앱이 다음에 활성화될 때 MealRecordStore가 읽어서 실제 기록으로 반영한다.
struct PendingAteAll: Codable {
    let mealType: String       // MealType.rawValue
    let date: TimeInterval     // 기준 날짜 (timeIntervalSince1970)
}
