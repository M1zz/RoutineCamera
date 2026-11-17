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
    /// 버튼을 누른 시각 — 앱이 나중에 반영해도 식사가 끝난 시각은 누른 때다. 예전 버전이 쌓은 항목은 nil
    public let tappedAt: TimeInterval?

    public init(mealType: String, date: TimeInterval, tappedAt: TimeInterval? = nil) {
        self.mealType = mealType
        self.date = date
        self.tappedAt = tappedAt
    }
}
