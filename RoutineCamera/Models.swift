//
//  Models.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import Foundation
import SwiftUI
import Combine

// 식사 타입 정의
enum MealType: String, CaseIterable, Codable {
    case breakfast = "아침"
    case lunch = "점심"
    case dinner = "저녁"

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        }
    }

    var symbolColor: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .blue
        }
    }
}

// 식사 기록 모델
struct MealRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let mealType: MealType
    let beforeImageData: Data?  // 식전 사진
    let afterImageData: Data?   // 식후 사진
    var memo: String?

    init(date: Date, mealType: MealType, beforeImageData: Data? = nil, afterImageData: Data? = nil, memo: String? = nil) {
        self.id = UUID()
        self.date = date
        self.mealType = mealType
        self.beforeImageData = beforeImageData
        self.afterImageData = afterImageData
        self.memo = memo
    }

    // 썸네일용 이미지 (식후 있으면 식후, 없으면 식전)
    var thumbnailImageData: Data? {
        return afterImageData ?? beforeImageData
    }

    // 기록이 완료되었는지 (최소 1개 사진 있으면 완료)
    var isComplete: Bool {
        return beforeImageData != nil || afterImageData != nil
    }
}

// 날짜별 식사 기록을 관리하는 ObservableObject
@MainActor
class MealRecordStore: ObservableObject {
    @Published var records: [MealRecord] = []

    private let userDefaults = UserDefaults.standard
    private let recordsKey = "MealRecords"

    init() {
        loadRecords()
    }

    // 특정 날짜의 식사 기록들 가져오기
    func getMeals(for date: Date) -> [MealType: MealRecord] {
        let targetDate = Calendar.current.startOfDay(for: date)
        let dayRecords = records.filter {
            Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }

        var mealDict: [MealType: MealRecord] = [:]
        for record in dayRecords {
            mealDict[record.mealType] = record
        }
        return mealDict
    }

    // 식사 기록 추가 또는 업데이트 (식전/식후 지정)
    func addOrUpdateMeal(date: Date, mealType: MealType, imageData: Data, isBefore: Bool) {
        let targetDate = Calendar.current.startOfDay(for: date)

        // 기존 기록 찾기
        if let existingIndex = records.firstIndex(where: {
            $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) {
            // 기존 기록 업데이트
            let existing = records[existingIndex]
            if isBefore {
                records[existingIndex] = MealRecord(
                    date: targetDate,
                    mealType: mealType,
                    beforeImageData: imageData,
                    afterImageData: existing.afterImageData,
                    memo: existing.memo
                )
            } else {
                records[existingIndex] = MealRecord(
                    date: targetDate,
                    mealType: mealType,
                    beforeImageData: existing.beforeImageData,
                    afterImageData: imageData,
                    memo: existing.memo
                )
            }
        } else {
            // 새 기록 추가
            let newRecord = MealRecord(
                date: targetDate,
                mealType: mealType,
                beforeImageData: isBefore ? imageData : nil,
                afterImageData: isBefore ? nil : imageData
            )
            records.append(newRecord)
        }

        saveRecords()
    }

    // 식사 기록 삭제
    func deleteMeal(date: Date, mealType: MealType) {
        let targetDate = Calendar.current.startOfDay(for: date)

        let beforeCount = records.count
        records.removeAll { record in
            record.mealType == mealType && Calendar.current.isDate(record.date, inSameDayAs: targetDate)
        }
        let afterCount = records.count

        print("🗑️ [MealRecordStore] 식사 기록 삭제: \(mealType.rawValue), 날짜: \(targetDate)")
        print("🗑️ [MealRecordStore] 삭제 전: \(beforeCount)개, 삭제 후: \(afterCount)개")

        saveRecords()
    }

    // 메모 업데이트
    func updateMemo(date: Date, mealType: MealType, memo: String?) {
        let targetDate = Calendar.current.startOfDay(for: date)

        if let existingIndex = records.firstIndex(where: {
            $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) {
            let existing = records[existingIndex]
            records[existingIndex] = MealRecord(
                date: existing.date,
                mealType: existing.mealType,
                beforeImageData: existing.beforeImageData,
                afterImageData: existing.afterImageData,
                memo: memo
            )
            saveRecords()
        }
    }

    // 기록 저장
    private func saveRecords() {
        if let encoded = try? JSONEncoder().encode(records) {
            userDefaults.set(encoded, forKey: recordsKey)
        }
    }

    // 기록 불러오기
    private func loadRecords() {
        if let data = userDefaults.data(forKey: recordsKey),
           let decoded = try? JSONDecoder().decode([MealRecord].self, from: data) {
            records = decoded
        }
    }

    // MARK: - Streak 계산

    // 현재 연속 기록 일수 계산
    func getCurrentStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 오늘 기록이 완료되었는지 확인
        let todayMeals = getMeals(for: today)
        let todayComplete = todayMeals.count == 3 && todayMeals.values.allSatisfy { $0.isComplete }

        var streak = 0
        var currentDate = today

        // 오늘부터 과거로 거슬러 올라가며 연속 기록 확인
        while true {
            let meals = getMeals(for: currentDate)
            let isComplete = meals.count == 3 && meals.values.allSatisfy { $0.isComplete }

            if isComplete {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                    break
                }
                currentDate = previousDay
            } else {
                // 오늘이 아직 완료되지 않았다면, 어제부터 확인
                if calendar.isDate(currentDate, inSameDayAs: today) && !todayComplete {
                    guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                        break
                    }
                    currentDate = previousDay
                    continue
                }
                break
            }
        }

        return streak
    }

    // 최고 연속 기록 일수
    func getMaxStreak() -> Int {
        let calendar = Calendar.current
        var maxStreak = 0
        var currentStreak = 0

        // 모든 날짜별로 정렬
        let sortedDates = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted()

        guard !sortedDates.isEmpty else { return 0 }

        for (index, date) in sortedDates.enumerated() {
            let meals = getMeals(for: date)
            let isComplete = meals.count == 3 && meals.values.allSatisfy { $0.isComplete }

            if isComplete {
                // 이전 날짜와 연속인지 확인
                if index > 0,
                   let previousDate = sortedDates[safe: index - 1],
                   let nextDay = calendar.date(byAdding: .day, value: 1, to: previousDate),
                   calendar.isDate(nextDay, inSameDayAs: date) {
                    currentStreak += 1
                } else {
                    currentStreak = 1
                }

                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }

        return maxStreak
    }

    // MARK: - 개발용 샘플 데이터 생성

    func generateSampleData() {
        print("🎨 [MealRecordStore] 샘플 데이터 생성 시작")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 과거 30일간의 샘플 데이터 생성
        for dayOffset in (1...30).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }

            // 80% 확률로 각 식사 기록 생성
            for mealType in MealType.allCases {
                if Double.random(in: 0...1) < 0.8 {
                    let hasBefore = Double.random(in: 0...1) < 0.7 // 70% 확률로 식전 사진
                    let hasAfter = Double.random(in: 0...1) < 0.7  // 70% 확률로 식후 사진

                    if hasBefore || hasAfter {
                        let beforeImage = hasBefore ? generateSampleImage(mealType: mealType, isBefore: true) : nil
                        let afterImage = hasAfter ? generateSampleImage(mealType: mealType, isBefore: false) : nil

                        let hasMemo = Double.random(in: 0...1) < 0.3 // 30% 확률로 메모
                        let memo = hasMemo ? "샘플 메모 - \(mealType.rawValue)" : nil

                        let record = MealRecord(
                            date: date,
                            mealType: mealType,
                            beforeImageData: beforeImage,
                            afterImageData: afterImage,
                            memo: memo
                        )
                        records.append(record)
                    }
                }
            }
        }

        saveRecords()
        print("🎨 [MealRecordStore] 샘플 데이터 생성 완료: \(records.count)개 기록 추가")
    }

    // 샘플 이미지 생성 (단색 배경 + 텍스트)
    private func generateSampleImage(mealType: MealType, isBefore: Bool) -> Data? {
        let size = CGSize(width: 600, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            // 배경색 설정
            let backgroundColor: UIColor
            switch mealType {
            case .breakfast:
                backgroundColor = isBefore ? UIColor.orange.withAlphaComponent(0.3) : UIColor.orange.withAlphaComponent(0.6)
            case .lunch:
                backgroundColor = isBefore ? UIColor.yellow.withAlphaComponent(0.3) : UIColor.yellow.withAlphaComponent(0.6)
            case .dinner:
                backgroundColor = isBefore ? UIColor.blue.withAlphaComponent(0.3) : UIColor.blue.withAlphaComponent(0.6)
            }

            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // 텍스트 추가
            let text = "\(mealType.rawValue)\n\(isBefore ? "식전" : "식후")"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 60),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -3.0
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)
        }

        return image.jpegData(compressionQuality: 0.8)
    }

    // 모든 데이터 삭제 (개발용)
    func clearAllData() {
        print("🗑️ [MealRecordStore] 모든 데이터 삭제")
        records.removeAll()
        saveRecords()
    }
}

// Array extension for safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
