//
//  PendingAteAll.swift
//  RoutineCameraCore
//
//  위젯/알림에서 앱 없이 남긴 "다 먹음"을 앱이 반영하기 전까지 쌓아두는 대기열 항목.
//

import Foundation

public struct PendingAteAll: Codable, Sendable, Equatable {
    public let mealType: String    // MealType.rawValue
    public let date: TimeInterval  // 기준 날짜 (timeIntervalSince1970)

    public init(mealType: String, date: TimeInterval) {
        self.mealType = mealType
        self.date = date
    }
}
