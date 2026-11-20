//
//  MealLedger.swift
//  RoutineCameraCore
//
//  한 앨범(식단 또는 운동)의 기록 장부와 그 규칙.
//  "어느 칸에 들어가나 · 덮어써도 되나 · 지우면 무엇이 남나 · 날짜를 옮기면 어떻게 되나" 를 한 곳에서 정한다.
//  저장 · 알림 · 화면 갱신은 모른다 — 앱의 MealRecordStore 가 이 장부를 고친 뒤 그 일들을 한다.
//  지금 시각과 달력을 밖에서 받으므로 그대로 테스트한다.
//

import Foundation

public struct MealLedger: Sendable {
    public private(set) var records: [MealRecord]
    public var calendar: Calendar
    /// 장부를 고친 횟수. 0 이면 저장할 것이 없다.
    public private(set) var changeCount = 0

    public init(records: [MealRecord] = [], calendar: Calendar = .current) {
        self.records = records
        self.calendar = calendar
    }

    // MARK: - 찾기

    private func index(on date: Date, _ mealType: MealType) -> Int? {
        records.firstIndex { $0.mealType == mealType && calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// 그날 그 끼니의 기록
    public func meal(on date: Date, _ mealType: MealType) -> MealRecord? {
        index(on: date, mealType).map { records[$0] }
    }

    /// 지금 새로 기록할 칸. 시간대 끼니가 오늘 이미 기록돼 있으면 덮어쓰지 않고 빈 간식 칸으로 보낸다.
    /// (점심을 찍은 뒤 오후에 간식을 찍으면 점심 사진이 간식으로 교체되던 문제)
    public func recordableMealType(at now: Date) -> MealType {
        let inferred = MealType.inferred(at: now, calendar: calendar)
        let taken = Set(records.filter { $0.isComplete && calendar.isDate($0.date, inSameDayAs: now) }.map(\.mealType))
        if !inferred.isSnack && !taken.contains(inferred) { return inferred }

        // 시간대에 맞는 간식 칸을 먼저, 차 있으면 남은 간식 칸
        let hour = calendar.component(.hour, from: now)
        let preferred: MealType = hour < 11 ? .snack1 : (hour < 16 ? .snack2 : .snack3)
        let candidates = [preferred] + [MealType.snack1, .snack2, .snack3].filter { $0 != preferred }
        // 전부 차 있으면 끼니 사진 대신 간식 칸을 덮어쓴다
        return candidates.first { !taken.contains($0) } ?? preferred
    }

    /// 가장 최근의 "먹는 중"(오늘 식전만 있는) 기록. 날이 지난 미마감 기록은 대상이 아니다.
    public func latestEatingInProgress(asOf now: Date) -> MealRecord? {
        records.filter { $0.isEatingInProgress(asOf: now, calendar: calendar) }.max { $0.sortDate < $1.sortDate }
    }

    // MARK: - 고치기

    /// 그날 그 끼니의 기록을 그 자리에서 고친다 (id 와 다른 칸은 그대로). 기록이 없으면 false.
    /// 예전에는 고칠 때마다 열한 칸을 다시 적어 새 기록을 만들었다 — 칸을 빠뜨리면 그 값이 조용히 사라졌다.
    @discardableResult
    public mutating func update(date: Date, mealType: MealType, _ change: (inout MealRecord) -> Void) -> Bool {
        guard let index = index(on: date, mealType) else { return false }
        change(&records[index])
        changeCount += 1
        return true
    }

    /// 사진을 남긴다. 그 칸에 기록이 있으면 사진만 더하고(먹은 시각 · 메모 · 찍은 곳은 그대로), 없으면 새로 만든다.
    /// - Parameters:
    ///   - capturedAt: 새 기록일 때의 "먹은 시각" (기록 화면에서 고른 값)
    ///   - now: 실제 지금. 식사 시간을 재는 시작 · 끝은 이것으로 남긴다
    /// - Returns: 저장된 기록
    @discardableResult
    public mutating func addPhoto(date: Date, mealType: MealType, imageData: Data, isBefore: Bool,
                                  capturedAt: Date, now: Date, place: MealPlace? = nil) -> MealRecord {
        let calendar = calendar
        // 식전 사진을 지금 먹는 자리에서 남겼을 때만 시작 시각으로 삼는다 — 지난 끼니를 뒤늦게 채운 기록은 재지 않는다
        let startsNow = isBefore && abs(capturedAt.timeIntervalSince(now)) < MealLedger.liveWindow
        let updated = update(date: date, mealType: mealType) { record in
            // 먹는 중이던 식사에 식후 사진이 붙는 순간이 식사가 끝난 시각이다 (식사 시간을 재는 데 쓴다)
            if !isBefore, record.isEatingInProgress(asOf: now, calendar: calendar), record.startedAt != nil {
                record.finishedAt = record.finishedAt ?? now
            }
            // 메모만 있던 빈 기록에 식전 사진을 지금 남기면 그때가 시작이다
            if startsNow, !record.isComplete {
                record.startedAt = record.startedAt ?? now
            }
            if isBefore { record.beforeImageData = imageData } else { record.afterImageData = imageData }
            record.recordedWithoutPhoto = false
            record.capturedAt = record.capturedAt ?? now
            record.place = record.place ?? place
        }
        if !updated {
            records.append(MealRecord(date: calendar.startOfDay(for: date), mealType: mealType,
                                      beforeImageData: isBefore ? imageData : nil,
                                      afterImageData: isBefore ? nil : imageData,
                                      capturedAt: capturedAt, place: place,
                                      startedAt: startsNow ? now : nil))
            changeCount += 1
        }
        // 바로 위에서 고쳤거나 더했으므로 반드시 있다
        return meal(on: date, mealType) ?? records[records.count - 1]
    }

    /// "지금 먹는 자리에서 남긴 것" 으로 보는 폭 (고른 먹은 시각과 실제 지금의 차이)
    public static let liveWindow: TimeInterval = 10 * 60

    /// 사진 없이 기록. 그 칸에 이미 기록이 있으면 그대로 둔다.
    /// - Returns: 새로 남겼으면 true
    @discardableResult
    public mutating func recordWithoutPhoto(date: Date, mealType: MealType, capturedAt: Date) -> Bool {
        guard index(on: date, mealType) == nil else { return false }
        records.append(MealRecord(date: calendar.startOfDay(for: date), mealType: mealType,
                                  recordedWithoutPhoto: true, capturedAt: capturedAt))
        changeCount += 1
        return true
    }

    /// "다 먹음". 그 칸에 기록이 있으면 신호만 붙이고(사진 · 메모는 그대로), 없으면 사진 없는 다 먹음 기록을 만든다.
    /// - Parameter finishedAt: 다 먹은 실제 시각. 한참 뒤 알림에서 누른 것처럼 끝난 때를 모르면 nil (식사 시간을 재지 않는다)
    public mutating func recordAteAll(date: Date, mealType: MealType, finishedAt: Date?, now: Date) {
        let calendar = calendar
        let updated = update(date: date, mealType: mealType) { record in
            if let finishedAt, record.isEatingInProgress(asOf: finishedAt, calendar: calendar), record.startedAt != nil {
                record.finishedAt = record.finishedAt ?? finishedAt
            }
            record.capturedAt = record.capturedAt ?? now
            record.ateAll = true
        }
        if !updated {
            records.append(MealRecord(date: calendar.startOfDay(for: date), mealType: mealType,
                                      capturedAt: now, ateAll: true))
            changeCount += 1
        }
    }

    /// 그날 그 끼니의 기록을 지운다 (겹친 기록이 있으면 모두).
    /// - Returns: 지운 기록의 id — 딸린 파일(도장 원본 띠)을 지우는 데 쓴다
    @discardableResult
    public mutating func delete(date: Date, mealType: MealType) -> [UUID] {
        var removed: [UUID] = []
        records.removeAll { record in
            let remove = record.mealType == mealType && calendar.isDate(record.date, inSameDayAs: date)
            if remove { removed.append(record.id) }
            return remove
        }
        // 지울 것이 없었어도 예전처럼 저장은 한 번 한다 (부르는 쪽이 알림을 정리한다)
        changeCount += 1
        return removed
    }

    // MARK: - 날짜 · 시각 바꾸기

    public enum MoveTarget: Equatable, Sendable {
        /// 이 칸으로 옮길 수 있다. 끼니가 바뀌었을 수 있다 (간식이 그날 빈 간식 칸으로)
        case slot(day: Date, mealType: MealType, dayChanged: Bool)
        /// 그날 같은 끼니 기록이 이미 있어 옮기지 않는다
        case slotTaken
        case notFound
    }

    /// 기록을 새 "먹은 시각" 으로 옮기면 어느 칸에 들어가는지.
    /// 다른 날로 옮길 때 그날 같은 끼니가 이미 있으면 옮기지 않는다 (간식은 빈 간식 칸으로 옮긴다).
    public func moveTarget(date: Date, mealType: MealType, to newCapturedAt: Date) -> MoveTarget {
        guard let original = meal(on: date, mealType) else { return .notFound }
        let newDay = calendar.startOfDay(for: newCapturedAt)
        let dayChanged = !calendar.isDate(original.date, inSameDayAs: newDay)
        guard dayChanged else { return .slot(day: newDay, mealType: mealType, dayChanged: false) }

        let taken = Set(records
            .filter { calendar.isDate($0.date, inSameDayAs: newDay) && $0.isComplete && $0.id != original.id }
            .map(\.mealType))
        guard taken.contains(mealType) else { return .slot(day: newDay, mealType: mealType, dayChanged: true) }
        guard mealType.isSnack,
              let free = [MealType.snack1, .snack2, .snack3].first(where: { !taken.contains($0) }) else { return .slotTaken }
        return .slot(day: newDay, mealType: free, dayChanged: true)
    }

    /// 기록을 그 칸으로 옮긴다. id 와 메모 · 찍은 곳 · 먹은 양 · 잰 식사 시간은 그대로 따라간다.
    /// 옮겨 간 자리에 비어 있는(완료되지 않은) 기록이 있으면 겹치지 않게 치운다.
    /// - Returns: 그 id 의 기록이 없으면 false
    @discardableResult
    public mutating func move(id: UUID, toDay newDay: Date, mealType: MealType, capturedAt: Date,
                              before: Data?, after: Data?) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
        let latest = records[index]
        let day = calendar.startOfDay(for: newDay)
        let dayChanged = !calendar.isDate(latest.date, inSameDayAs: day)
        records[index] = MealRecord(id: latest.id, date: day, mealType: mealType,
                                    beforeImageData: before, afterImageData: after,
                                    memo: latest.memo, recordedWithoutPhoto: latest.recordedWithoutPhoto,
                                    hidePhotoCountBadge: latest.hidePhotoCountBadge, visionAnalysis: latest.visionAnalysis,
                                    capturedAt: capturedAt, ateAll: latest.ateAll, place: latest.place, portion: latest.portion,
                                    // 잰 식사 시간은 "먹은 시각" 을 고쳐도 그대로다
                                    startedAt: latest.startedAt, finishedAt: latest.finishedAt)
        if dayChanged {
            records.removeAll {
                $0.id != id && $0.mealType == mealType && calendar.isDate($0.date, inSameDayAs: day) && !$0.isComplete
            }
        }
        changeCount += 1
        return true
    }
}
