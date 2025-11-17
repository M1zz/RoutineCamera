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
enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast = "아침"
    case lunch = "점심"
    case dinner = "저녁"

    var id: String { self.rawValue }

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
    let recordedWithoutPhoto: Bool  // 사진 없이 기록했는지
    var hidePhotoCountBadge: Bool  // 이 식사의 사진 개수 알림 숨기기

    init(date: Date, mealType: MealType, beforeImageData: Data? = nil, afterImageData: Data? = nil, memo: String? = nil, recordedWithoutPhoto: Bool = false, hidePhotoCountBadge: Bool = false) {
        self.id = UUID()
        self.date = date
        self.mealType = mealType
        self.beforeImageData = beforeImageData
        self.afterImageData = afterImageData
        self.memo = memo
        self.recordedWithoutPhoto = recordedWithoutPhoto
        self.hidePhotoCountBadge = hidePhotoCountBadge
    }

    // 기존 데이터 호환성을 위한 커스텀 디코딩
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        mealType = try container.decode(MealType.self, forKey: .mealType)
        beforeImageData = try container.decodeIfPresent(Data.self, forKey: .beforeImageData)
        afterImageData = try container.decodeIfPresent(Data.self, forKey: .afterImageData)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        // 기존 데이터에는 recordedWithoutPhoto가 없을 수 있으므로 기본값 false 사용
        recordedWithoutPhoto = try container.decodeIfPresent(Bool.self, forKey: .recordedWithoutPhoto) ?? false
        // 기존 데이터에는 hidePhotoCountBadge가 없을 수 있으므로 기본값 false 사용
        hidePhotoCountBadge = try container.decodeIfPresent(Bool.self, forKey: .hidePhotoCountBadge) ?? false
    }

    // 썸네일용 이미지 (식후 있으면 식후, 없으면 식전)
    var thumbnailImageData: Data? {
        return afterImageData ?? beforeImageData
    }

    // 기록이 완료되었는지 (최소 1개 사진 있거나 사진 없이 기록했으면 완료)
    var isComplete: Bool {
        return beforeImageData != nil || afterImageData != nil || recordedWithoutPhoto
    }
}

// 날짜별 식사 기록을 관리하는 ObservableObject
@MainActor
class MealRecordStore: ObservableObject {
    // 식단과 운동을 완전히 별개로 저장
    @Published private var dietRecords: [MealRecord] = []
    @Published private var exerciseRecords: [MealRecord] = []

    // 현재 앨범 타입에 따라 적절한 레코드 반환
    var records: [MealRecord] {
        get {
            switch SettingsManager.shared.albumType {
            case .diet:
                return dietRecords
            case .exercise:
                return exerciseRecords
            }
        }
        set {
            switch SettingsManager.shared.albumType {
            case .diet:
                dietRecords = newValue
            case .exercise:
                exerciseRecords = newValue
            }
            saveRecords()
        }
    }

    private let userDefaults = UserDefaults.standard
    private let dietRecordsKey = "DietMealRecords"
    private let exerciseRecordsKey = "ExerciseMealRecords"
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadRecords()
        migrateOldDataIfNeeded()

        // SettingsManager의 albumType 변경 감지
        SettingsManager.shared.$albumType
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // 기존 데이터를 식단 전용으로 마이그레이션
    private func migrateOldDataIfNeeded() {
        let oldKey = "MealRecords"

        // 기존 키에 데이터가 있는지 확인
        guard userDefaults.data(forKey: oldKey) != nil else {
            print("📦 [Migration] 마이그레이션 필요 없음 - 기존 데이터 없음")
            return
        }

        // 이미 마이그레이션 했는지 확인
        let migrationKey = "DataMigrated_v1"
        guard !userDefaults.bool(forKey: migrationKey) else {
            print("📦 [Migration] 이미 마이그레이션 완료됨")
            return
        }

        // 기존 데이터를 식단 데이터로 이동
        if let oldData = userDefaults.data(forKey: oldKey),
           let oldRecords = try? JSONDecoder().decode([MealRecord].self, from: oldData) {
            dietRecords = oldRecords
            if let encoded = try? JSONEncoder().encode(dietRecords) {
                userDefaults.set(encoded, forKey: dietRecordsKey)
                print("📦 [Migration] 기존 \(oldRecords.count)개 기록을 식단으로 마이그레이션 완료")
            }

            // 기존 데이터 삭제
            userDefaults.removeObject(forKey: oldKey)

            // 마이그레이션 완료 플래그 설정
            userDefaults.set(true, forKey: migrationKey)
        }
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

        // 현재 앨범 타입에 따라 적절한 배열 사용
        var currentRecords = records

        // 기존 기록 찾기
        if let existingIndex = currentRecords.firstIndex(where: {
            $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) {
            // 기존 기록 업데이트
            let existing = currentRecords[existingIndex]
            if isBefore {
                currentRecords[existingIndex] = MealRecord(
                    date: targetDate,
                    mealType: mealType,
                    beforeImageData: imageData,
                    afterImageData: existing.afterImageData,
                    memo: existing.memo
                )
            } else {
                currentRecords[existingIndex] = MealRecord(
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
            currentRecords.append(newRecord)
        }

        // 다시 할당하여 setter 호출
        records = currentRecords

        // 업적 체크
        AchievementManager.shared.checkAndUnlockAchievements(mealStore: self)
    }

    // 사진 없이 기록
    func recordWithoutPhoto(date: Date, mealType: MealType) {
        let targetDate = Calendar.current.startOfDay(for: date)

        var currentRecords = records

        // 이미 기록이 있는지 확인
        if currentRecords.contains(where: {
            $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) {
            print("⚠️ [MealRecordStore] 이미 기록이 있습니다")
            return
        }

        // 새 기록 추가 (사진 없이)
        let newRecord = MealRecord(
            date: targetDate,
            mealType: mealType,
            beforeImageData: nil,
            afterImageData: nil,
            recordedWithoutPhoto: true
        )
        currentRecords.append(newRecord)

        records = currentRecords

        // 업적 체크
        AchievementManager.shared.checkAndUnlockAchievements(mealStore: self)
    }

    // 식사 기록 삭제
    func deleteMeal(date: Date, mealType: MealType) {
        let targetDate = Calendar.current.startOfDay(for: date)

        var currentRecords = records
        let beforeCount = currentRecords.count
        currentRecords.removeAll { record in
            record.mealType == mealType && Calendar.current.isDate(record.date, inSameDayAs: targetDate)
        }
        let afterCount = currentRecords.count

        print("🗑️ [MealRecordStore] 식사 기록 삭제: \(mealType.rawValue), 날짜: \(targetDate)")
        print("🗑️ [MealRecordStore] 삭제 전: \(beforeCount)개, 삭제 후: \(afterCount)개")

        records = currentRecords
    }

    // 메모 업데이트
    func updateMemo(date: Date, mealType: MealType, memo: String?) {
        let targetDate = Calendar.current.startOfDay(for: date)

        var currentRecords = records
        if let existingIndex = currentRecords.firstIndex(where: {
            $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) {
            let existing = currentRecords[existingIndex]
            currentRecords[existingIndex] = MealRecord(
                date: existing.date,
                mealType: existing.mealType,
                beforeImageData: existing.beforeImageData,
                afterImageData: existing.afterImageData,
                memo: memo,
                recordedWithoutPhoto: existing.recordedWithoutPhoto,
                hidePhotoCountBadge: existing.hidePhotoCountBadge
            )
            records = currentRecords
        }
    }

    // 사진 개수 알림 숨기기 업데이트
    func updateHidePhotoCountBadge(date: Date, mealType: MealType, hide: Bool) {
        let targetDate = Calendar.current.startOfDay(for: date)

        var currentRecords = records
        if let existingIndex = currentRecords.firstIndex(where: {
            $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: targetDate)
        }) {
            let existing = currentRecords[existingIndex]
            currentRecords[existingIndex] = MealRecord(
                date: existing.date,
                mealType: existing.mealType,
                beforeImageData: existing.beforeImageData,
                afterImageData: existing.afterImageData,
                memo: existing.memo,
                recordedWithoutPhoto: existing.recordedWithoutPhoto,
                hidePhotoCountBadge: hide
            )
            records = currentRecords
        }
    }

    // 기록 저장 (현재 앨범 타입의 데이터만 저장)
    private func saveRecords() {
        switch SettingsManager.shared.albumType {
        case .diet:
            if let encoded = try? JSONEncoder().encode(dietRecords) {
                userDefaults.set(encoded, forKey: dietRecordsKey)
                print("💾 [MealRecordStore] 식단 기록 저장: \(dietRecords.count)개")
            }
        case .exercise:
            if let encoded = try? JSONEncoder().encode(exerciseRecords) {
                userDefaults.set(encoded, forKey: exerciseRecordsKey)
                print("💾 [MealRecordStore] 운동 기록 저장: \(exerciseRecords.count)개")
            }
        }
    }

    // 기록 불러오기 (식단과 운동 모두 로드)
    private func loadRecords() {
        // 식단 기록 로드
        if let data = userDefaults.data(forKey: dietRecordsKey),
           let decoded = try? JSONDecoder().decode([MealRecord].self, from: data) {
            dietRecords = decoded
            print("📂 [MealRecordStore] 식단 기록 로드: \(dietRecords.count)개")
        }

        // 운동 기록 로드
        if let data = userDefaults.data(forKey: exerciseRecordsKey),
           let decoded = try? JSONDecoder().decode([MealRecord].self, from: data) {
            exerciseRecords = decoded
            print("📂 [MealRecordStore] 운동 기록 로드: \(exerciseRecords.count)개")
        }
    }

    // MARK: - Streak 계산

    // 현재 연속 기록 일수 계산
    func getCurrentStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let isExerciseMode = SettingsManager.shared.albumType == .exercise

        // 오늘 기록이 완료되었는지 확인
        let todayMeals = getMeals(for: today)
        let todayComplete: Bool
        if isExerciseMode {
            todayComplete = todayMeals[.breakfast]?.isComplete ?? false
        } else {
            todayComplete = todayMeals.count == 3 && todayMeals.values.allSatisfy { $0.isComplete }
        }

        var streak = 0
        var currentDate = today

        // 오늘부터 과거로 거슬러 올라가며 연속 기록 확인
        while true {
            let meals = getMeals(for: currentDate)
            let isComplete: Bool
            if isExerciseMode {
                isComplete = meals[.breakfast]?.isComplete ?? false
            } else {
                isComplete = meals.count == 3 && meals.values.allSatisfy { $0.isComplete }
            }

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

        let isExerciseMode = SettingsManager.shared.albumType == .exercise

        // 모든 날짜별로 정렬
        let sortedDates = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted()

        guard !sortedDates.isEmpty else { return 0 }

        for (index, date) in sortedDates.enumerated() {
            let meals = getMeals(for: date)
            let isComplete: Bool
            if isExerciseMode {
                isComplete = meals[.breakfast]?.isComplete ?? false
            } else {
                isComplete = meals.count == 3 && meals.values.allSatisfy { $0.isComplete }
            }

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
        print("🎨 [MealRecordStore] 샘플 데이터 생성 시작 - \(SettingsManager.shared.albumType.rawValue) 모드")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var currentRecords = records

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
                        currentRecords.append(record)
                    }
                }
            }
        }

        records = currentRecords
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

    // 모든 데이터 삭제 (개발용 - 현재 앨범 타입의 데이터만)
    func clearAllData() {
        print("🗑️ [MealRecordStore] \(SettingsManager.shared.albumType.rawValue) 모드 데이터 삭제")
        records = []
    }

    // 총 기록 개수 (완료된 식사 개수)
    func getTotalRecordCount() -> Int {
        return records.filter { $0.isComplete }.count
    }

    // 총 사진 개수
    func getTotalPhotoCount() -> Int {
        var count = 0
        for record in records {
            if record.beforeImageData != nil {
                count += 1
            }
            if record.afterImageData != nil {
                count += 1
            }
        }
        return count
    }

    // 총 메모 개수
    func getTotalMemoCount() -> Int {
        return records.filter { $0.memo != nil && !$0.memo!.isEmpty }.count
    }
}

// Array extension for safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
