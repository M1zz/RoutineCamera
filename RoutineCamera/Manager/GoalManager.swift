//
//  GoalManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import Foundation
import SwiftUI
import Combine

class GoalManager: ObservableObject {
    static let shared = GoalManager()

    @Published var goalDays: Int {
        didSet {
            UserDefaults.standard.set(goalDays, forKey: "goalDays")
        }
    }

    @Published var goalEnabled: Bool {
        didSet {
            UserDefaults.standard.set(goalEnabled, forKey: "goalEnabled")
        }
    }

    private init() {
        self.goalDays = UserDefaults.standard.integer(forKey: "goalDays")
        self.goalEnabled = UserDefaults.standard.bool(forKey: "goalEnabled")

        // 기본값 설정
        if goalDays == 0 {
            goalDays = 30
        }
    }

    // 목표 진행률 계산
    func getProgress(currentStreak: Int) -> Double {
        guard goalEnabled && goalDays > 0 else { return 0 }
        return min(Double(currentStreak) / Double(goalDays), 1.0)
    }

    // 목표 달성 여부
    func isGoalAchieved(currentStreak: Int) -> Bool {
        return goalEnabled && currentStreak >= goalDays
    }
}
