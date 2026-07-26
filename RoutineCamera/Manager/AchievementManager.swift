//
//  AchievementManager.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import Foundation
import SwiftUI

// 업적 구조체
struct Achievement: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let color: String
    var isUnlocked: Bool = false
    var unlockedDate: Date?
}

import Combine

class AchievementManager: ObservableObject {
    static let shared = AchievementManager()

    @Published var achievements: [Achievement] = []

    private let achievementsKey = "user_achievements"

    private init() {
        loadAchievements()
    }

    // 기본 업적 목록
    private func createDefaultAchievements() -> [Achievement] {
        return [
            // 연속 기록 업적
            Achievement(
                id: "streak_7",
                title: "일주일 연속",
                description: "7일 연속으로 기록했어요",
                icon: "🔥",
                color: "orange"
            ),
            Achievement(
                id: "streak_14",
                title: "2주 연속",
                description: "14일 연속으로 기록했어요",
                icon: "💪",
                color: "red"
            ),
            Achievement(
                id: "streak_30",
                title: "한 달 연속",
                description: "30일 연속으로 기록했어요",
                icon: "🏆",
                color: "yellow"
            ),
            Achievement(
                id: "streak_100",
                title: "100일 연속",
                description: "100일 연속으로 기록했어요",
                icon: "👑",
                color: "purple"
            ),

            // 식사별 업적
            Achievement(
                id: "breakfast_30",
                title: "아침형 인간",
                description: "아침 식사 30회 기록",
                icon: "🌅",
                color: "orange"
            ),
            Achievement(
                id: "lunch_30",
                title: "점심 마스터",
                description: "점심 식사 30회 기록",
                icon: "☀️",
                color: "yellow"
            ),
            Achievement(
                id: "dinner_30",
                title: "저녁 달인",
                description: "저녁 식사 30회 기록",
                icon: "🌙",
                color: "blue"
            ),

            // 총 기록 업적
            Achievement(
                id: "total_50",
                title: "기록의 시작",
                description: "총 50회 기록 달성",
                icon: "📝",
                color: "green"
            ),
            Achievement(
                id: "total_100",
                title: "백전백승",
                description: "총 100회 기록 달성",
                icon: "💯",
                color: "blue"
            ),
            Achievement(
                id: "total_300",
                title: "삼백 기록",
                description: "총 300회 기록 달성",
                icon: "🎯",
                color: "red"
            ),
            Achievement(
                id: "total_500",
                title: "오백 돌파",
                description: "총 500회 기록 달성",
                icon: "⭐",
                color: "yellow"
            ),

            // 사진 업적
            Achievement(
                id: "photo_100",
                title: "사진 마니아",
                description: "사진 100장 촬영",
                icon: "📸",
                color: "purple"
            ),

            // 메모 업적
            Achievement(
                id: "memo_50",
                title: "메모의 달인",
                description: "메모 50개 작성",
                icon: "✍️",
                color: "brown"
            ),

            // 완벽한 주/월
            Achievement(
                id: "perfect_week",
                title: "완벽한 일주일",
                description: "일주일 동안 모든 끼니 기록",
                icon: "🌟",
                color: "yellow"
            ),
            Achievement(
                id: "perfect_month",
                title: "완벽한 한 달",
                description: "한 달 동안 모든 끼니 기록",
                icon: "🎊",
                color: "rainbow"
            )
        ]
    }

    // 업적 로드
    private func loadAchievements() {
        if let data = UserDefaults.standard.data(forKey: achievementsKey),
           let decoded = try? JSONDecoder().decode([Achievement].self, from: data) {
            achievements = decoded
        } else {
            // 기본 업적 생성
            achievements = createDefaultAchievements()
            saveAchievements()
        }
    }

    // 업적 저장
    private func saveAchievements() {
        if let encoded = try? JSONEncoder().encode(achievements) {
            UserDefaults.standard.set(encoded, forKey: achievementsKey)
        }
    }

    // 업적 체크 및 잠금 해제
    func checkAndUnlockAchievements(mealStore: MealRecordStore) {
        var newUnlocks: [Achievement] = []

        let maxStreak = mealStore.getMaxStreak()

        // 연속 기록 업적 체크
        checkStreakAchievement(id: "streak_7", requiredStreak: 7, currentStreak: maxStreak, newUnlocks: &newUnlocks)
        checkStreakAchievement(id: "streak_14", requiredStreak: 14, currentStreak: maxStreak, newUnlocks: &newUnlocks)
        checkStreakAchievement(id: "streak_30", requiredStreak: 30, currentStreak: maxStreak, newUnlocks: &newUnlocks)
        checkStreakAchievement(id: "streak_100", requiredStreak: 100, currentStreak: maxStreak, newUnlocks: &newUnlocks)

        // 식사별 업적 체크 (식단 모드일 때만)
        if SettingsManager.shared.albumType == .diet {
            let breakfastCount = countMealType(.breakfast, in: mealStore)
            let lunchCount = countMealType(.lunch, in: mealStore)
            let dinnerCount = countMealType(.dinner, in: mealStore)

            checkCountAchievement(id: "breakfast_30", requiredCount: 30, currentCount: breakfastCount, newUnlocks: &newUnlocks)
            checkCountAchievement(id: "lunch_30", requiredCount: 30, currentCount: lunchCount, newUnlocks: &newUnlocks)
            checkCountAchievement(id: "dinner_30", requiredCount: 30, currentCount: dinnerCount, newUnlocks: &newUnlocks)
        }

        // 총 기록 업적 체크
        let totalCount = mealStore.getTotalRecordCount()
        checkCountAchievement(id: "total_50", requiredCount: 50, currentCount: totalCount, newUnlocks: &newUnlocks)
        checkCountAchievement(id: "total_100", requiredCount: 100, currentCount: totalCount, newUnlocks: &newUnlocks)
        checkCountAchievement(id: "total_300", requiredCount: 300, currentCount: totalCount, newUnlocks: &newUnlocks)
        checkCountAchievement(id: "total_500", requiredCount: 500, currentCount: totalCount, newUnlocks: &newUnlocks)

        // 사진 업적 체크
        let photoCount = mealStore.getTotalPhotoCount()
        checkCountAchievement(id: "photo_100", requiredCount: 100, currentCount: photoCount, newUnlocks: &newUnlocks)

        // 메모 업적 체크
        let memoCount = mealStore.getTotalMemoCount()
        checkCountAchievement(id: "memo_50", requiredCount: 50, currentCount: memoCount, newUnlocks: &newUnlocks)

        // 완벽한 주/월 체크
        if checkPerfectWeek(mealStore: mealStore) {
            unlockAchievement(id: "perfect_week", newUnlocks: &newUnlocks)
        }

        if checkPerfectMonth(mealStore: mealStore) {
            unlockAchievement(id: "perfect_month", newUnlocks: &newUnlocks)
        }

        saveAchievements()
    }

    // 연속 기록 업적 체크
    private func checkStreakAchievement(id: String, requiredStreak: Int, currentStreak: Int, newUnlocks: inout [Achievement]) {
        if currentStreak >= requiredStreak {
            unlockAchievement(id: id, newUnlocks: &newUnlocks)
        }
    }

    // 카운트 업적 체크
    private func checkCountAchievement(id: String, requiredCount: Int, currentCount: Int, newUnlocks: inout [Achievement]) {
        if currentCount >= requiredCount {
            unlockAchievement(id: id, newUnlocks: &newUnlocks)
        }
    }

    // 업적 잠금 해제
    private func unlockAchievement(id: String, newUnlocks: inout [Achievement]) {
        if let index = achievements.firstIndex(where: { $0.id == id }), !achievements[index].isUnlocked {
            achievements[index].isUnlocked = true
            achievements[index].unlockedDate = Date()
            newUnlocks.append(achievements[index])
        }
    }

    // 특정 식사 타입 개수 세기
    private func countMealType(_ mealType: MealType, in mealStore: MealRecordStore) -> Int {
        var count = 0
        let calendar = Calendar.current
        let today = Date()

        // 최근 1년 데이터 확인
        for day in 0..<365 {
            if let date = calendar.date(byAdding: .day, value: -day, to: today) {
                let meals = mealStore.getMeals(for: date)
                if meals[mealType]?.isComplete ?? false {
                    count += 1
                }
            }
        }

        return count
    }

    // 완벽한 주 체크
    private func checkPerfectWeek(mealStore: MealRecordStore) -> Bool {
        let calendar = Calendar.current
        let today = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        let isExerciseMode = SettingsManager.shared.albumType == .exercise
        let requiredPerDay = isExerciseMode ? 1 : 3

        for day in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: day, to: startOfWeek) {
                let meals = mealStore.getMeals(for: date)
                let completedCount = meals.values.filter { $0.isComplete }.count

                if completedCount < requiredPerDay {
                    return false
                }
            }
        }

        return true
    }

    // 완벽한 월 체크
    private func checkPerfectMonth(mealStore: MealRecordStore) -> Bool {
        let calendar = Calendar.current
        let today = Date()
        let range = calendar.range(of: .day, in: .month, for: today)!
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!

        let isExerciseMode = SettingsManager.shared.albumType == .exercise
        let requiredPerDay = isExerciseMode ? 1 : 3

        for day in 0..<range.count {
            if let date = calendar.date(byAdding: .day, value: day, to: startOfMonth) {
                let meals = mealStore.getMeals(for: date)
                let completedCount = meals.values.filter { $0.isComplete }.count

                if completedCount < requiredPerDay {
                    return false
                }
            }
        }

        return true
    }
}
