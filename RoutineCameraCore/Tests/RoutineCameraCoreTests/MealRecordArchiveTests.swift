import XCTest
@testable import RoutineCameraCore

/// 저장 → 다시 읽기. 기록과 사진을 잃지 않는 것이 이 앱에서 가장 중요하다.
final class MealRecordArchiveTests: XCTestCase {

    private var directory: URL!
    private var store: MealImageFileStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)", isDirectory: true)
        store = MealImageFileStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let day = Date(timeIntervalSince1970: 1_790_000_000)
    private func bytes(_ seed: UInt8, count: Int = 5000) -> Data { Data(repeating: seed, count: count) }

    private func fullRecord() -> MealRecord {
        MealRecord(date: day, mealType: .lunch, beforeImageData: bytes(1), afterImageData: bytes(2), memo: "메모",
                   recordedWithoutPhoto: false, hidePhotoCountBadge: true,
                   visionAnalysis: VisionAnalysisData(foodItems: ["밥"], extractedText: [], confidence: 0.5, analyzedDate: day),
                   capturedAt: day.addingTimeInterval(60), ateAll: true,
                   place: MealPlace(latitude: 37.5, longitude: 127, name: "식당"), portion: .half,
                   startedAt: day.addingTimeInterval(60), finishedAt: day.addingTimeInterval(1500))
    }

    func testRoundTrip_keepsEveryField() throws {
        let original = fullRecord()
        let encoded = try MealRecordArchive.encode(records: [original], store: store)
        let decoded = try MealRecordArchive.decode(encoded.data, store: MealImageFileStore(directory: directory))

        XCTAssertFalse(decoded.hasInlinePhotos)
        XCTAssertTrue(decoded.unreadable.isEmpty)
        let read = try XCTUnwrap(decoded.records.first)
        XCTAssertEqual(read.id, original.id)
        XCTAssertEqual(read.date, original.date)
        XCTAssertEqual(read.mealType, original.mealType)
        XCTAssertEqual(read.beforeImageData, original.beforeImageData)
        XCTAssertEqual(read.afterImageData, original.afterImageData)
        XCTAssertEqual(read.memo, original.memo)
        XCTAssertEqual(read.hidePhotoCountBadge, original.hidePhotoCountBadge)
        XCTAssertEqual(read.visionAnalysis?.foodItems, ["밥"])
        XCTAssertEqual(read.capturedAt, original.capturedAt)
        XCTAssertEqual(read.ateAll, original.ateAll)
        XCTAssertEqual(read.place, original.place)
        XCTAssertEqual(read.portion, original.portion)
        XCTAssertEqual(read.startedAt, original.startedAt)
        XCTAssertEqual(read.finishedAt, original.finishedAt)
    }

    func testEncode_movesPhotoBytesOutOfTheJSON() throws {
        let encoded = try MealRecordArchive.encode(records: [fullRecord()], store: store)
        XCTAssertLessThan(encoded.data.count, 2000, "사진이 JSON 안에 남으면 저장할 때마다 수백 MB 를 쓴다")
        XCTAssertEqual(encoded.referenced.count, 2)
        XCTAssertTrue(encoded.keptInline.isEmpty)
        for name in encoded.referenced {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path))
        }
    }

    func testEncode_withoutStoreKeepsPhotosInline() throws {
        let original = fullRecord()
        let encoded = try MealRecordArchive.encode(records: [original], store: nil)
        let decoded = try MealRecordArchive.decode(encoded.data, store: nil)
        XCTAssertTrue(decoded.hasInlinePhotos)
        XCTAssertEqual(decoded.records.first?.beforeImageData, original.beforeImageData)
    }

    /// 예전 버전은 사진 바이트를 기록 안에 넣어 저장했다 — 그대로 읽히고, 다시 저장하면 파일로 옮겨져야 한다
    func testLegacyInlineFormat_isReadAndMigratedWithoutLoss() throws {
        let original = fullRecord()
        let legacy = try JSONEncoder().encode([original])   // 파일 이름 칸이 없는 옛 모양

        let decoded = try MealRecordArchive.decode(legacy, store: store)
        XCTAssertTrue(decoded.hasInlinePhotos)
        XCTAssertEqual(decoded.records.first?.afterImageData, original.afterImageData)

        let migrated = try MealRecordArchive.encode(records: decoded.records, store: store)
        let again = try MealRecordArchive.decode(migrated.data, store: MealImageFileStore(directory: directory))
        XCTAssertFalse(again.hasInlinePhotos)
        XCTAssertEqual(again.records.first?.beforeImageData, original.beforeImageData)
        XCTAssertEqual(again.records.first?.afterImageData, original.afterImageData)
    }

    /// 1.0 대 기록: 나중에 생긴 칸이 하나도 없다
    func testOldestRecordShape_decodesWithDefaults() throws {
        let json = """
        [{"id":"8C8B0F0E-1B1A-4C1D-9E1F-000000000001","date":790000000,"mealType":"점심"}]
        """
        let decoded = try MealRecordArchive.decode(Data(json.utf8), store: store)
        let record = try XCTUnwrap(decoded.records.first)
        XCTAssertEqual(record.mealType, .lunch)
        XCTAssertFalse(record.ateAll)
        XCTAssertFalse(record.recordedWithoutPhoto)
        XCTAssertNil(record.capturedAt)
        XCTAssertNil(record.portion)
        XCTAssertFalse(record.isComplete)
    }

    /// 새 버전이 더한 값을 옛 버전이 만나도 기록 전체를 못 읽게 되면 안 된다
    func testUnknownPortionValue_doesNotBreakTheWholeFile() throws {
        let json = """
        [{"id":"8C8B0F0E-1B1A-4C1D-9E1F-000000000002","date":790000000,"mealType":"저녁","ateAll":true,"portion":"double","futureField":{"a":1}}]
        """
        let decoded = try MealRecordArchive.decode(Data(json.utf8), store: store)
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertNil(decoded.records.first?.portion)
        XCTAssertEqual(decoded.records.first?.ateAll, true)
    }

    /// 5220c72: 못 읽은 저장값을 빈 목록으로 돌려주면 다음 저장이 원본을 덮는다 — 반드시 던져야 한다
    func testRegression_corruptDataThrowsInsteadOfLookingEmpty() {
        XCTAssertThrowsError(try MealRecordArchive.decode(Data("{not json".utf8), store: store))
        XCTAssertThrowsError(try MealRecordArchive.decode(Data(#"[{"id":"x"}]"#.utf8), store: store))
    }

    /// e8b77a1 · 5220c72: 사진 파일을 못 읽은 것은 지운 것이 아니다 — 다시 저장해도 참조와 파일이 남아야 한다
    func testRegression_unreadablePhotoKeepsItsReferenceAcrossSaves() throws {
        let original = fullRecord()
        let first = try MealRecordArchive.encode(records: [original], store: store)
        let beforeName = MealRecordArchive.slotName(for: original, kind: "before")

        // 사진 파일을 못 읽는 상황 (다른 폴더를 보는 보관소)
        let elsewhere = MealImageFileStore(directory: directory.appendingPathComponent("missing", isDirectory: true))
        let decoded = try MealRecordArchive.decode(first.data, store: elsewhere)
        XCTAssertNil(decoded.records.first?.beforeImageData)
        XCTAssertEqual(decoded.unreadable[beforeName], beforeName)
        XCTAssertEqual(decoded.unreadable.count, 2)

        // 그 상태로 메모만 고쳐 다시 저장
        var edited = decoded.records
        edited[0].memo = "고침"
        let second = try MealRecordArchive.encode(records: edited, store: store, unreadable: decoded.unreadable)
        XCTAssertEqual(second.referenced, first.referenced, "참조가 빠지면 정리 단계가 사진 파일을 지운다")
        XCTAssertEqual(store.removeFiles(keeping: second.referenced), 0)

        // 다음 실행에 사진이 돌아온다
        let recovered = try MealRecordArchive.decode(second.data, store: MealImageFileStore(directory: directory))
        XCTAssertEqual(recovered.records.first?.beforeImageData, original.beforeImageData)
        XCTAssertEqual(recovered.records.first?.afterImageData, original.afterImageData)
        XCTAssertEqual(recovered.records.first?.memo, "고침")
    }

    func testUnreadableWithoutPassingItBack_wouldDropTheReference() throws {
        // 위 테스트의 반대쪽: unreadable 을 넘기지 않으면 실제로 참조가 빠진다는 것 (규칙이 일을 하고 있다는 확인)
        let original = fullRecord()
        let first = try MealRecordArchive.encode(records: [original], store: store)
        let elsewhere = MealImageFileStore(directory: directory.appendingPathComponent("missing", isDirectory: true))
        let decoded = try MealRecordArchive.decode(first.data, store: elsewhere)
        let second = try MealRecordArchive.encode(records: decoded.records, store: store)
        XCTAssertTrue(second.referenced.isEmpty)
    }

    /// e8b77a1: 같은 날 같은 끼니 기록이 둘이면 사진 파일이 서로 덮였다 (재설치 뒤 사진 섞임)
    func testRegression_twoRecordsInTheSameSlotKeepSeparatePhotos() throws {
        let a = MealRecord(date: day, mealType: .lunch, beforeImageData: bytes(7))
        let b = MealRecord(date: day, mealType: .lunch, beforeImageData: bytes(8))
        let encoded = try MealRecordArchive.encode(records: [a, b], store: store)
        XCTAssertEqual(encoded.referenced.count, 2)

        let decoded = try MealRecordArchive.decode(encoded.data, store: MealImageFileStore(directory: directory))
        XCTAssertEqual(decoded.records.first { $0.id == a.id }?.beforeImageData, bytes(7))
        XCTAssertEqual(decoded.records.first { $0.id == b.id }?.beforeImageData, bytes(8))
    }

    func testDeletedPhoto_fileIsCleanedOnlyAfterItLeavesTheRecord() throws {
        var record = fullRecord()
        let first = try MealRecordArchive.encode(records: [record], store: store)
        XCTAssertEqual(store.removeFiles(keeping: first.referenced), 0)

        record.afterImageData = nil
        let second = try MealRecordArchive.encode(records: [record], store: store)
        XCTAssertEqual(second.referenced.count, 1)
        XCTAssertEqual(store.removeFiles(keeping: second.referenced), 1)
        let decoded = try MealRecordArchive.decode(second.data, store: MealImageFileStore(directory: directory))
        XCTAssertNil(decoded.records.first?.afterImageData)
        XCTAssertEqual(decoded.records.first?.beforeImageData, record.beforeImageData)
    }

    func testEmptyList_roundTrips() throws {
        let encoded = try MealRecordArchive.encode(records: [], store: store)
        XCTAssertTrue(try MealRecordArchive.decode(encoded.data, store: store).records.isEmpty)
    }

    func testSlotName_isStablePerDayMealAndKind() {
        let record = MealRecord(date: day, mealType: .snack2)
        XCTAssertEqual(MealRecordArchive.slotName(for: record, kind: "after"),
                       "\(DayKey.string(from: day))_snack2_after.jpg")
    }
}
