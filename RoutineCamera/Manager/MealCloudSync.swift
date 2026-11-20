//
//  MealCloudSync.swift
//  RoutineCamera
//
//  내 기록과 사진을 iCloud 개인 저장소(private DB)에 보관하고 기기끼리 맞춘다.
//  친구 공유용 공개 DB(FriendManager)와는 완전히 별개다 — 여기 올린 것은 나만 볼 수 있다.
//
//  - 끼니 칸(앨범 + 날짜 + 끼니) 하나가 CloudKit 레코드 하나다. MealRecord.id 는 고칠 때마다 바뀌어 쓰지 않는다.
//  - 이 기기 저장값과 지난번 동기화 상태를 비교해 바뀐 칸만 보낸다 (reconcile).
//  - 원칙은 "기록을 잃지 않는다": 로그아웃 · iCloud 데이터 삭제 · 읽기 실패 때 이 기기 기록을 지우지 않는다.
//

import CloudKit
import Combine
import CryptoKit
import Foundation
import RoutineCameraCore
import os

/// 끼니 칸 하나의 주소. 날짜는 기기 시간대의 달력 날짜 문자열이라 시간대를 옮겨도 같은 칸이다.
struct MealSyncSlot: Hashable {
    let album: AlbumType
    let day: String
    let mealType: MealType

    init(album: AlbumType, record: MealRecord) {
        self.album = album
        self.day = DayKey.string(from: record.date)
        self.mealType = record.mealType
    }

    /// 레코드 이름: meal_<앨범>_<yyyy-MM-dd>_<끼니>. 표시용 rawValue(한글) 대신 케이스 이름을 쓴다.
    init?(recordName: String) {
        guard let parsed = MealSyncPlanner.parseSlotName(recordName),
              let album = AlbumType.allCases.first(where: { "\($0)" == parsed.album }) else { return nil }
        self.album = album
        self.day = parsed.day
        self.mealType = parsed.mealType
    }

    var recordName: String { MealSyncPlanner.slotName(album: "\(album)", day: day, mealType: mealType) }

    var date: Date? {
        DayKey.date(from: day).map { Calendar.current.startOfDay(for: $0) }
    }
}

@MainActor
final class MealCloudSync: ObservableObject {
    static let shared = MealCloudSync()

    enum Status: Equatable {
        case off
        case notSignedIn
        case uploading(Int)
        case upToDate
        case storageFull
        case failed
    }

    @Published private(set) var status: Status = .off
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            AppGroup.defaults.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? startEngineIfPossible() : stopEngine()
        }
    }

    private static let enabledKey = "iCloudMealBackupEnabled"
    private static let containerID = "iCloud.com.ysoup.RoutineCamera"
    private static let recordType = "SekkiMeal"
    /// 하루 기록 · 스탬프 목록 (JSON 한 덩어리)
    private static let habitRecordType = "SekkiHabit"
    private static let zoneID = CKRecordZone.ID(zoneName: "SekkiMeals", ownerName: CKCurrentUserDefaultName)

    /// 칸마다의 동기화 상태 — 모양과 "무엇이 바뀌었나" 판정은 RoutineCameraCore 의 MealSyncPlanner
    private typealias SlotState = MealSyncSlotState

    private struct PersistedState: Codable {
        var engineState: CKSyncEngine.State.Serialization?
        var slots: [String: SlotState] = [:]
    }

    private var state = PersistedState()
    private var engine: CKSyncEngine?
    private var hasStarted = false
    private var hitStorageLimit = false
    private var hadSendFailure = false
    private var isSignedOut = false

    private var store: MealRecordStore { MealRecordStore.shared }

    private init() {
        isEnabled = AppGroup.defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        state = Self.loadState()
    }

    // MARK: - 진입점

    /// 앱 시작 때 한 번. MealRecordStore 초기화가 끝난 뒤 불러야 한다.
    func start() {
        guard !hasStarted else { return }
        // 스크린샷용 가짜 데이터가 내 iCloud 로 올라가거나 지우지 않도록
        guard ProcessInfo.processInfo.environment["SEED_SCREENSHOT_DIR"] == nil else { return }
        // 저장된 기록을 읽지 못했으면 "다 지워진 것"으로 보여 iCloud 까지 지울 수 있다. 동기화를 멈춘다.
        guard store.canTrustLoadedRecordsForSync, !HabitStore.shared.failedToLoad else {
            Log.sync.warning("저장된 기록을 읽지 못해 동기화를 시작하지 않음")
            return
        }
        hasStarted = true
        Self.removeTemporaryAssets()
        if isEnabled { startEngineIfPossible() }
    }

    /// 앱이 앞으로 올 때: 다른 기기 변경을 받고, 지난번에 못 보낸 것을 다시 보낸다.
    func appBecameActive() {
        guard let engine else { return }
        hitStorageLimit = false
        hadSendFailure = false
        flushDirtySlots()
        refreshStatus()
        Task { await refreshAccountStatus() }
        Task { try? await engine.fetchChanges() }
    }

    /// 기록을 저장할 때마다 MealRecordStore 가 부른다.
    func localRecordsChanged() {
        guard hasStarted, isEnabled, engine != nil else { return }
        reconcile()
    }

    // MARK: - 엔진

    private func startEngineIfPossible() {
        guard hasStarted, engine == nil else { return }
        let database = CKContainer(identifier: Self.containerID).privateCloudDatabase
        let delegate = MealCloudSyncEngineDelegate(owner: self)
        engineDelegate = delegate
        let configuration = CKSyncEngine.Configuration(database: database,
                                                       stateSerialization: state.engineState,
                                                       delegate: delegate)
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        reconcile()
        flushDirtySlots()
        refreshStatus()
        Task { await refreshAccountStatus() }
    }

    private var engineDelegate: MealCloudSyncEngineDelegate?

    private func stopEngine() {
        engine = nil
        engineDelegate = nil
        refreshStatus()
    }

    private func refreshAccountStatus() async {
        let accountStatus = try? await CKContainer(identifier: Self.containerID).accountStatus()
        isSignedOut = accountStatus != .available
        refreshStatus()
    }

    private func refreshStatus() {
        guard isEnabled, engine != nil else { status = .off; return }
        if isSignedOut { status = .notSignedIn; return }
        let pending = state.slots.values.filter(\.isDirty).count
        if pending == 0 { status = .upToDate; hitStorageLimit = false; hadSendFailure = false; return }
        if hitStorageLimit { status = .storageFull; return }
        status = hadSendFailure ? .failed : .uploading(pending)
    }

    // MARK: - 이 기기 변경 찾기

    private func fingerprint(of record: MealRecord) -> String {
        MealSyncPlanner.fingerprint(of: record)
    }

    private static func hexDigest(_ source: Data) -> String {
        MealSyncPlanner.hexDigest(source)
    }

    private func reconcile() {
        // 끼니 칸 + 하루 기록(스탬프 · 수분 · 카페인)과 스탬프 목록
        let meals = store.allRecordsForSync.map { album, record in
            MealSyncPlanner.Item.meal(name: MealSyncSlot(album: album, record: record).recordName,
                                      fingerprint: fingerprint(of: record), recordedAt: record.sortDate)
        }
        let habits = HabitStore.shared.syncDocuments.map { name, data in
            MealSyncPlanner.Item.document(name: name, fingerprint: Self.hexDigest(data),
                                          modifiedAt: HabitStore.shared.syncModifiedAt(of: name))
        }
        let plan = MealSyncPlanner.reconcile(slots: &state.slots, current: meals + habits, now: Date())
        guard !plan.isEmpty else { return }
        plan.saves.forEach(enqueueSave)
        plan.deletes.forEach(enqueueDelete)
        saveState()
        refreshStatus()
    }

    private func flushDirtySlots() {
        for (name, slot) in state.slots where slot.isDirty {
            slot.isDeleted ? enqueueDelete(name) : enqueueSave(name)
        }
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: Self.zoneID)
    }

    private func enqueueSave(_ name: String) {
        let id = recordID(name)
        engine?.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    private func enqueueDelete(_ name: String) {
        let id = recordID(name)
        engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
        engine?.state.add(pendingRecordZoneChanges: [.deleteRecord(id)])
    }

    // MARK: - 보내기

    fileprivate func nextBatch(context: CKSyncEngine.SendChangesContext,
                               engine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = engine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !changes.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { [weak self] id in
            await self?.buildRecord(for: id)
        }
    }

    private func buildRecord(for id: CKRecord.ID) -> CKRecord? {
        if HabitSyncName.isHabit(id.recordName) { return buildHabitRecord(for: id) }
        guard let slot = MealSyncSlot(recordName: id.recordName),
              let date = slot.date,
              let meal = (slot.album == .diet ? store.dietMeals(for: date) : store.exerciseMeals(for: date))[slot.mealType],
              let current = state.slots[id.recordName], !current.isDeleted else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }

        let record = Self.record(fromSystemFields: current.systemFields)
            ?? CKRecord(recordType: Self.recordType, recordID: id)
        record["album"] = "\(slot.album)"
        record["day"] = slot.day
        record["mealType"] = "\(slot.mealType)"
        record["memo"] = meal.memo
        record["recordedWithoutPhoto"] = meal.recordedWithoutPhoto
        record["hidePhotoCountBadge"] = meal.hidePhotoCountBadge
        record["ateAll"] = meal.ateAll
        record["portion"] = meal.portion?.rawValue
        record["capturedAt"] = meal.capturedAt
        // 식사 시간을 잰 기록만 쓴다 — 재지 않은 기록은 서버에 이 필드가 없어도 올라간다
        if meal.startedAt != nil || record["startedAt"] != nil { record["startedAt"] = meal.startedAt }
        if meal.finishedAt != nil || record["finishedAt"] != nil { record["finishedAt"] = meal.finishedAt }
        // 찍은 곳 — 내 개인 iCloud 에만. 친구 공개 기록에는 넣지 않는다
        record["placeLatitude"] = meal.place?.latitude
        record["placeLongitude"] = meal.place?.longitude
        record["placeName"] = meal.place?.name
        record["modifiedAt"] = current.modifiedAt
        record["fingerprint"] = current.fingerprint
        let visionData = meal.visionAnalysis.flatMap { try? JSONEncoder().encode($0) }
        record.setObject(visionData as NSData?, forKey: "visionAnalysis")

        for (kind, data, field) in [("before", meal.beforeImageData, "beforeImage"),
                                    ("after", meal.afterImageData, "afterImage")] {
            // 파일을 못 읽어 비어 보이는 사진으로 iCloud 사본까지 지우지 않는다
            if data == nil, store.isPhotoUnreadableForSync(meal, album: slot.album, kind: kind) { continue }
            guard let data else { record.setObject(nil, forKey: field); continue }
            guard let url = Self.writeTemporaryAsset(data, name: "\(id.recordName)_\(kind).jpg") else { return nil }
            record.setObject(CKAsset(fileURL: url), forKey: field)
        }
        return record
    }

    private func buildHabitRecord(for id: CKRecord.ID) -> CKRecord? {
        guard let data = HabitStore.shared.syncDocument(named: id.recordName),
              let current = state.slots[id.recordName], !current.isDeleted else {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }
        let record = Self.record(fromSystemFields: current.systemFields)
            ?? CKRecord(recordType: Self.habitRecordType, recordID: id)
        record["payload"] = data
        record["modifiedAt"] = current.modifiedAt
        record["fingerprint"] = current.fingerprint
        return record
    }

    // MARK: - 보낸 결과

    fileprivate func handle(_ event: CKSyncEngine.Event, engine: CKSyncEngine) {
        switch event {
        case .stateUpdate(let update):
            state.engineState = update.stateSerialization
            saveState()
        case .accountChange(let change):
            handleAccountChange(change)
        case .fetchedDatabaseChanges(let changes):
            handleDatabaseChanges(changes)
        case .fetchedRecordZoneChanges(let changes):
            handleFetched(changes)
        case .sentRecordZoneChanges(let sent):
            handleSent(sent)
        default:
            break
        }
        refreshStatus()
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        for record in sent.savedRecords {
            let name = record.recordID.recordName
            state.slots[name]?.systemFields = Self.systemFields(of: record)
            // 보내는 사이에 또 고쳤으면 그 변경은 아직 안 올라간 것이다
            if state.slots[name]?.fingerprint == record["fingerprint"] as? String {
                state.slots[name]?.isDirty = false
            }
            Self.removeTemporaryAssets(recordName: name)
        }
        for id in sent.deletedRecordIDs where state.slots[id.recordName]?.isDeleted == true {
            state.slots.removeValue(forKey: id.recordName)
        }

        var conflicts: [CKRecord] = []
        for failure in sent.failedRecordSaves {
            let name = failure.record.recordID.recordName
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord { conflicts.append(server) }
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                state.slots[name]?.systemFields = nil
                enqueueSave(name)
            case .unknownItem:
                // 다른 기기에서 지운 레코드. 이 기기 변경이 더 나중이므로 새로 만든다.
                state.slots[name]?.systemFields = nil
                enqueueSave(name)
            case .quotaExceeded:
                hitStorageLimit = true
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                 .requestRateLimited, .notAuthenticated, .operationCancelled, .batchRequestFailed:
                break // 엔진이 알아서 다시 시도한다
            default:
                // 무한 반복을 막기 위해 바로 다시 넣지 않는다. 다음에 앱을 열 때 flushDirtySlots 가 다시 넣는다.
                hadSendFailure = true
                Log.sync.error("저장 실패 \(name): \(failure.error.localizedDescription)")
            }
        }
        if !conflicts.isEmpty { applyRemote(saves: conflicts, deletions: []) }
        saveState()
    }

    // MARK: - 받기

    private func handleFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        applyRemote(saves: changes.modifications.map(\.record),
                    deletions: changes.deletions.map(\.recordID))
    }

    private func applyRemote(saves allSaves: [CKRecord], deletions allDeletions: [CKRecord.ID]) {
        let isHabit = { (name: String) in HabitSyncName.isHabit(name) }
        applyRemoteHabits(saves: allSaves.filter { isHabit($0.recordID.recordName) },
                          deletions: allDeletions.filter { isHabit($0.recordName) })
        let saves = allSaves.filter { !isHabit($0.recordID.recordName) }
        let deletions = allDeletions.filter { !isHabit($0.recordName) }

        var applied: [(slot: MealSyncSlot, record: MealRecord)] = []
        var deletedSlots: [MealSyncSlot] = []
        var afterApply: [(MealSyncSlot, Date, Bool)] = []

        for server in saves {
            guard let slot = MealSyncSlot(recordName: server.recordID.recordName),
                  let date = slot.date else { continue } // 새 버전이 만든, 아직 모르는 끼니는 건너뛴다
            let name = slot.recordName
            let meta = state.slots[name]
            let serverFields = Self.systemFields(of: server)

            if let meta, meta.fingerprint == server["fingerprint"] as? String {
                state.slots[name]?.systemFields = serverFields
                // 저장은 됐는데 응답만 못 받은 경우 — 같은 내용이니 더 보낼 것이 없다
                if !meta.isDeleted {
                    state.slots[name]?.isDirty = false
                    engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
                }
                continue
            }

            let local = (slot.album == .diet ? store.dietMeals(for: date) : store.exerciseMeals(for: date))[slot.mealType]
            let remoteModifiedAt = server["modifiedAt"] as? Date ?? .distantPast
            let decision = MealSyncResolver.resolveRemoteSave(localExists: local != nil,
                                                              localHasPendingChange: meta?.isDirty ?? false,
                                                              localModifiedAt: meta?.modifiedAt,
                                                              remoteModifiedAt: remoteModifiedAt,
                                                              localWasSynced: meta?.systemFields != nil)
            guard decision != .ignore else {
                state.slots[name]?.systemFields = serverFields
                continue
            }

            var remote = Self.mealRecord(from: server, date: date, mealType: slot.mealType)
            if Self.hasUnreadableAsset(server, in: remote) {
                // 서버에는 사진이 있는데 파일을 못 읽었다. 없는 사진으로 받아들이면 이 기기 사진까지 지워진다
                Log.sync.error("받은 사진을 읽지 못함 \(name, privacy: .public) — 이 기기 사진을 그대로 둔다")
                remote = Self.fillingPhotos(of: remote, from: local)
            }
            let result: MealRecord
            var stillDirty = false
            switch decision {
            case .applyRemote, .ignore:
                result = remote
            case .applyRemoteFillingPhotos:
                let filled = Self.fillingPhotos(of: remote, from: local)
                stillDirty = filled.beforeImageData?.count != remote.beforeImageData?.count
                    || filled.afterImageData?.count != remote.afterImageData?.count
                result = filled
            case .keepLocalFillingPhotos:
                result = Self.fillingPhotos(of: local ?? remote, from: remote)
                stillDirty = true
            case .keepLocal:
                result = local ?? remote
                stillDirty = true
            }

            applied.append((slot, result))
            let keepsLocal = decision == .keepLocalFillingPhotos || decision == .keepLocal
            let modifiedAt = keepsLocal ? (meta?.modifiedAt ?? remoteModifiedAt) : remoteModifiedAt
            afterApply.append((slot, modifiedAt, stillDirty))
            var updated = meta ?? SlotState(modifiedAt: modifiedAt, isDirty: false, isDeleted: false)
            updated.systemFields = serverFields
            state.slots[name] = updated
        }

        for id in deletions {
            guard let slot = MealSyncSlot(recordName: id.recordName) else { continue }
            let meta = state.slots[id.recordName]
            if MealSyncResolver.shouldApplyRemoteDelete(localHasPendingChange: meta?.isDirty ?? false) {
                deletedSlots.append(slot)
                state.slots.removeValue(forKey: id.recordName)
            } else if meta?.isDeleted == true {
                state.slots.removeValue(forKey: id.recordName) // 양쪽 다 지웠다
                engine?.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
            } else {
                state.slots[id.recordName]?.systemFields = nil // 이 기기 변경을 새 레코드로 다시 올린다
                enqueueSave(id.recordName)
            }
        }

        guard !applied.isEmpty || !deletedSlots.isEmpty else { saveState(); return }

        // 먼저 메모리·파일에 반영하고, 반영된 내용을 기준으로 지문을 맞춘다 (다시 올라가지 않게)
        store.applySyncChanges(saves: applied, deletes: deletedSlots)
        for (index, item) in afterApply.enumerated() {
            let name = item.0.recordName
            state.slots[name]?.fingerprint = fingerprint(of: applied[index].record)
            state.slots[name]?.modifiedAt = item.1
            state.slots[name]?.isDeleted = false
            state.slots[name]?.isDirty = item.2
            if item.2 {
                enqueueSave(name)
            } else {
                engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
                engine?.state.remove(pendingRecordZoneChanges: [.deleteRecord(recordID(name))])
            }
        }
        saveState()
    }

    /// 하루 기록 · 스탬프 목록 받기. 둘 다 고쳤으면 나중에 고친 쪽이 이긴다.
    private func applyRemoteHabits(saves: [CKRecord], deletions: [CKRecord.ID]) {
        guard !saves.isEmpty || !deletions.isEmpty else { return }
        var applied: [String: Data] = [:]
        var deleted: [String] = []
        var stampsDate: Date?

        for server in saves {
            let name = server.recordID.recordName
            let meta = state.slots[name]
            let remoteModifiedAt = server["modifiedAt"] as? Date ?? .distantPast
            state.slots[name, default: SlotState(modifiedAt: remoteModifiedAt, isDirty: false, isDeleted: false)]
                .systemFields = Self.systemFields(of: server)
            if meta?.fingerprint == server["fingerprint"] as? String, meta?.isDeleted != true {
                state.slots[name]?.isDirty = false
                engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(server.recordID)])
                continue
            }
            if let meta, meta.isDirty, meta.modifiedAt > remoteModifiedAt {
                enqueueSave(name) // 이 기기에서 더 나중에 고쳤다 — 내 것을 다시 올린다
                continue
            }
            guard let data = server["payload"] as? Data else { continue }
            applied[name] = data
            if name == HabitSyncName.stamps { stampsDate = remoteModifiedAt }
            state.slots[name]?.modifiedAt = remoteModifiedAt
        }

        for id in deletions {
            let name = id.recordName
            if MealSyncResolver.shouldApplyRemoteDelete(localHasPendingChange: state.slots[name]?.isDirty ?? false) {
                deleted.append(name)
                state.slots.removeValue(forKey: name)
            } else if state.slots[name]?.isDeleted == true {
                state.slots.removeValue(forKey: name)
                engine?.state.remove(pendingRecordZoneChanges: [.deleteRecord(id)])
            } else {
                state.slots[name]?.systemFields = nil
                enqueueSave(name)
            }
        }

        guard !applied.isEmpty || !deleted.isEmpty else { saveState(); return }
        HabitStore.shared.applySyncDocuments(saves: applied, deletes: deleted, stampsModifiedAt: stampsDate)
        // 반영된 내용으로 지문을 맞춰 다시 올라가지 않게 한다
        for name in applied.keys {
            state.slots[name]?.fingerprint = HabitStore.shared.syncDocument(named: name).map(Self.hexDigest)
            state.slots[name]?.isDirty = false
            state.slots[name]?.isDeleted = false
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
        }
        saveState()
    }

    private func handleDatabaseChanges(_ changes: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for deletion in changes.deletions where deletion.zoneID == Self.zoneID {
            switch deletion.reason {
            case .deleted, .purged:
                // iCloud 설정에서 이 앱 데이터를 지웠다. 뜻을 따라 다시 올리지 않되, 이 기기 기록은 남긴다.
                state.slots.removeAll()
                saveState()
                isEnabled = false
                return
            default:
                // 암호화 키 재설정 등 — iCloud 쪽 사본만 사라졌으니 이 기기 기록으로 다시 올린다
                requeueEverything()
            }
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn, .switchAccounts:
            isSignedOut = false
            hitStorageLimit = false
            requeueEverything()
        case .signOut:
            // 로그아웃해도 이 기기 기록은 지우지 않는다 (이 기기에만 있는 기록일 수 있다)
            isSignedOut = true
        @unknown default:
            break
        }
    }

    /// 새 계정 · 빈 iCloud 기준으로 다시 올린다. 고친 시각은 유지해 받은 내용과 공정하게 비교한다.
    private func requeueEverything() {
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        state.slots = state.slots.filter { !$0.value.isDeleted }
        for name in state.slots.keys {
            state.slots[name]?.systemFields = nil
            state.slots[name]?.isDirty = true
        }
        reconcile()
        flushDirtySlots()
        saveState()
    }

    // MARK: - CKRecord ↔ MealRecord

    private static func mealRecord(from server: CKRecord, date: Date, mealType: MealType) -> MealRecord {
        MealRecord(date: date,
                   mealType: mealType,
                   beforeImageData: assetData(server["beforeImage"]),
                   afterImageData: assetData(server["afterImage"]),
                   memo: server["memo"] as? String,
                   recordedWithoutPhoto: server["recordedWithoutPhoto"] as? Bool ?? false,
                   hidePhotoCountBadge: server["hidePhotoCountBadge"] as? Bool ?? false,
                   visionAnalysis: (server["visionAnalysis"] as? Data).flatMap { try? JSONDecoder().decode(VisionAnalysisData.self, from: $0) },
                   capturedAt: server["capturedAt"] as? Date,
                   ateAll: server["ateAll"] as? Bool ?? false,
                   place: place(from: server),
                   portion: (server["portion"] as? String).flatMap(MealPortion.init(rawValue:)),
                   startedAt: server["startedAt"] as? Date,
                   finishedAt: server["finishedAt"] as? Date)
    }

    /// 서버 레코드에는 사진이 있는데 읽어 온 기록에는 없는 칸이 있는지
    private static func hasUnreadableAsset(_ server: CKRecord, in record: MealRecord) -> Bool {
        (server["beforeImage"] is CKAsset && record.beforeImageData == nil)
            || (server["afterImage"] is CKAsset && record.afterImageData == nil)
    }

    private static func place(from server: CKRecord) -> MealPlace? {
        guard let latitude = server["placeLatitude"] as? Double,
              let longitude = server["placeLongitude"] as? Double else { return nil }
        return MealPlace(latitude: latitude, longitude: longitude, name: server["placeName"] as? String)
    }

    /// 받은 사진. 통째로 메모리에 올리지 않는다 — 새 기기에서 몇 년 치를 받으면 수백 MB 가 되어 앱이 종료된다.
    /// CloudKit 의 파일은 CloudKit 이 언제 지우거나 바꿀지 모르므로 우리 폴더로 복제(APFS 라 바로 끝난다)한 뒤 매핑한다.
    /// 복제본은 매핑이 살아 있는 동안 지우지 않는다 — 다음 실행 때 removeTemporaryAssets() 가 정리한다.
    private static func assetData(_ value: CKRecordValue?) -> Data? {
        guard let source = (value as? CKAsset)?.fileURL else { return nil }
        let copy = receivedAssetDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: receivedAssetDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: copy)
            return try Data(contentsOf: copy, options: .alwaysMapped)
        } catch {
            return try? Data(contentsOf: source)
        }
    }

    /// 받은 사진의 복제본 (임시 사진 폴더 안이라 다음 실행 때 함께 지워진다)
    private static var receivedAssetDirectory: URL {
        assetDirectory.appendingPathComponent("received", isDirectory: true)
    }

    private static func fillingPhotos(of base: MealRecord, from other: MealRecord?) -> MealRecord {
        MealSyncPlanner.fillingPhotos(of: base, from: other)
    }

    private static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private static func record(fromSystemFields data: Data?) -> CKRecord? {
        guard let data, let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: - 파일

    private static var stateURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MealCloudSync", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    private static func loadState() -> PersistedState {
        guard let url = stateURL, FileManager.default.fileExists(atPath: url.path) else { return PersistedState() }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: url))
        } catch {
            // 처음부터 다시 맞춘다 (기록을 잃지는 않지만 전부 다시 비교해 올린다) — 왜 그랬는지 남긴다
            Log.sync.fault("동기화 상태를 읽지 못해 처음부터 다시 맞춤: \(String(describing: error))")
            return PersistedState()
        }
    }

    private func saveState() {
        guard let url = Self.stateURL else { return }
        do {
            let data = try JSONEncoder().encode(state)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            // 못 쓰면 다음 실행이 옛 상태로 시작해 이미 올린 것을 다시 올린다
            Log.sync.error("동기화 상태를 저장하지 못함: \(String(describing: error))")
        }
    }

    private static var assetDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MealCloudSyncAssets", isDirectory: true)
    }

    private static func writeTemporaryAsset(_ data: Data, name: String) -> URL? {
        let url = assetDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.sync.warning("임시 사진 파일을 쓰지 못함: \(error.localizedDescription)")
            return nil
        }
    }

    private static func removeTemporaryAssets(recordName: String) {
        for kind in ["before", "after"] {
            try? FileManager.default.removeItem(at: assetDirectory.appendingPathComponent("\(recordName)_\(kind).jpg"))
        }
    }

    private static func removeTemporaryAssets() {
        try? FileManager.default.removeItem(at: assetDirectory)
    }
}

/// CKSyncEngine 은 delegate 를 강하게 잡지 않고 임의 스레드에서 부른다. 메인 액터로 넘겨 주는 얇은 다리.
private final class MealCloudSyncEngineDelegate: CKSyncEngineDelegate, @unchecked Sendable {
    private weak var owner: MealCloudSync?

    init(owner: MealCloudSync) { self.owner = owner }

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await MainActor.run { owner?.handle(event, engine: syncEngine) }
    }

    nonisolated func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                               syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await owner?.nextBatch(context: context, engine: syncEngine)
    }
}
