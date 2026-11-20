import XCTest
@testable import RoutineCameraCore

/// iCloud 백업: 이 기기에서 무엇이 바뀌었나. 바뀌지 않은 것을 다시 올리면 안 되고, 바뀐 것을 빠뜨려도 안 된다.
final class MealSyncPlannerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var now: Date { t0.addingTimeInterval(3600) }
    private let id = UUID(uuidString: "8C8B0F0E-1B1A-4C1D-9E1F-0000000000AA")!

    private func meal(_ name: String, _ fingerprint: String) -> MealSyncPlanner.Item {
        .meal(name: name, fingerprint: fingerprint, recordedAt: t0)
    }

    // MARK: 무엇을 보내나

    func testFirstSight_savesWithRecordTime() {
        var slots: [String: MealSyncSlotState] = [:]
        let plan = MealSyncPlanner.reconcile(slots: &slots, current: [meal("a", "f1")], now: now)
        XCTAssertEqual(plan, .init(saves: ["a"], deletes: []))
        XCTAssertEqual(slots["a"], MealSyncSlotState(fingerprint: "f1", modifiedAt: t0, isDirty: true, isDeleted: false))
    }

    /// ad6cf9d: 앱을 켤 때마다 전체 기록을 다시 올렸다 — 바뀌지 않았으면 아무것도 보내지 않는다
    func testRegression_unchangedRecordsAreNotSentAgain() {
        var slots: [String: MealSyncSlotState] = [:]
        let items = (0..<50).map { meal("slot\($0)", "f\($0)") }
        _ = MealSyncPlanner.reconcile(slots: &slots, current: items, now: now)
        for name in slots.keys { slots[name]?.isDirty = false }   // 다 올라갔다
        let settled = slots

        let again = MealSyncPlanner.reconcile(slots: &slots, current: items, now: now.addingTimeInterval(86_400))
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(slots, settled, "상태도 건드리지 않는다 (고친 시각이 바뀌면 충돌 때 엉뚱한 쪽이 이긴다)")
    }

    func testChangedRecord_isSentWithCurrentTime() {
        var slots = ["a": MealSyncSlotState(fingerprint: "f1", modifiedAt: t0, isDirty: false, isDeleted: false, systemFields: Data([1]))]
        let plan = MealSyncPlanner.reconcile(slots: &slots, current: [meal("a", "f2")], now: now)
        XCTAssertEqual(plan.saves, ["a"])
        XCTAssertEqual(slots["a"]?.modifiedAt, now)
        XCTAssertEqual(slots["a"]?.isDirty, true)
        XCTAssertEqual(slots["a"]?.systemFields, Data([1]), "서버 레코드 정보는 지키고 그 위에 덮어쓴다")
    }

    func testMissingRecord_isDeletedOnce() {
        var slots = ["a": MealSyncSlotState(fingerprint: "f1", modifiedAt: t0, isDirty: false, isDeleted: false),
                     "b": MealSyncSlotState(fingerprint: "f2", modifiedAt: t0, isDirty: false, isDeleted: false)]
        let plan = MealSyncPlanner.reconcile(slots: &slots, current: [meal("a", "f1")], now: now)
        XCTAssertEqual(plan, .init(saves: [], deletes: ["b"]))
        XCTAssertEqual(slots["b"]?.isDeleted, true)
        XCTAssertEqual(slots["b"]?.isDirty, true)
        // 아직 서버에서 안 지워졌어도 다시 계획에 넣지 않는다
        XCTAssertTrue(MealSyncPlanner.reconcile(slots: &slots, current: [meal("a", "f1")], now: now).isEmpty)
    }

    func testRecreatedAfterDelete_isSavedEvenWithSameContent() {
        var slots = ["a": MealSyncSlotState(fingerprint: "f1", modifiedAt: t0, isDirty: true, isDeleted: true)]
        let plan = MealSyncPlanner.reconcile(slots: &slots, current: [meal("a", "f1")], now: now)
        XCTAssertEqual(plan.saves, ["a"])
        XCTAssertEqual(slots["a"]?.isDeleted, false)
    }

    func testDocument_usesItsOwnModifiedTime() {
        var slots: [String: MealSyncSlotState] = [:]
        let edited = t0.addingTimeInterval(120)
        _ = MealSyncPlanner.reconcile(slots: &slots, current: [.document(name: "habit", fingerprint: "h1", modifiedAt: edited)], now: now)
        XCTAssertEqual(slots["habit"]?.modifiedAt, edited)
        _ = MealSyncPlanner.reconcile(slots: &slots, current: [.document(name: "habit", fingerprint: "h2", modifiedAt: nil)], now: now)
        XCTAssertEqual(slots["habit"]?.modifiedAt, now, "고친 시각을 모르면 지금")
    }

    func testEmptyDevice_deletesEverythingKnown() {
        // 그래서 앱은 저장값을 못 읽었을 때 동기화를 시작하지 않는다 (빈 목록이 "다 지움" 으로 보인다)
        var slots = ["a": MealSyncSlotState(fingerprint: "f1", modifiedAt: t0, isDirty: false, isDeleted: false)]
        XCTAssertEqual(MealSyncPlanner.reconcile(slots: &slots, current: [], now: now).deletes, ["a"])
    }

    // MARK: 지문

    private func baseRecord() -> MealRecord {
        MealRecord(id: id, date: t0, mealType: .lunch, beforeImageData: Data([1, 2, 3]), memo: "m", capturedAt: t0, ateAll: true)
    }

    /// 저장해 둔 지문과 비교하므로 값이 달라지면 모든 사용자의 모든 기록이 다시 올라간다. 값을 고정한다.
    func testFingerprint_isPinned() {
        XCTAssertEqual(MealSyncPlanner.fingerprint(of: baseRecord()),
                       "9f9fa78fa6971f3da8e9d45a46d107fbb638c9478bbd5098513e82c30582ea59")
    }

    func testFingerprint_withNewerFieldsIsPinned() {
        var record = baseRecord()
        record.place = MealPlace(latitude: 37.5, longitude: 127, name: "집")
        record.portion = .half
        record.startedAt = t0
        record.finishedAt = t0.addingTimeInterval(1500)
        XCTAssertEqual(MealSyncPlanner.fingerprint(of: record),
                       "2b9acba77685e7e84b104a56c93fabdd2f6441c12684a3c9ce4139c84441b90d")
    }

    func testFingerprint_changesWhenAnythingSyncedChanges() {
        let base = MealSyncPlanner.fingerprint(of: baseRecord())
        let edits: [(inout MealRecord) -> Void] = [
            { $0.memo = "other" }, { $0.beforeImageData = Data([1]) }, { $0.afterImageData = Data([1]) },
            { $0.recordedWithoutPhoto = true }, { $0.hidePhotoCountBadge = true }, { $0.ateAll = false },
            { $0.capturedAt = nil }, { $0.portion = .little }, { $0.place = MealPlace(latitude: 1, longitude: 2) },
            { $0.finishedAt = Date(timeIntervalSince1970: 5) },
        ]
        for (index, edit) in edits.enumerated() {
            var record = baseRecord()
            edit(&record)
            XCTAssertNotEqual(MealSyncPlanner.fingerprint(of: record), base, "바꿔도 지문이 같다: \(index)")
        }
    }

    func testHexDigest_matchesKnownSHA256() {
        XCTAssertEqual(MealSyncPlanner.hexDigest(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: 사진 채우기

    func testFillingPhotos_keepsBothSidesPhotos() {
        let a = MealRecord(date: t0, mealType: .lunch, beforeImageData: Data([1]), memo: "A")
        let b = MealRecord(date: t0, mealType: .lunch, beforeImageData: Data([7]), afterImageData: Data([2]), memo: "B")
        let filled = MealSyncPlanner.fillingPhotos(of: a, from: b)
        XCTAssertEqual(filled.beforeImageData, Data([1]), "있는 사진은 바꾸지 않는다")
        XCTAssertEqual(filled.afterImageData, Data([2]))
        XCTAssertEqual(filled.memo, "A")
        XCTAssertEqual(filled.id, a.id)
        XCTAssertNil(MealSyncPlanner.fillingPhotos(of: a, from: nil).afterImageData)
    }

    // MARK: 칸 이름

    func testSlotName_roundTrips() throws {
        let name = MealSyncPlanner.slotName(album: "diet", day: "2026-11-20", mealType: .snack2)
        XCTAssertEqual(name, "meal_diet_2026-11-20_snack2", "서버에 있는 레코드 이름이다 — 바꾸면 기존 백업과 끊긴다")
        let parsed = try XCTUnwrap(MealSyncPlanner.parseSlotName(name))
        XCTAssertEqual(parsed.album, "diet")
        XCTAssertEqual(parsed.day, "2026-11-20")
        XCTAssertEqual(parsed.mealType, .snack2)
    }

    func testSlotName_rejectsWhatItDoesNotKnow() {
        XCTAssertNil(MealSyncPlanner.parseSlotName("meal_diet_2026-11-20_brunch"), "새 버전이 만든 모르는 끼니는 건너뛴다")
        XCTAssertNil(MealSyncPlanner.parseSlotName("meal_diet_notaday_lunch"))
        XCTAssertNil(MealSyncPlanner.parseSlotName("habit_2026-11-20"))
        XCTAssertNil(MealSyncPlanner.parseSlotName("meal_diet_2026-11-20_점심"), "표시용 이름이 아니라 케이스 이름이다")
    }

    /// 기기에 저장해 둔 상태를 새 코드가 그대로 읽는지 (칸 이름이 바뀌면 전부 처음 보는 것이 되어 다시 올라간다)
    func testSlotState_decodesStoredShape() throws {
        let json = #"{"fingerprint":"abc","modifiedAt":700000000,"isDirty":true,"isDeleted":false,"systemFields":"AQI="}"#
        let state = try JSONDecoder().decode(MealSyncSlotState.self, from: Data(json.utf8))
        XCTAssertEqual(state, MealSyncSlotState(fingerprint: "abc", modifiedAt: Date(timeIntervalSinceReferenceDate: 700_000_000),
                                                isDirty: true, isDeleted: false, systemFields: Data([1, 2])))
        let bare = try JSONDecoder().decode(MealSyncSlotState.self, from: Data(#"{"modifiedAt":0,"isDirty":false,"isDeleted":false}"#.utf8))
        XCTAssertNil(bare.fingerprint)
        XCTAssertNil(bare.systemFields)
    }
}
