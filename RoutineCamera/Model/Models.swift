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
    case snack1 = "간식1"
    case snack2 = "간식2"
    case snack3 = "간식3"

    var id: String { self.rawValue }

    var symbolName: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack1, .snack2, .snack3: return "cup.and.saucer.fill"
        }
    }

    var symbolColor: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .dinner: return .blue
        case .snack1: return .green
        case .snack2: return .pink
        case .snack3: return .purple
        }
    }

    // 간식 타입인지 확인
    var isSnack: Bool {
        switch self {
        case .snack1, .snack2, .snack3:
            return true
        default:
            return false
        }
    }
}

// Vision 분석 결과 저장용 모델
struct VisionAnalysisData: Codable {
    let foodItems: [String]
    let extractedText: [String]
    let confidence: Float
    let analyzedDate: Date
    let isOpenAI: Bool // OpenAI로 분석했는지 여부
    let description: String? // OpenAI의 상세 설명

    init(foodItems: [String], extractedText: [String], confidence: Float, analyzedDate: Date, isOpenAI: Bool = false, description: String? = nil) {
        self.foodItems = foodItems
        self.extractedText = extractedText
        self.confidence = confidence
        self.analyzedDate = analyzedDate
        self.isOpenAI = isOpenAI
        self.description = description
    }

    // 기존 데이터 호환성을 위한 커스텀 디코딩
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        foodItems = try container.decode([String].self, forKey: .foodItems)
        extractedText = try container.decode([String].self, forKey: .extractedText)
        confidence = try container.decode(Float.self, forKey: .confidence)
        analyzedDate = try container.decode(Date.self, forKey: .analyzedDate)
        isOpenAI = try container.decodeIfPresent(Bool.self, forKey: .isOpenAI) ?? false
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }

    var summary: String {
        var result = ""

        if !foodItems.isEmpty {
            result += "🍽️ 음식: \(foodItems.joined(separator: ", "))\n"
        }

        if let desc = description, !desc.isEmpty {
            result += "💬 \(desc)\n"
        }

        if !extractedText.isEmpty {
            result += "📝 텍스트: \(extractedText.joined(separator: " "))"
        }

        return result.isEmpty ? "분석 결과 없음" : result
    }
}

// 피드백 모델 (받은 피드백)
struct MealFeedback: Identifiable, Codable {
    let id: String // 고유 ID (CloudKit 레코드 이름)
    let authorId: String // 작성자 UID
    let authorNickname: String // 작성자 닉네임
    let content: String // 피드백 내용
    let createdAt: Date // 작성 시간
    var isRead: Bool // 읽음 여부 (수신자가 읽었는지)

    enum CodingKeys: String, CodingKey {
        case id
        case authorId
        case authorNickname
        case content
        case createdAt
        case isRead
    }

    init(id: String = UUID().uuidString, authorId: String, authorNickname: String, content: String, createdAt: Date = Date(), isRead: Bool = false) {
        self.id = id
        self.authorId = authorId
        self.authorNickname = authorNickname
        self.content = content
        self.createdAt = createdAt
        self.isRead = isRead
    }

    // 기존 데이터 호환성을 위한 커스텀 디코딩
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        authorId = try container.decode(String.self, forKey: .authorId)
        authorNickname = try container.decode(String.self, forKey: .authorNickname)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
    }
}

// 보낸 피드백 모델
struct SentFeedback: Identifiable, Codable {
    let id: String
    let recipientId: String // 받는 사람 UID
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case recipientId
        case content
        case createdAt
    }

    init(id: String = UUID().uuidString, recipientId: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.recipientId = recipientId
        self.content = content
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        recipientId = try container.decode(String.self, forKey: .recipientId)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
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
    var visionAnalysis: VisionAnalysisData?  // Vision Framework 분석 결과

    init(date: Date, mealType: MealType, beforeImageData: Data? = nil, afterImageData: Data? = nil, memo: String? = nil, recordedWithoutPhoto: Bool = false, hidePhotoCountBadge: Bool = false, visionAnalysis: VisionAnalysisData? = nil) {
        self.id = UUID()
        self.date = date
        self.mealType = mealType
        self.beforeImageData = beforeImageData
        self.afterImageData = afterImageData
        self.memo = memo
        self.recordedWithoutPhoto = recordedWithoutPhoto
        self.hidePhotoCountBadge = hidePhotoCountBadge
        self.visionAnalysis = visionAnalysis
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
        // 기존 데이터에는 visionAnalysis가 없을 수 있으므로 기본값 nil 사용
        visionAnalysis = try container.decodeIfPresent(VisionAnalysisData.self, forKey: .visionAnalysis)
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
    // 싱글톤 인스턴스
    static let shared = MealRecordStore()

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

    // 실패(거른 끼니) 판정의 기준 시작일
    // = 첫 실행일과 가장 오래된 기록일 중 이른 쪽
    // 이 날짜 이전의 과거는 "설치 전"이므로 실패로 판정하지 않는다.
    var startDate: Date {
        let calendar = Calendar.current
        let launchDay = calendar.startOfDay(for: SettingsManager.shared.appStartDate)
        if let earliestRecord = records.map({ calendar.startOfDay(for: $0.date) }).min() {
            return min(launchDay, earliestRecord)
        }
        return launchDay
    }

    // CloudKit 업로드 추적
    private var dirtyDates: Set<String> = []  // 업로드 필요한 날짜들
    private var lastUploadTime: Date?
    private var uploadTimer: Timer?
    private let uploadDelaySeconds: TimeInterval = 5  // 5초 후 업로드

    init() {
        loadRecords()
        migrateOldDataIfNeeded()

        // SettingsManager의 albumType 변경 감지
        SettingsManager.shared.$albumType
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 앱 백그라운드 진입 시 대기 중인 업로드 즉시 실행
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.uploadTimer?.invalidate()
            self?.uploadDirtyDates()
        }
    }

    deinit {
        uploadTimer?.invalidate()
        // 앱 종료 시 대기 중인 업로드 실행
        if !dirtyDates.isEmpty {
            print("⚠️ [CloudKit] 앱 종료 - 남은 업로드 실행")
        }
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
                    memo: existing.memo,
                    recordedWithoutPhoto: false,
                    hidePhotoCountBadge: existing.hidePhotoCountBadge,
                    visionAnalysis: existing.visionAnalysis
                )
            } else {
                currentRecords[existingIndex] = MealRecord(
                    date: targetDate,
                    mealType: mealType,
                    beforeImageData: existing.beforeImageData,
                    afterImageData: imageData,
                    memo: existing.memo,
                    recordedWithoutPhoto: false,
                    hidePhotoCountBadge: existing.hidePhotoCountBadge,
                    visionAnalysis: existing.visionAnalysis
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
                hidePhotoCountBadge: existing.hidePhotoCountBadge,
                visionAnalysis: existing.visionAnalysis
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
                hidePhotoCountBadge: hide,
                visionAnalysis: existing.visionAnalysis
            )
            records = currentRecords
        }
    }

    // Vision 분석 결과 업데이트
    func updateVisionAnalysis(date: Date, mealType: MealType, analysis: VisionAnalysisData?) {
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
                hidePhotoCountBadge: existing.hidePhotoCountBadge,
                visionAnalysis: analysis
            )
            records = currentRecords
        }
    }

    // 기록 저장 (현재 앨범 타입의 데이터만 저장)
    private func saveRecords() {
        print("🔔 [MealRecordStore] saveRecords() 호출됨")
        print("   - 현재 앨범 타입: \(SettingsManager.shared.albumType)")

        switch SettingsManager.shared.albumType {
        case .diet:
            print("   - 식단 모드로 저장 시작")
            if let encoded = try? JSONEncoder().encode(dietRecords) {
                userDefaults.set(encoded, forKey: dietRecordsKey)
                print("💾 [MealRecordStore] 식단 기록 저장: \(dietRecords.count)개")

                // CloudKit 동기화 (식단 공유가 활성화된 경우)
                if !FriendManager.shared.isSignedIn {
                    print("⚠️ [CloudKit] iCloud 미로그인이라 업로드 건너뜀")
                } else if SettingsManager.shared.shareMealsToCloud {
                    // 변경된 날짜들을 dirty로 표시하고 지연 업로드 스케줄
                    markDirtyDatesFromRecords()
                    scheduleDelayedUpload()
                } else {
                    print("⚠️ [CloudKit] 식단 공유 비활성화됨 - 설정에서 활성화 필요")
                }
            }
        case .exercise:
            if let encoded = try? JSONEncoder().encode(exerciseRecords) {
                userDefaults.set(encoded, forKey: exerciseRecordsKey)
                print("💾 [MealRecordStore] 운동 기록 저장: \(exerciseRecords.count)개")
            }
        }
    }

    // MARK: - 스마트 CloudKit 업로드

    /// 현재 식단 기록에서 변경된 날짜를 dirty로 표시
    private func markDirtyDatesFromRecords() {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // 최근 3일간의 날짜를 dirty로 표시
        for dayOffset in 0..<3 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let dateString = dateFormatter.string(from: date)
                if !getMeals(for: date).isEmpty {
                    dirtyDates.insert(dateString)
                }
            }
        }

        if !dirtyDates.isEmpty {
            print("📝 [CloudKit] 업로드 대기 날짜: \(dirtyDates.sorted())")
        }
    }

    /// 지연된 업로드 스케줄 (여러 저장이 연속으로 일어날 때 배치 처리)
    private func scheduleDelayedUpload() {
        // 기존 타이머 취소
        uploadTimer?.invalidate()

        // 새 타이머 설정 (5초 후 업로드)
        uploadTimer = Timer.scheduledTimer(withTimeInterval: uploadDelaySeconds, repeats: false) { [weak self] _ in
            self?.uploadDirtyDates()
        }

        print("⏰ [CloudKit] \(Int(uploadDelaySeconds))초 후 업로드 예정")
    }

    /// dirty로 표시된 날짜만 업로드
    private func uploadDirtyDates() {
        guard !dirtyDates.isEmpty else {
            print("ℹ️ [CloudKit] 업로드할 날짜 없음")
            return
        }

        print("🚀 [CloudKit] 스마트 업로드 시작 - \(dirtyDates.count)개 날짜")

        let datesToUpload = dirtyDates
        dirtyDates.removeAll()  // 먼저 클리어 (중복 방지)

        _Concurrency.Task {
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"

            for dateString in datesToUpload.sorted() {
                // 날짜 문자열을 Date로 변환
                guard let date = dateFormatter.date(from: dateString) else { continue }

                let meals = getMeals(for: date)
                print("   📅 \(dateString) - 식단 개수: \(meals.count)")

                if meals.isEmpty {
                    print("   ⏭️ 식단 없음, 건너뜀")
                    continue
                }

                // dirty로 표시된 날짜는 무조건 업로드 (중복 방지는 dirty 클리어로 처리)
                do {
                    try await FriendManager.shared.uploadMyMeals(date: date, meals: meals)
                    print("   ✅ \(dateString) 업로드 완료 (\(meals.count)개 식단)")
                } catch {
                    print("   ❌ \(dateString) 업로드 실패: \(error)")
                }
            }

            await MainActor.run {
                self.lastUploadTime = Date()
                print("🏁 [CloudKit] 스마트 업로드 완료")
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

    // 특정 날짜가 "완전히 기록된 날"인지 (주요 3끼 모두 — '완벽한 날' 개념)
    func isDayComplete(_ date: Date) -> Bool {
        let meals = getMeals(for: date)
        if SettingsManager.shared.albumType == .exercise {
            return meals[.breakfast]?.isComplete ?? false
        } else {
            // 간식 제외 주요 3끼 모두 완료
            let mainMeals = meals.filter { !$0.key.isSnack }
            return mainMeals.count == 3 && mainMeals.values.allSatisfy { $0.isComplete }
        }
    }

    // 하루가 "연속 기록에 포함되는 날"인지 (완벽주의/올오어낫씽 완화)
    // 3끼를 다 채워야 인정하던 기준을 "최소 한 끼라도 남기면 이어진 것"으로 바꾼다.
    // → 두 끼만 찍은 날에도 연속이 끊기지 않아 '완벽하지 못하면 안 하느니만' 심리를 줄인다.
    func isDayRecorded(_ date: Date) -> Bool {
        let meals = getMeals(for: date)
        if SettingsManager.shared.albumType == .exercise {
            return meals[.breakfast]?.isComplete ?? false
        }
        // 간식 포함 어떤 끼니든 하나라도 완료되면 기록된 날로 인정
        return meals.values.contains { $0.isComplete }
    }

    func getCurrentStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // 완화된 기준(isDayRecorded)으로 연속을 계산 — 한 끼라도 남기면 이어진다
        let todayRecorded = isDayRecorded(today)

        var streak = 0
        var currentDate = today

        // 오늘부터 과거로 거슬러 올라가며 연속 기록 확인
        while true {
            if isDayRecorded(currentDate) {
                streak += 1
                guard let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) else {
                    break
                }
                currentDate = previousDay
            } else {
                // 오늘이 아직 미기록이면 '진행 중'이므로 끊긴 게 아님 — 어제부터 확인
                if calendar.isDate(currentDate, inSameDayAs: today) && !todayRecorded {
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

    // 최고 연속 기록 일수 (완화된 기준 — 업적 판정 등에 사용)
    func getMaxStreak() -> Int {
        let calendar = Calendar.current
        var maxStreak = 0
        var currentStreak = 0

        // 모든 날짜별로 정렬
        let sortedDates = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted()

        guard !sortedDates.isEmpty else { return 0 }

        for (index, date) in sortedDates.enumerated() {
            if isDayRecorded(date) {
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

    // 지금까지 기록한 날 수 (한 번 올라가면 절대 줄지 않는 누적 카운터)
    // 연속이 끊겨도 사라지지 않아 '나쁜 날'에 대한 자책을 만들지 않는다.
    func getTotalRecordedDays() -> Int {
        let calendar = Calendar.current
        let days = Set(records.filter { $0.isComplete }.map { calendar.startOfDay(for: $0.date) })
        return days.count
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
            case .snack1:
                backgroundColor = isBefore ? UIColor.green.withAlphaComponent(0.3) : UIColor.green.withAlphaComponent(0.6)
            case .snack2:
                backgroundColor = isBefore ? UIColor.systemPink.withAlphaComponent(0.3) : UIColor.systemPink.withAlphaComponent(0.6)
            case .snack3:
                backgroundColor = isBefore ? UIColor.purple.withAlphaComponent(0.3) : UIColor.purple.withAlphaComponent(0.6)
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
