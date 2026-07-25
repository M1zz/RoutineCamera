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
}

/// 앱을 실행하지 않고 위젯에서 "다 먹음"을 눌렀을 때 공유 저장소에 쌓이는 항목.
/// 앱이 다음에 활성화될 때 MealRecordStore가 읽어서 실제 기록으로 반영한다.
struct PendingAteAll: Codable {
    let mealType: String       // MealType.rawValue
    let date: TimeInterval     // 기준 날짜 (timeIntervalSince1970)
}
