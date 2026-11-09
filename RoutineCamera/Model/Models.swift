//
//  Models.swift
//  RoutineCamera
//
//  Created by hyunho lee on 11/11/25.
//

import Foundation
import SwiftUI
import Combine
import WidgetKit
import RoutineCameraCore
import os

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

// 날짜별 식사 기록을 관리하는 ObservableObject
@MainActor
class MealRecordStore: ObservableObject {
    // 싱글톤 인스턴스
    static let shared = MealRecordStore()

    // 식단과 운동을 완전히 별개로 저장
    @Published private var dietRecords: [MealRecord] = [] {
        didSet { dietByDay = Self.indexByDay(dietRecords); feedCache[.diet] = nil; dietRevision &+= 1 }
    }
    @Published private var exerciseRecords: [MealRecord] = [] {
        didSet { exerciseByDay = Self.indexByDay(exerciseRecords); feedCache[.exercise] = nil }
    }

    /// 식단 기록이 바뀔 때마다 하나씩 오른다 — 바뀌지 않았으면 다시 할 필요 없는 일(Spotlight 색인 등)을 건너뛰는 표시
    private(set) var dietRevision = 0

    /// 피드(순간 컬렉션)용 — 남긴 기록을 날짜별로, 최신 날 먼저 · 날 안에서도 최신순.
    /// 피드는 1분마다 · 설정이 바뀔 때마다 다시 그려지는데, 그때마다 전체를 정렬하지 않게 기록이 바뀔 때만 만든다.
    private var feedCache: [AlbumType: [(day: Date, records: [MealRecord])]] = [:]

    var feedDays: [(day: Date, records: [MealRecord])] {
        let album = SettingsManager.shared.albumType
        if let cached = feedCache[album] { return cached }
        let calendar = Calendar.current
        let built = Dictionary(grouping: records.filter(\.isComplete)) { calendar.startOfDay(for: $0.feedDate) }
            .map { (day: $0.key, records: $0.value.sorted { $0.feedDate > $1.feedDate }) }
            .sorted { $0.day > $1.day }
        feedCache[album] = built
        return built
    }

    /// 날짜(그날 0시) → 끼니 → 기록. 화면과 연속 기록 계산이 날마다 전체 기록을 훑지 않게 한다.
    /// 기록이 바뀔 때만 다시 만든다.
    private var dietByDay: [Date: [MealType: MealRecord]] = [:]
    private var exerciseByDay: [Date: [MealType: MealRecord]] = [:]

    /// 같은 날 같은 끼니가 둘이면 뒤의 것이 이긴다 (예전 getMeals 와 같다)
    private static func indexByDay(_ records: [MealRecord]) -> [Date: [MealType: MealRecord]] {
        let calendar = Calendar.current
        var index: [Date: [MealType: MealRecord]] = [:]
        for record in records {
            index[calendar.startOfDay(for: record.date), default: [:]][record.mealType] = record
        }
        return index
    }

    /// 시간대가 바뀌면 "그날" 의 경계가 바뀐다
    private func rebuildDayIndex() {
        dietByDay = Self.indexByDay(dietRecords)
        exerciseByDay = Self.indexByDay(exerciseRecords)
        feedCache.removeAll()
        objectWillChange.send()
    }

    /// 식단 앨범 기록 — 보고 있는 앨범과 상관없이 읽는다 (Siri · Spotlight 색인용)
    var dietMeals: [MealRecord] { dietRecords }

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

    // 위젯과 공유하기 위해 App Group 저장소 사용 (미등록 시 표준으로 폴백)
    private let userDefaults = AppGroup.defaults
    private let dietRecordsKey = AppGroup.dietRecordsKey
    private let exerciseRecordsKey = AppGroup.exerciseRecordsKey
    private var cancellables = Set<AnyCancellable>()

    // 실패(거른 끼니) 판정의 기준 시작일
    // = 첫 실행일과 가장 오래된 기록일 중 이른 쪽
    // 이 날짜 이전의 과거는 "설치 전"이므로 실패로 판정하지 않는다.
    var startDate: Date {
        let calendar = Calendar.current
        let launchDay = calendar.startOfDay(for: SettingsManager.shared.appStartDate)
        // 날짜 목록에서 고른다 — 격자 칸마다 여러 번 불려, 기록 전체를 훑으면 스크롤이 버벅인다
        let byDay = SettingsManager.shared.albumType == .diet ? dietByDay : exerciseByDay
        if let earliestRecord = byDay.keys.min() {
            return min(launchDay, earliestRecord)
        }
        return launchDay
    }

    // CloudKit 업로드 추적
    // 업로드 필요한 날짜들 — 기기에 남겨 둔다 (5초 안에 앱을 닫거나 업로드가 실패해도 다음에 다시 올린다)
    private var dirtyDates: Set<String> = [] {
        didSet { userDefaults.set(Array(dirtyDates), forKey: dirtyDatesKey) }
    }
    private let dirtyDatesKey = "pendingUploadDates_v1"
    /// 날짜별 기록 지문. 실제로 바뀐 날짜만 업로드하기 위한 기준값
    private var dateFingerprints: [String: Int] = [:]
    // v2: 지문을 StableHasher 로 만든다. v1 은 실행마다 시드가 바뀌는 Hasher 라 저장값과 맞은 적이 없어,
    // 앱을 켠 뒤 처음 저장할 때마다 기록이 있는 모든 날짜가 다시 올라갔다. 키를 바꿔 기준값을 새로 잡는다.
    private let fingerprintsKey = "dietDateFingerprints_v2"
    private let fingerprintBaselineKey = "dietFingerprintBaseline_v2"
    // 운동은 지문을 따로 둔다. 기존 식단 해시에 운동을 섞으면 모든 날짜가 "바뀐 것"으로 잡혀
    // 1.0.8 첫 실행에 전체 이력이 한꺼번에 재업로드된다.
    private var exerciseDateFingerprints: [String: Int] = [:]
    private let exerciseFingerprintsKey = "exerciseDateFingerprints_v2"
    private let exerciseFingerprintBaselineKey = "exerciseFingerprintBaseline_v2"
    private var lastUploadTime: Date?
    private var uploadTimer: Timer?
    private let uploadDelaySeconds: TimeInterval = 5  // 5초 후 업로드

    init() {
        migrateToAppGroupIfNeeded()
        loadRecords()
        // 어느 기록도 가리키지 않는 도장 원본 띠 정리 (메인 밖)
        MealStampBackingStore.shared.prune(keeping: Set((dietRecords + exerciseRecords).map(\.id)))
        movePhotosOutOfDefaultsIfNeeded()
        removeStaleStandardCopiesIfNeeded()
        establishFingerprintBaselineIfNeeded()
        dirtyDates = Set(userDefaults.stringArray(forKey: dirtyDatesKey) ?? [])
        drainPendingAteAll()

        // SettingsManager의 albumType 변경 감지
        SettingsManager.shared.$albumType
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildDayIndex() }
        }

        // 앱이 다시 활성화될 때, 위젯/알림에서 앱 없이 쌓인 "다 먹음" 대기열 반영
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.drainPendingAteAll()
                // 지난번에 못 올린 날짜가 있으면 다시 올린다
                if self?.dirtyDates.isEmpty == false { self?.scheduleDelayedUpload() }
            }
        }

        // 앱 백그라운드 진입 시 대기 중인 업로드 즉시 실행
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.uploadTimer?.invalidate()
                self?.uploadDirtyDates()
            }
        }

        // 기록 쓰기는 메인 밖에서 한다. 앱이 멈추거나 종료되기 전에 밀린 쓰기를 마친다.
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finishPendingWrites() }
            }
        }
    }

    deinit {
        uploadTimer?.invalidate()
    }

    // 표준 UserDefaults → App Group 공유 저장소로 1회 이관 (위젯 공유 전환 시 데이터 보존)
    private func migrateToAppGroupIfNeeded() {
        let flagKey = "migratedToAppGroup_v1"
        // 공유 suite가 표준과 동일(폴백)하면 이관 불필요
        guard userDefaults != UserDefaults.standard else { return }
        guard !userDefaults.bool(forKey: flagKey) else { return }

        let std = UserDefaults.standard
        if userDefaults.object(forKey: dietRecordsKey) == nil,
           let data = std.data(forKey: dietRecordsKey) {
            userDefaults.set(data, forKey: dietRecordsKey)
            Log.store.info("식단 기록 이관 완료")
        }
        if userDefaults.object(forKey: exerciseRecordsKey) == nil,
           let data = std.data(forKey: exerciseRecordsKey) {
            userDefaults.set(data, forKey: exerciseRecordsKey)
            Log.store.info("운동 기록 이관 완료")
        }
        userDefaults.set(true, forKey: flagKey)
    }

    // 특정 날짜의 식사 기록들 가져오기
    func getMeals(for date: Date) -> [MealType: MealRecord] {
        SettingsManager.shared.albumType == .diet ? dietMeals(for: date) : exerciseMeals(for: date)
    }

    // 지금 새로 기록할 칸. 시간대 끼니가 오늘 이미 기록돼 있으면 덮어쓰지 않고 빈 간식 칸으로 보낸다.
    // (점심을 찍은 뒤 오후에 간식을 찍으면 점심 사진이 간식으로 교체되던 문제)
    func recordableMealType(at now: Date = Date()) -> MealType {
        let cal = Calendar.current
        let inferred = MealType.inferred(at: now)
        let taken = Set(
            records
                .filter { $0.isComplete && cal.isDate($0.date, inSameDayAs: now) }
                .map(\.mealType)
        )
        if !inferred.isSnack && !taken.contains(inferred) { return inferred }

        // 시간대에 맞는 간식 칸을 먼저, 차 있으면 남은 간식 칸
        let hour = cal.component(.hour, from: now)
        let preferred: MealType = hour < 11 ? .snack1 : (hour < 16 ? .snack2 : .snack3)
        let candidates = [preferred] + [MealType.snack1, .snack2, .snack3].filter { $0 != preferred }
        // 전부 차 있으면 끼니 사진 대신 간식 칸을 덮어쓴다
        return candidates.first { !taken.contains($0) } ?? preferred
    }

    // MARK: - 한 끼 고치기

    /// 그날 그 끼니의 기록을 그 자리에서 고친다 (id 는 그대로). 기록이 없으면 false.
    /// 예전에는 고칠 때마다 열한 칸을 다시 적어 새 기록을 만들었다 — 칸을 빠뜨리면 그 값이 조용히 사라졌다.
    @discardableResult
    private func mutateMeal(date: Date, mealType: MealType, _ change: (inout MealRecord) -> Void) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        var current = records
        guard let index = current.firstIndex(where: {
            $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: day)
        }) else { return false }
        change(&current[index])
        records = current
        return true
    }

    private func meal(on date: Date, _ mealType: MealType) -> MealRecord? {
        let day = Calendar.current.startOfDay(for: date)
        return records.first { $0.mealType == mealType && Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    // 식사 기록 추가 또는 업데이트 (식전/식후 지정)
    // capturedAt: 새 기록일 때 "먹은 시각" (기록 화면에서 고른 값). 기존 기록에 사진을 더할 때는 원래 시각을 유지한다.
    // stampBacking: 카메라로 찍어 날짜 도장을 새긴 사진이면 도장 아래 원본 띠 (나중에 날짜 · 글꼴을 바꿔 다시 새길 때 쓴다).
    //   앨범에서 고른 사진처럼 띠가 없으면 nil — 이때 옛 띠가 남아 있으면 지운다 (다른 사진의 띠를 붙이면 안 되므로).
    func addOrUpdateMeal(date: Date, mealType: MealType, imageData: Data, isBefore: Bool, capturedAt: Date = Date(),
                         place: MealPlace? = nil, stampBacking: Data? = nil) {
        let updated = mutateMeal(date: date, mealType: mealType) { record in
            if isBefore { record.beforeImageData = imageData } else { record.afterImageData = imageData }
            record.recordedWithoutPhoto = false
            record.capturedAt = record.capturedAt ?? Date()
            record.place = record.place ?? place
        }
        if !updated {
            records.append(MealRecord(date: Calendar.current.startOfDay(for: date), mealType: mealType,
                                      beforeImageData: isBefore ? imageData : nil,
                                      afterImageData: isBefore ? nil : imageData,
                                      capturedAt: capturedAt, place: place))
        }
        if let saved = meal(on: date, mealType) {
            MealStampBackingStore.shared.save(stampBacking, for: saved.id, kind: isBefore ? "before" : "after")
        }
        AchievementManager.shared.checkAndUnlockAchievements(mealStore: self)
    }

    // MARK: - 날짜 · 시각 바꾸기

    enum RescheduleResult: Equatable {
        /// 옮겼다. 끼니가 바뀌었을 수 있다 (간식이 그날 빈 간식 칸으로)
        case moved(day: Date, mealType: MealType)
        /// 그날 같은 끼니 기록이 이미 있어 옮기지 않았다
        case slotTaken
        case notFound
    }

    /// 이 사진을 새 날짜로 다시 새길 수 있는지 — 카메라로 찍어 도장 아래 원본 띠가 남아 있을 때만
    func canRestampPhoto(_ record: MealRecord, isBefore: Bool) -> Bool {
        let data = isBefore ? record.beforeImageData : record.afterImageData
        return data != nil && MealStampBackingStore.shared.exists(for: record.id, kind: isBefore ? "before" : "after")
    }

    /// 기록의 날짜와 "먹은 시각" 을 바꾼다 (사용자 피드백: 기록 날짜 · 시간 편집, 2026-11-09).
    /// 다른 날로 옮길 때 그날 같은 끼니가 이미 있으면 옮기지 않는다 (간식은 빈 간식 칸으로 옮긴다).
    /// restampStyle 을 주면 다시 새길 수 있는 사진의 날짜 도장을 새 시각 · 그 모양으로 다시 새긴다 (nil 이면 사진은 그대로).
    /// 사진 두 장을 다시 그리는 동안 화면이 멈추지 않도록 그리기는 메인 밖에서 한다.
    func rescheduleMeal(date: Date, mealType: MealType, to newCapturedAt: Date, restampStyle: MealStampStyle?) async -> RescheduleResult {
        let calendar = Calendar.current
        guard let original = meal(on: date, mealType) else { return .notFound }
        let newDay = calendar.startOfDay(for: newCapturedAt)
        let dayChanged = !calendar.isDate(original.date, inSameDayAs: newDay)

        var targetType = mealType
        if dayChanged {
            let taken = Set(records.filter { calendar.isDate($0.date, inSameDayAs: newDay) && $0.isComplete && $0.id != original.id }
                .map(\.mealType))
            if taken.contains(mealType) {
                guard mealType.isSnack,
                      let free = [MealType.snack1, .snack2, .snack3].first(where: { !taken.contains($0) }) else { return .slotTaken }
                targetType = free
            }
        }

        // 다시 새기기 (메인 밖) — 띠가 없는 사진(예전 버전 · 앨범 사진)은 그대로 둔다
        var before = original.beforeImageData
        var after = original.afterImageData
        if let style = restampStyle {
            let id = original.id
            let backingBefore = MealStampBackingStore.shared.load(for: id, kind: "before")
            let backingAfter = MealStampBackingStore.shared.load(for: id, kind: "after")
            let (b, a) = (before, after)
            let restamped = await Task.detached(priority: .userInitiated) { () -> (Data?, Data?) in
                func redo(_ photo: Data?, _ backing: Data?) -> Data? {
                    guard let photo, let backing else { return nil }
                    return MealPhotoStamp.restamp(stamped: photo, backing: backing, date: newCapturedAt, style: style)
                }
                return (redo(b, backingBefore), redo(a, backingAfter))
            }.value
            before = restamped.0 ?? before
            after = restamped.1 ?? after
        }

        // 기다리는 사이 기록이 바뀌었을 수 있다 — 다시 찾아서 그 위에 쓴다
        var current = records
        guard let index = current.firstIndex(where: { $0.id == original.id }) else { return .notFound }
        let latest = current[index]
        let moved = MealRecord(id: latest.id, date: newDay, mealType: targetType,
                               beforeImageData: before, afterImageData: after,
                               memo: latest.memo, recordedWithoutPhoto: latest.recordedWithoutPhoto,
                               hidePhotoCountBadge: latest.hidePhotoCountBadge, visionAnalysis: latest.visionAnalysis,
                               capturedAt: newCapturedAt, ateAll: latest.ateAll, place: latest.place, portion: latest.portion)
        current[index] = moved
        if dayChanged {
            // 옮겨 간 자리에 비어 있는(완료되지 않은) 기록이 있으면 둘이 겹치지 않게 치운다
            current.removeAll { $0.id != moved.id && $0.mealType == targetType && calendar.isDate($0.date, inSameDayAs: newDay) && !$0.isComplete }
            NotificationManager.shared.cancelAteAllReminder(date: original.date, mealType: mealType)
        }
        records = current
        Log.store.info("기록 날짜 · 시각 변경: \(mealType.rawValue, privacy: .public) → \(DayKey.string(from: newDay), privacy: .public) \(targetType.rawValue, privacy: .public)")
        return .moved(day: newDay, mealType: targetType)
    }

    // 사진 없이 기록 (이미 기록이 있으면 그대로 둔다)
    func recordWithoutPhoto(date: Date, mealType: MealType, capturedAt: Date = Date()) {
        guard meal(on: date, mealType) == nil else { return }
        records.append(MealRecord(date: Calendar.current.startOfDay(for: date), mealType: mealType,
                                  recordedWithoutPhoto: true, capturedAt: capturedAt))
        AchievementManager.shared.checkAndUnlockAchievements(mealStore: self)
    }

    // "다 먹음" 기록 — 식전만 찍은 기록에 다먹음 신호를 붙이거나, 없으면 사진 없이 다먹음 기록 생성.
    // 위젯/액션버튼/알림에서 앱 안 열고 호출되는 진입점.
    func recordAteAll(date: Date, mealType: MealType) {
        let updated = mutateMeal(date: date, mealType: mealType) { record in
            record.capturedAt = record.capturedAt ?? Date()
            record.ateAll = true
        }
        if !updated {
            records.append(MealRecord(date: Calendar.current.startOfDay(for: date), mealType: mealType,
                                      capturedAt: Date(), ateAll: true))
        }
        AchievementManager.shared.checkAndUnlockAchievements(mealStore: self)
    }

    // 가장 최근의 "먹는 중"(오늘 식전만 있는) 기록을 찾아 반환 (다먹음 신호를 붙일 대상 추정용).
    // 날이 지난 미마감 기록은 "기록 필요" 상태이므로 원탭 다먹음의 대상이 아니다.
    func latestEatingInProgress() -> MealRecord? {
        return records.filter { $0.isEatingInProgressToday }.max(by: { $0.sortDate < $1.sortDate })
    }

    // 위젯/알림에서 앱 없이 쌓아둔 "다 먹음" 대기열을 실제 기록으로 반영
    func drainPendingAteAll() {
        guard let data = userDefaults.data(forKey: AppGroup.pendingAteAllKey),
              let items = try? JSONDecoder().decode([PendingAteAll].self, from: data),
              !items.isEmpty else { return }

        // 대기열은 항상 식단 기록으로 반영 (위젯은 식단 전용)
        inDietAlbum {
            for item in items {
                guard let mealType = MealType(rawValue: item.mealType) else { continue }
                recordAteAll(date: Date(timeIntervalSince1970: item.date), mealType: mealType)
            }
        }
        userDefaults.removeObject(forKey: AppGroup.pendingAteAllKey)
        Log.store.info("대기 중 '다 먹음' \(items.count)건 반영")
    }

    /// 알림·위젯의 '다 먹음'은 식단 기록이다 — 앱이 운동 앨범을 보고 있어도 식단에 남긴다
    func inDietAlbum(_ body: () -> Void) {
        let previousAlbum = SettingsManager.shared.albumType
        if previousAlbum != .diet { SettingsManager.shared.albumType = .diet }
        body()
        if previousAlbum != .diet { SettingsManager.shared.albumType = previousAlbum }
    }

    // 식사 기록 삭제
    func deleteMeal(date: Date, mealType: MealType) {
        let targetDate = Calendar.current.startOfDay(for: date)

        var currentRecords = records
        let beforeCount = currentRecords.count
        var removedIDs: [UUID] = []
        currentRecords.removeAll { record in
            let remove = record.mealType == mealType && Calendar.current.isDate(record.date, inSameDayAs: targetDate)
            if remove { removedIDs.append(record.id) }
            return remove
        }
        let afterCount = currentRecords.count
        for id in removedIDs { MealStampBackingStore.shared.remove(for: id) }

        Log.store.info("기록 삭제: \(mealType.rawValue, privacy: .public) \(beforeCount)개 → \(afterCount)개")

        records = currentRecords
        // 지운 식사에 "다 드셨어요?" 알림이 남아 있으면, 울려서 '다 먹음'을 누를 때 지운 기록이 되살아난다
        NotificationManager.shared.cancelAteAllReminder(date: targetDate, mealType: mealType)
    }

    // 메모 업데이트
    func updateMemo(date: Date, mealType: MealType, memo: String?) {
        mutateMeal(date: date, mealType: mealType) { $0.memo = memo }
    }

    // 사진 개수 알림 숨기기 업데이트
    func updateHidePhotoCountBadge(date: Date, mealType: MealType, hide: Bool) {
        mutateMeal(date: date, mealType: mealType) { $0.hidePhotoCountBadge = hide }
    }

    // 얼마나 먹었는지 (다시 누르면 지운다)
    func updatePortion(date: Date, mealType: MealType, portion: MealPortion?) {
        guard let existing = meal(on: date, mealType), existing.portion != portion else { return }
        mutateMeal(date: date, mealType: mealType) { $0.portion = portion }
    }

    // 찍은 곳 업데이트 (nil 이면 지운다). 같으면 저장하지 않는다
    func updatePlace(date: Date, mealType: MealType, place: MealPlace?) {
        guard let existing = meal(on: date, mealType), existing.place != place else { return }
        mutateMeal(date: date, mealType: mealType) { $0.place = place }
    }

    // Vision 분석 결과 업데이트
    func updateVisionAnalysis(date: Date, mealType: MealType, analysis: VisionAnalysisData?) {
        mutateMeal(date: date, mealType: mealType) { $0.visionAnalysis = analysis }
    }

    // 기록 저장 (현재 앨범 타입의 데이터만 저장)
    private func saveRecords() {
        persist(SettingsManager.shared.albumType)

        // 친구 공유: 바뀐 날짜를 표시해 두고 잠시 뒤 올린다. 1.0.8부터 운동도 공유된다 (친구 화면의 "운동" 탭)
        if FriendManager.shared.isSignedIn && SettingsManager.shared.shareMealsToCloud {
            markDirtyDatesFromRecords()
            scheduleDelayedUpload()
        }

        // 위젯(홈/잠금화면)이 읽는 경량 스냅샷은 앨범 모드와 무관하게 식단 기준으로 항상 갱신
        publishWidgetSnapshot()

        // 오늘 기록한 끼니는 오늘 식사 전 알림에서 빼고, 지운 끼니는 되살린다 (내일부터 알림은 그대로)
        let completedToday = Set(dietMeals(for: Date()).filter { $0.value.isComplete }.keys)
        NotificationManager.shared.scheduleMealNotifications(recordedToday: completedToday)

        // 내 iCloud 백업 (친구 공유와 별개, 공유를 꺼도 동작한다)
        MealCloudSync.shared.localRecordsChanged()
    }

    // MARK: - iCloud 백업 · 동기화

    var canTrustLoadedRecordsForSync: Bool { albumsFailedToLoad.isEmpty }

    var allRecordsForSync: [(AlbumType, MealRecord)] {
        dietRecords.map { (AlbumType.diet, $0) } + exerciseRecords.map { (AlbumType.exercise, $0) }
    }

    /// 파일을 못 읽어 비어 보일 뿐인 사진인지 (지운 사진과 구분한다)
    func isPhotoUnreadableForSync(_ record: MealRecord, album: AlbumType, kind: String) -> Bool {
        unreadableImageFiles["\(album.rawValue)/\(imageSlotName(for: record, kind: kind))"] != nil
    }

    /// 다른 기기 · iCloud 에서 받은 변경을 반영한다. saveRecords 를 거치지 않아 다시 올라가지 않는다.
    func applySyncChanges(saves: [(slot: MealSyncSlot, record: MealRecord)], deletes: [MealSyncSlot]) {
        var replaced = Set(deletes)
        replaced.formUnion(saves.map(\.slot))
        let changedDays = Set(replaced.map(\.day))

        var diet = dietRecords.filter { !replaced.contains(MealSyncSlot(album: .diet, record: $0)) }
        var exercise = exerciseRecords.filter { !replaced.contains(MealSyncSlot(album: .exercise, record: $0)) }
        // 다른 기기에서 사진이 바뀐 기록은 여기 남은 도장 원본 띠가 그 사진의 것이 아니다 — 지운다 (지워진 기록도)
        let incoming = Dictionary(saves.map { ($0.record.id, $0.record) }, uniquingKeysWith: { _, new in new })
        func dropStaleBackings(_ olds: [MealRecord], album: AlbumType) {
            for old in olds where replaced.contains(MealSyncSlot(album: album, record: old)) {
                guard let new = incoming[old.id] else { MealStampBackingStore.shared.remove(for: old.id); continue }
                if new.beforeImageData?.count != old.beforeImageData?.count { MealStampBackingStore.shared.save(nil, for: old.id, kind: "before") }
                if new.afterImageData?.count != old.afterImageData?.count { MealStampBackingStore.shared.save(nil, for: old.id, kind: "after") }
            }
        }
        dropStaleBackings(dietRecords, album: .diet)
        dropStaleBackings(exerciseRecords, album: .exercise)
        for save in saves {
            if save.slot.album == .diet { diet.append(save.record) } else { exercise.append(save.record) }
        }
        // 바뀐 앨범만 저장한다 — 새 기기에서 복원하면 이것이 묶음마다 불려, 두 앨범을 매번 통째로 쓰면 메인이 오래 막힌다
        let albums = Set(replaced.map(\.album))
        if albums.contains(.diet) {
            dietRecords = diet
            persist(.diet)
        }
        if albums.contains(.exercise) {
            exerciseRecords = exercise
            persist(.exercise)
        }

        // 받은 날짜를 친구 공유 변경 감지 기준에 넣는다. 안 그러면 복원한 이력 전체가 공개 DB 로 다시 올라간다.
        let currentDiet = currentDateFingerprints()
        let currentExercise = currentExerciseFingerprints()
        _ = storedFingerprints()
        _ = storedExerciseFingerprints()
        for day in changedDays {
            dateFingerprints[day] = currentDiet[day]
            exerciseDateFingerprints[day] = currentExercise[day]
        }
        persistFingerprints()
        persistExerciseFingerprints()

        publishWidgetSnapshot()
        let completedToday = Set(dietMeals(for: Date()).filter { $0.value.isComplete }.keys)
        NotificationManager.shared.scheduleMealNotifications(recordedToday: completedToday)
    }

    // MARK: - 위젯 스냅샷

    /// 마지막으로 위젯을 다시 그리게 한 내용 (같으면 다시 그리지 않는다)
    private var lastWidgetContent: String?

    // 위젯은 사진이 담긴 기록 전체를 디코딩하지 않고 이 요약만 읽는다.
    // 기록이 바뀔 때마다 공유 저장소에 쓰고 위젯 타임라인을 새로고침한다.
    func publishWidgetSnapshot() {
        let cal = Calendar.current
        let now = Date()
        let todays = dietRecords.filter { $0.isComplete && cal.isDate($0.sortDate, inSameDayAs: now) }
        let inProgress = dietRecords
            .filter { $0.isEatingInProgress(asOf: now) }
            .max(by: { $0.sortDate < $1.sortDate })

        let snapshot = WidgetSnapshot(
            todayCount: todays.count,
            inProgressMealType: inProgress?.mealType.rawValue,
            inProgressSince: inProgress?.sortDate,
            lastRecordedAt: todays.map(\.sortDate).max(),
            needsRecordCount: dietRecords.filter { $0.needsRecordCompletion(asOf: now) }.count,
            generatedAt: now,
            // 위젯의 아침·점심·저녁 체크 — 끼니는 촬영 시각이 아니라 기록한 날짜 기준
            recordedMealTypes: dietRecords
                .filter { $0.isComplete && cal.isDate($0.date, inSameDayAs: now) }
                .map(\.mealType.rawValue),
            caredMealTypes: [MealType.breakfast, .lunch, .dinner]
                .filter { SettingsManager.shared.caredMeals.contains($0) }
                .map(\.rawValue)
        )

        if let encoded = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(encoded, forKey: AppGroup.widgetSnapshotKey)
            // 위젯이 보여 주는 내용이 그대로면 다시 그리게 하지 않는다 (저장할 때마다 · 앱을 켤 때마다 불린다).
            // 날이 바뀌면 오늘 수가 달라지므로 그때는 다시 그린다.
            let content = "\(snapshot.todayCount)|\(snapshot.inProgressMealType ?? "")|\(snapshot.inProgressSince?.timeIntervalSince1970 ?? 0)|"
                + "\(snapshot.lastRecordedAt?.timeIntervalSince1970 ?? 0)|\(snapshot.needsRecordCount)|"
                + "\(snapshot.recordedMealTypes ?? [])|\(snapshot.caredMealTypes ?? [])|\(cal.startOfDay(for: now).timeIntervalSince1970)"
            guard content != lastWidgetContent else { return }
            lastWidgetContent = content
            WidgetCenter.shared.reloadAllTimelines()
            Log.app.debug("스냅샷 갱신: 오늘 \(snapshot.todayCount)개, 먹는 중 \(snapshot.inProgressMealType ?? "없음")")
        }
    }

    // MARK: - 스마트 CloudKit 업로드

    /// 현재 식단 기록에서 변경된 날짜를 dirty로 표시
    private func markDirtyDatesFromRecords() {
        // 저장 시점 기준 최근 며칠이 아니라, **실제로 내용이 바뀐 날짜**만 업로드 대상으로 표시한다.
        // (예전에는 최근 3일만 표시해서, 오래된 기록을 고쳐도 서버에 반영되지 않았다)
        let current = currentDateFingerprints()
        let stored = storedFingerprints()

        for (dateString, hash) in current where stored[dateString] != hash {
            dirtyDates.insert(dateString)
        }
        for dateString in stored.keys where current[dateString] == nil {
            dirtyDates.insert(dateString) // 그 날 기록이 모두 지워짐 → 서버에서도 삭제
        }

        dateFingerprints = current
        persistFingerprints()

        // 운동도 같은 방식으로. 업로드는 날짜 단위라 어느 쪽이 바뀌든 그 날을 올리면 된다.
        let currentExercise = currentExerciseFingerprints()
        let storedExercise = storedExerciseFingerprints()

        for (dateString, hash) in currentExercise where storedExercise[dateString] != hash {
            dirtyDates.insert(dateString)
        }
        for dateString in storedExercise.keys where currentExercise[dateString] == nil {
            dirtyDates.insert(dateString)
        }

        exerciseDateFingerprints = currentExercise
        persistExerciseFingerprints()

        if !dirtyDates.isEmpty {
            Log.share.debug("업로드 대기 날짜: \(self.dirtyDates.sorted())")
        }
    }

    /// 업데이트 직후 이력 전체가 "바뀐 것"으로 잡혀 대량 업로드되는 걸 막기 위해,
    /// 앱 시작 시 한 번 현재 상태를 기준값으로 삼는다.
    /// (새로 설치한 기기는 기록이 없는 상태가 기준이 되므로 첫 기록부터 정상 업로드된다)
    private func establishFingerprintBaselineIfNeeded() {
        if !userDefaults.bool(forKey: fingerprintBaselineKey) {
            dateFingerprints = currentDateFingerprints()
            persistFingerprints()
            userDefaults.set(true, forKey: fingerprintBaselineKey)
            Log.share.debug("변경 감지 기준값 생성 (\(self.dateFingerprints.count)일) — 예전 기록은 설정의 '예전 기록 공유'로 올릴 수 있음")
        }

        // 1.0.8에서 운동 공유가 생겼다. 기준값을 지금 상태로 잡아 두지 않으면
        // 첫 실행에 운동 이력 전체가 한꺼번에 올라간다.
        if !userDefaults.bool(forKey: exerciseFingerprintBaselineKey) {
            exerciseDateFingerprints = currentExerciseFingerprints()
            persistExerciseFingerprints()
            userDefaults.set(true, forKey: exerciseFingerprintBaselineKey)
            Log.share.debug("운동 변경 감지 기준값 생성 (\(self.exerciseDateFingerprints.count)일)")
        }
    }

    /// 날짜별 지문. 사진은 바이트 수만 보므로 계산이 가볍다.
    private func currentDateFingerprints() -> [String: Int] {
        fingerprints(of: dietRecords)
    }

    private func currentExerciseFingerprints() -> [String: Int] {
        fingerprints(of: exerciseRecords)
    }

    private func fingerprints(of records: [MealRecord]) -> [String: Int] {
        var grouped: [String: [MealRecord]] = [:]
        for record in records {
            grouped[DayKey.string(from: record.date), default: []].append(record)
        }

        var result: [String: Int] = [:]
        for (dateString, records) in grouped {
            var hasher = StableHasher() // 실행이 바뀌어도 같은 값 (저장해 두고 다음 실행에 비교한다)
            for record in records.sorted(by: { $0.mealType.rawValue < $1.mealType.rawValue }) {
                hasher.combine(record.mealType.rawValue)
                hasher.combine(record.memo ?? "")
                hasher.combine(record.beforeImageData?.count ?? 0)
                hasher.combine(record.afterImageData?.count ?? 0)
                hasher.combine(record.ateAll)
                hasher.combine(record.capturedAt?.timeIntervalSince1970 ?? 0)
            }
            result[dateString] = hasher.finalize()
        }
        return result
    }

    private func storedFingerprints() -> [String: Int] {
        if !dateFingerprints.isEmpty { return dateFingerprints }
        guard let raw = userDefaults.dictionary(forKey: fingerprintsKey) as? [String: Int] else { return [:] }
        dateFingerprints = raw
        return raw
    }

    private func storedExerciseFingerprints() -> [String: Int] {
        if !exerciseDateFingerprints.isEmpty { return exerciseDateFingerprints }
        guard let raw = userDefaults.dictionary(forKey: exerciseFingerprintsKey) as? [String: Int] else { return [:] }
        exerciseDateFingerprints = raw
        return raw
    }

    private func persistExerciseFingerprints() {
        userDefaults.set(exerciseDateFingerprints, forKey: exerciseFingerprintsKey)
    }

    private func persistFingerprints() {
        userDefaults.set(dateFingerprints, forKey: fingerprintsKey)
    }

    /// 식단 기록 전용 접근자 — 현재 앨범 모드(운동/식단)와 무관하게 항상 식단만 본다.
    /// 업로드 경로가 `records`(모드 의존)를 쓰면 운동 모드에서 운동 기록이 식단으로 올라간다.
    func dietMeals(for date: Date) -> [MealType: MealRecord] {
        dietByDay[Calendar.current.startOfDay(for: date)] ?? [:]
    }

    /// 그 날의 운동 기록 (친구 화면의 "운동" 탭으로 올라간다)
    func exerciseMeals(for date: Date) -> [MealType: MealRecord] {
        exerciseByDay[Calendar.current.startOfDay(for: date)] ?? [:]
    }

    /// 식단 기록이 있는 모든 날짜 (최신순)
    var datesWithDietRecords: [Date] {
        let calendar = Calendar.current
        let days = Set(dietRecords.map { calendar.startOfDay(for: $0.date) })
        return days.sorted(by: >)
    }

    /// 대기 중인 업로드가 있으면 올린다 (iCloud 확인이 끝났을 때 FriendManager 가 부른다)
    func uploadPendingIfNeeded() {
        guard !dirtyDates.isEmpty else { return }
        scheduleDelayedUpload()
    }

    /// 지연된 업로드 스케줄 (여러 저장이 연속으로 일어날 때 배치 처리)
    private func scheduleDelayedUpload() {
        // 기존 타이머 취소
        uploadTimer?.invalidate()

        // 새 타이머 설정 (5초 후 업로드)
        uploadTimer = Timer.scheduledTimer(withTimeInterval: uploadDelaySeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.uploadDirtyDates() }
        }

        Log.share.debug("\(Int(self.uploadDelaySeconds))초 후 업로드 예정")
    }

    /// dirty로 표시된 날짜만 업로드
    private func uploadDirtyDates() {
        guard !dirtyDates.isEmpty else {
            Log.share.debug("업로드할 날짜 없음")
            return
        }

        // 로그인 확인 전이면 기다린다 — 지금 올리면 실패로 끝나고 날짜만 다시 쌓인다
        guard FriendManager.shared.isSignedIn, !FriendManager.shared.myUserId.isEmpty,
              SettingsManager.shared.shareMealsToCloud else {
            Log.share.info("업로드 보류 (로그인 전 또는 공유 꺼짐) - \(self.dirtyDates.count)개 날짜 대기")
            return
        }

        Log.share.info("스마트 업로드 시작 - \(self.dirtyDates.count)개 날짜")

        let datesToUpload = dirtyDates
        dirtyDates.removeAll()  // 먼저 클리어 (업로드 중 생긴 변경은 새로 쌓인다)

        _Concurrency.Task {
            var failed: Set<String> = []

            for dateString in datesToUpload.sorted() {
                // 날짜 문자열을 Date로 변환
                guard let date = DayKey.date(from: dateString) else { continue }

                // 음식과 운동을 각각 올린다. 서버에서는 레코드 이름이 달라 서로 덮어쓰지 않는다.
                for album in AlbumType.allCases {
                    let meals = album == .diet ? dietMeals(for: date) : exerciseMeals(for: date)
                    Log.share.debug("\(dateString) - \(album.rawValue) 개수: \(meals.count)")

                    do {
                        if meals.isEmpty {
                            // 그 날 기록이 모두 지워진 경우 — 친구 화면에 남지 않도록 서버에서도 삭제
                            try await FriendManager.shared.deleteMyMeals(date: date, album: album)
                            Log.share.debug("\(dateString) \(album.rawValue) 기록 없음 → 서버에서 삭제")
                        } else {
                            try await FriendManager.shared.uploadMyMeals(date: date, meals: meals, album: album)
                            Log.share.debug("\(dateString) \(album.rawValue) 업로드 완료 (\(meals.count)개)")
                        }
                    } catch {
                        Log.share.error("\(dateString) \(album.rawValue) 업로드 실패: \(error.localizedDescription)")
                        failed.insert(dateString)
                    }
                }
            }

            await MainActor.run {
                self.lastUploadTime = Date()
                // 실패한 날짜는 다시 대기열로 — 앱이 다시 앞으로 오거나 다음에 저장할 때 올린다
                self.dirtyDates.formUnion(failed)
                if failed.isEmpty {
                    Log.share.info("스마트 업로드 완료")
                } else {
                    Log.share.warning("업로드 실패 \(failed.count)개 날짜 — 다음에 다시 시도")
                }
            }
        }
    }

    // MARK: - 사진 파일 보관

    private lazy var dietImageStore: MealImageFileStore? = Self.makeImageStore(folder: "diet")
    private lazy var exerciseImageStore: MealImageFileStore? = Self.makeImageStore(folder: "exercise")

    /// 불러올 때 사진 바이트가 기록 안에 들어 있던 앨범 (파일로 옮겨야 함)
    private var albumsWithInlinePhotos: Set<AlbumType> = []

    /// 파일을 읽지 못한 사진 — "앨범/끼니 칸 이름" → 실제 파일 이름.
    /// 화면엔 비어 보여도 지운 사진이 아니므로, 저장할 때 참조를 버리지 않고 파일도 지우지 않는다.
    private var unreadableImageFiles: [String: String] = [:]

    private static func makeImageStore(folder: String) -> MealImageFileStore? {
        let fileManager = FileManager.default
        // 기록(UserDefaults)이 App Group 에 있으니 사진도 같은 곳에 둔다
        guard let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
                ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = base
            .appendingPathComponent("MealImages", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
        return MealImageFileStore(directory: directory)
    }

    private func imageStore(for album: AlbumType) -> MealImageFileStore? {
        album == .diet ? dietImageStore : exerciseImageStore
    }

    /// 끼니 칸 하나의 기본 파일 이름 (예: 2026-09-10_lunch_before.jpg)
    private func imageSlotName(for record: MealRecord, kind: String) -> String {
        MealRecordWriter.slotName(for: record, kind: kind)
    }

    /// 디스크 쓰기는 메인 밖의 한 줄에서 한다 (MealRecordWriter)
    private lazy var recordWriter = MealRecordWriter(defaults: userDefaults)

    /// 한 앨범의 기록을 디스크에 쓴다. 메인은 기다리지 않는다 — 메모리의 기록이 언제나 기준이다.
    private func persist(_ album: AlbumType) {
        let prefix = "\(album.rawValue)/"
        var unreadable: [String: String] = [:]
        for (slot, file) in unreadableImageFiles where slot.hasPrefix(prefix) {
            unreadable[String(slot.dropFirst(prefix.count))] = file
        }
        let snapshot = MealRecordWriter.Snapshot(
            records: album == .diet ? dietRecords : exerciseRecords,
            key: album == .diet ? dietRecordsKey : exerciseRecordsKey,
            store: imageStore(for: album),
            unreadable: unreadable)
        recordWriter.enqueue(snapshot) { [weak self] referenced in
            // 기록에서 빠진 사진이면 "읽지 못한 사진" 목록에서도 뺀다
            guard let self else { return }
            unreadableImageFiles = unreadableImageFiles.filter { !$0.key.hasPrefix(prefix) || referenced.contains($0.value) }
        }
    }

    /// 밀린 디스크 쓰기가 끝날 때까지 기다린다 (백그라운드로 가거나 종료될 때)
    func finishPendingWrites() {
        recordWriter.waitUntilIdle()
    }

    /// 저장된 기록을 읽고 사진을 다시 붙인다. 사진 바이트가 기록 안에 들어 있던 예전 형식이면 hasInlinePhotos 가 true.
    private func loadStoredRecords(forKey key: String, album: AlbumType) -> (records: [MealRecord], hasInlinePhotos: Bool)? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        guard let entries = try? JSONDecoder().decode([StoredMealRecord].self, from: data) else {
            // 못 읽은 원본을 옆에 남긴다 — 빈 목록으로 시작해 다음 저장이 덮어써도 되찾을 수 있게
            Self.keepUnreadable(data, forKey: key)
            return nil
        }

        let store = imageStore(for: album)
        var hasInlinePhotos = false
        let records = entries.map { entry -> MealRecord in
            let record = entry.record
            if record.beforeImageData != nil || record.afterImageData != nil {
                hasInlinePhotos = true
            }
            let before = record.beforeImageData
                ?? loadImage(named: entry.beforeImageFile, kind: "before", of: record, album: album, store: store)
            let after = record.afterImageData
                ?? loadImage(named: entry.afterImageFile, kind: "after", of: record, album: album, store: store)
            return record.replacingImages(before: before, after: after)
        }
        return (records, hasInlinePhotos)
    }

    private func loadImage(named name: String?, kind: String, of record: MealRecord, album: AlbumType, store: MealImageFileStore?) -> Data? {
        guard let name else { return nil }
        if let data = store?.load(named: name) { return data }
        Log.store.warning("사진 파일을 읽지 못함: \(name)")
        unreadableImageFiles["\(album.rawValue)/\(imageSlotName(for: record, kind: kind))"] = name
        return nil
    }

    /// 예전 형식(사진 바이트가 UserDefaults 안에 든 기록)을 사진 파일 + 가벼운 JSON 으로 옮긴다.
    /// 사진이 쌓이면 이 값이 수백 MB 가 되어, 저장할 때마다 메모리가 치솟아 앱이 종료되던 원인이다.
    /// 바이트를 그대로 옮기므로 화질 손실은 없다.
    private func movePhotosOutOfDefaultsIfNeeded() {
        for album in albumsWithInlinePhotos {
            Log.store.notice("\(album.rawValue, privacy: .public) 기록의 사진을 파일로 옮김")
            persist(album)
        }
        albumsWithInlinePhotos.removeAll()
    }

    /// 기록을 제대로 읽어 들인 앨범 (표준 저장소의 옛 사본을 지워도 되는지 판단용)
    private var loadedAlbums: Set<AlbumType> = []

    /// App Group 으로 옮기기 전 표준 UserDefaults 에 남아 있던 기록 사본을 지운다.
    /// 옮긴 뒤로 한 번도 갱신되지 않은 사본인데 사진이 든 채 수백 MB 로 남아, 설정 하나만 읽어도
    /// 통째로 메모리에 올라왔다. App Group 쪽 기록을 제대로 읽었을 때만 지운다.
    private func removeStaleStandardCopiesIfNeeded() {
        let standard = UserDefaults.standard
        guard userDefaults != standard, userDefaults.bool(forKey: "migratedToAppGroup_v1") else { return }
        for (album, key) in [(AlbumType.diet, dietRecordsKey), (AlbumType.exercise, exerciseRecordsKey)]
        where loadedAlbums.contains(album) && standard.object(forKey: key) != nil {
            standard.removeObject(forKey: key)
            Log.store.info("표준 저장소에 남은 옛 \(album.rawValue) 기록 사본 삭제")
        }
    }

    /// 저장값은 있는데 읽지 못한 앨범. 이 상태의 빈 배열은 "다 지움"이 아니다.
    private var albumsFailedToLoad: Set<AlbumType> = []

    /// 못 읽은 기록 원본을 파일로 둔다. 공유 저장소(UserDefaults)에 두지 않는다 — 예전 형식이면 사진이 든 채
    /// 수백 MB 라, 위젯이 공유 저장소의 키 하나만 읽어도 통째로 메모리에 올라와 위젯 한도를 넘는다.
    private static func keepUnreadable(_ data: Data, forKey key: String) {
        let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(key + ".unreadable.json"), options: .atomic)
    }

    // 기록 불러오기 (식단과 운동 모두 로드)
    private func loadRecords() {
        // 예전 버전이 공유 저장소에 남긴 못 읽은 사본은 파일로 옮긴다
        for key in [dietRecordsKey, exerciseRecordsKey] {
            if let old = userDefaults.data(forKey: key + ".unreadable") {
                Self.keepUnreadable(old, forKey: key)
                userDefaults.removeObject(forKey: key + ".unreadable")
            }
        }

        // 식단 기록 로드
        if let loaded = loadStoredRecords(forKey: dietRecordsKey, album: .diet) {
            dietRecords = loaded.records
            loadedAlbums.insert(.diet)
            if loaded.hasInlinePhotos { albumsWithInlinePhotos.insert(.diet) }
            Log.store.info("식단 기록 로드: \(self.dietRecords.count)개")
        } else if userDefaults.data(forKey: dietRecordsKey) != nil {
            albumsFailedToLoad.insert(.diet)
        }

        // 운동 기록 로드
        if let loaded = loadStoredRecords(forKey: exerciseRecordsKey, album: .exercise) {
            exerciseRecords = loaded.records
            loadedAlbums.insert(.exercise)
            if loaded.hasInlinePhotos { albumsWithInlinePhotos.insert(.exercise) }
            Log.store.info("운동 기록 로드: \(self.exerciseRecords.count)개")
        } else if userDefaults.data(forKey: exerciseRecordsKey) != nil {
            albumsFailedToLoad.insert(.exercise)
        }

        // 저장 없이 앱만 켠 경우에도 위젯이 최신 상태를 보도록 (날이 바뀌면 오늘 수/먹는 중이 달라진다)
        publishWidgetSnapshot()
    }

    // MARK: - Streak 계산 (규칙은 RoutineCameraCore 의 MealStats 한 곳에 — 테스트가 그것을 고정한다)

    // 하루가 "연속 기록에 포함되는 날"인지. 간식을 포함해 한 끼라도 남기면 인정한다
    // (3끼를 다 채워야 하던 기준을 풀어, 완벽하지 못한 날에도 연속이 끊기지 않게).
    func isDayRecorded(_ date: Date) -> Bool {
        getMeals(for: date).values.contains { $0.isComplete }
    }

    func getCurrentStreak() -> Int { MealStats.currentStreak(records: records) }

    // 최고 연속 기록 일수 (업적 판정 등에 사용)
    func getMaxStreak() -> Int { MealStats.maxStreak(records: records) }

    // 지금까지 기록한 날 수 (한 번 올라가면 절대 줄지 않는 누적 카운터)
    // 연속이 끊겨도 사라지지 않아 '나쁜 날'에 대한 자책을 만들지 않는다.
    func getTotalRecordedDays() -> Int { MealStats.totalRecordedDays(records: records) }

    #if DEBUG
    // MARK: - 개발용 샘플 데이터 생성

    func generateSampleData() {
        Log.store.info("샘플 데이터 생성 시작 - \(SettingsManager.shared.albumType.rawValue) 모드")
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

                        // 실제 촬영처럼 날짜 도장을 새기고 원본 띠를 남긴다 — 시뮬레이터(카메라 없음)에서도 "날짜·시간 바꾸기" 를 시험할 수 있게
                        let capturedAt = calendar.date(bySettingHour: mealType.typicalHour, minute: Int.random(in: 0..<60), second: 0, of: date) ?? date
                        let id = UUID()
                        let record = MealRecord(
                            id: id,
                            date: date,
                            mealType: mealType,
                            beforeImageData: stampedSample(beforeImage, date: capturedAt, recordID: id, kind: "before"),
                            afterImageData: stampedSample(afterImage, date: capturedAt, recordID: id, kind: "after"),
                            memo: memo,
                            capturedAt: capturedAt
                        )
                        currentRecords.append(record)
                    }
                }
            }
        }

        records = currentRecords
        Log.store.info("샘플 데이터 생성 완료: \(self.records.count)개 기록 추가")
    }

    /// 샘플 사진에 지금 설정의 날짜 도장을 새기고 도장 아래 원본 띠를 보관한다 (개발용)
    private func stampedSample(_ data: Data?, date: Date, recordID: UUID, kind: String) -> Data? {
        guard let data, let image = UIImage(data: data) else { return data }
        let style = MealStampStyle.current
        MealStampBackingStore.shared.save(style.isEnabled ? MealPhotoStamp.backing(of: image) : nil, for: recordID, kind: kind)
        return MealPhotoStamp.apply(to: image, date: date, style: style).jpegData(compressionQuality: MealPhotoStamp.jpegQuality) ?? data
    }

    #if DEBUG
    // 앱스토어 스크린샷용 데이터: 폴더의 01.jpg… 사진으로 최근 21일 식단을 채운다 (기존 기록은 지움)
    // 실행: SIMCTL_CHILD_SEED_SCREENSHOT_DIR=<폴더> xcrun simctl launch booted com.ysoup.RoutineCamera
    func generateScreenshotData(photoDirectory: String) {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: photoDirectory)) ?? [])
            .filter { $0.lowercased().hasSuffix(".jpg") }
            .sorted()
        let photos = files.compactMap { FileManager.default.contents(atPath: (photoDirectory as NSString).appendingPathComponent($0)) }
        guard !photos.isEmpty else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let slots: [(MealType, Int, Int)] = [(.breakfast, 8, 10), (.lunch, 12, 40), (.dinner, 19, 5)]
        // 스크린샷 언어에 맞춘 메모 (시뮬레이터 언어가 영어면 영어 메모)
        let memosByLanguage: [String: [String]] = [
            "ko": ["친구랑 비빔밥", "오늘은 가볍게", "퇴근 후 떡볶이", "주말 브런치"],
            "en": ["Bibimbap with a friend", "Keeping it light today", "Tteokbokki after work", "Weekend brunch"],
            "zh-Hans": ["和朋友吃拌饭", "今天吃得清淡点", "下班后的炒年糕", "周末早午餐"],
            "zh-Hant": ["和朋友吃拌飯", "今天吃清淡一點", "下班後的辣炒年糕", "週末早午餐"],
            "ja": ["友だちとビビンバ", "今日は軽めに", "仕事帰りのトッポッキ", "週末のブランチ"],
            "ru": ["Пибимпап с другом", "Сегодня что-то лёгкое", "Токпокки после работы", "Бранч в выходной"],
            "es": ["Bibimbap con un amigo", "Hoy, algo ligero", "Tteokbokki al salir del trabajo", "Brunch de fin de semana"],
            "de": ["Bibimbap mit einer Freundin", "Heute mal leicht", "Tteokbokki nach der Arbeit", "Wochenend-Brunch"],
            "fr": ["Bibimbap avec un ami", "Léger aujourd’hui", "Tteokbokki après le boulot", "Brunch du week-end"],
            "it": ["Bibimbap con un’amica", "Oggi qualcosa di leggero", "Tteokbokki dopo il lavoro", "Brunch del weekend"],
            "pt": ["Bibimbap com um amigo", "Hoje, algo leve", "Tteokbokki depois do trabalho", "Brunch de fim de semana"],
            "th": ["บิบิมบับกับเพื่อน", "วันนี้กินเบา ๆ", "ต็อกบกกีหลังเลิกงาน", "บรันช์วันหยุด"],
            "vi": ["Cơm trộn cùng bạn", "Hôm nay ăn nhẹ", "Tteokbokki sau giờ làm", "Bữa brunch cuối tuần"],
            "cs": ["Bibimbap s kamarádem", "Dnes něco lehkého", "Tteokbokki po práci", "Víkendový brunch"],
            "da": ["Bibimbap med en ven", "Noget let i dag", "Tteokbokki efter arbejde", "Weekendbrunch"],
            "el": ["Μπιμπιμπάπ με έναν φίλο", "Σήμερα κάτι ελαφρύ", "Τοκμπόκι μετά τη δουλειά", "Μπραντς Σαββατοκύριακου"],
            "fi": ["Bibimbapia ystävän kanssa", "Tänään jotain kevyttä", "Tteokbokkia töiden jälkeen", "Viikonlopun brunssi"],
            "id": ["Bibimbap bareng teman", "Hari ini yang ringan saja", "Tteokbokki sepulang kerja", "Brunch akhir pekan"],
            "nb": ["Bibimbap med en venn", "Noe lett i dag", "Tteokbokki etter jobb", "Helgebrunsj"],
            "nl": ["Bibimbap met een vriend", "Vandaag iets lichts", "Tteokbokki na het werk", "Weekendbrunch"],
            "pl": ["Bibimbap ze znajomym", "Dziś coś lekkiego", "Tteokbokki po pracy", "Weekendowy brunch"],
            "sv": ["Bibimbap med en vän", "Något lätt i dag", "Tteokbokki efter jobbet", "Helgbrunch"],
            "tr": ["Arkadaşla bibimbap", "Bugün hafif bir şeyler", "İş çıkışı tteokbokki", "Hafta sonu brunch’ı"],
        ]
        let language = Locale.current.language
        let languageCode = language.languageCode?.identifier ?? "en"
        let scriptKey = language.script == .hanTraditional ? "zh-Hant" : "zh-Hans"
        let memos = memosByLanguage[languageCode == "zh" ? scriptKey : languageCode] ?? memosByLanguage["en"]!
        var result: [MealRecord] = []
        var index = 0
        // 식사 지도 스크린샷용 찍은 곳 (서울 몇 군데 — 이름은 기기가 주소로 바꾼 것처럼 비워 둔다)
        let places = [MealPlace(latitude: 37.5665, longitude: 126.9780), MealPlace(latitude: 37.5512, longitude: 126.9882),
                      MealPlace(latitude: 37.5796, longitude: 126.9770), MealPlace(latitude: 37.5443, longitude: 127.0557)]

        for dayOffset in (0...20).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for (slotIndex, slot) in slots.enumerated() {
                let photo = photos[index % photos.count]
                index += 1
                let capturedAt = calendar.date(bySettingHour: slot.1, minute: slot.2, second: 0, of: day)
                let memo = (dayOffset + slotIndex) % 5 == 0 ? memos[(dayOffset + slotIndex) % memos.count] : nil
                // 먹은 양: 절반이 점점 늘어나는 모습 (스크린샷용)
                let portion: MealPortion? = (dayOffset + slotIndex) % 3 == 0 ? .half : ((dayOffset + slotIndex) % 7 == 0 ? .little : .all)
                result.append(MealRecord(date: day, mealType: slot.0, beforeImageData: photo, memo: memo, capturedAt: capturedAt, ateAll: true,
                                         place: places[(dayOffset + slotIndex) % places.count], portion: portion))
            }
        }
        records = result
        HabitStore.shared.seedForScreenshots(days: 21)
    }
    #endif

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
    #endif

    // 모든 데이터 삭제 (개발용 - 현재 앨범 타입의 데이터만)
    func clearAllData() {
        Log.store.info("\(SettingsManager.shared.albumType.rawValue) 모드 데이터 삭제")
        for record in records { MealStampBackingStore.shared.remove(for: record.id) }
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
