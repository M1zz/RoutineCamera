import XCTest
@testable import RoutineCameraCore

final class MealRecordTests: XCTestCase {

    func testIsComplete_combinations() {
        let d = Date()
        XCTAssertTrue(MealRecord(date: d, mealType: .lunch, beforeImageData: Data([1])).isComplete)
        XCTAssertTrue(MealRecord(date: d, mealType: .lunch, afterImageData: Data([1])).isComplete)
        XCTAssertTrue(MealRecord(date: d, mealType: .lunch, recordedWithoutPhoto: true).isComplete)
        XCTAssertTrue(MealRecord(date: d, mealType: .lunch, ateAll: true).isComplete)
        XCTAssertFalse(MealRecord(date: d, mealType: .lunch).isComplete)
    }

    func testEatingInProgress() {
        let d = Date()
        XCTAssertTrue(MealRecord(date: d, mealType: .lunch, beforeImageData: Data([1])).isEatingInProgress)
        // 식후가 있으면 진행 중 아님
        XCTAssertFalse(MealRecord(date: d, mealType: .lunch, beforeImageData: Data([1]), afterImageData: Data([2])).isEatingInProgress)
        // 다 먹음이면 진행 중 아님
        XCTAssertFalse(MealRecord(date: d, mealType: .lunch, beforeImageData: Data([1]), ateAll: true).isEatingInProgress)
    }

    func testEatingInProgress_onlyCountsAsInProgressOnTheSameDay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-24 * 60 * 60)

        // 오늘 남긴 식전만 있는 기록 → "먹는 중"
        let today = MealRecord(date: now, mealType: .lunch, beforeImageData: Data([1]), capturedAt: now)
        XCTAssertTrue(today.isEatingInProgress(asOf: now))
        XCTAssertFalse(today.needsRecordCompletion(asOf: now))

        // 날이 지난 미마감 기록 → "기록 필요"
        let stale = MealRecord(date: yesterday, mealType: .lunch, beforeImageData: Data([1]), capturedAt: yesterday)
        XCTAssertFalse(stale.isEatingInProgress(asOf: now))
        XCTAssertTrue(stale.needsRecordCompletion(asOf: now))

        // 마감된 기록은 날짜와 무관하게 둘 다 아님
        let done = MealRecord(date: yesterday, mealType: .lunch, beforeImageData: Data([1]), afterImageData: Data([2]), capturedAt: yesterday)
        XCTAssertFalse(done.isEatingInProgress(asOf: now))
        XCTAssertFalse(done.needsRecordCompletion(asOf: now))
    }

    func testHasBeforeAfterComparison() {
        let d = Date()
        XCTAssertTrue(MealRecord(date: d, mealType: .lunch, beforeImageData: Data([1]), afterImageData: Data([2])).hasBeforeAfterComparison)
        XCTAssertFalse(MealRecord(date: d, mealType: .lunch, beforeImageData: Data([1])).hasBeforeAfterComparison)
    }

    func testCodableRoundTrip_preservesNewFields() throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let original = MealRecord(date: Date(), mealType: .dinner, beforeImageData: Data([9]), memo: "맛있음", capturedAt: stamp, ateAll: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealRecord.self, from: data)
        XCTAssertEqual(decoded.mealType, .dinner)
        XCTAssertEqual(decoded.memo, "맛있음")
        XCTAssertEqual(decoded.capturedAt, stamp)
        XCTAssertTrue(decoded.ateAll)
        XCTAssertEqual(decoded.beforeImageData, Data([9]))
    }

    func testDecode_backwardCompat_missingNewFields() throws {
        // 구버전 데이터: capturedAt / ateAll / recordedWithoutPhoto 없음
        let json = """
        {"id":"\(UUID().uuidString)","date":0,"mealType":"점심"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MealRecord.self, from: json)
        XCTAssertEqual(decoded.mealType, .lunch)
        XCTAssertNil(decoded.capturedAt)
        XCTAssertFalse(decoded.ateAll)
        XCTAssertFalse(decoded.recordedWithoutPhoto)
    }

    func testPendingAteAll_roundTrip() throws {
        let items = [PendingAteAll(mealType: "점심", date: 123), PendingAteAll(mealType: "저녁", date: 456)]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([PendingAteAll].self, from: data)
        XCTAssertEqual(decoded, items)
    }

    // MARK: - 앱에서 옮겨 온 것 (찍은 곳 · 사진 교체 · 피드 자리 · 예전 데이터)

    func testPlace_roundTrips() throws {
        let record = MealRecord(date: Date(), mealType: .dinner, beforeImageData: Data([1]),
                                place: MealPlace(latitude: 37.5, longitude: 127.0, name: "서울"))
        let decoded = try JSONDecoder().decode(MealRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.place, record.place)
        XCTAssertEqual(decoded.id, record.id)
    }

    func testReplacingImages_keepsIdentityAndFields() {
        let record = MealRecord(date: Date(), mealType: .lunch, beforeImageData: Data([1]), memo: "메모",
                                capturedAt: Date(), ateAll: true, place: MealPlace(latitude: 1, longitude: 2))
        let copy = record.replacingImages(before: nil, after: Data([9]))
        XCTAssertEqual(copy.id, record.id)
        XCTAssertNil(copy.beforeImageData)
        XCTAssertEqual(copy.afterImageData, Data([9]))
        XCTAssertEqual(copy.memo, "메모")
        XCTAssertEqual(copy.capturedAt, record.capturedAt)
        XCTAssertTrue(copy.ateAll)
        XCTAssertEqual(copy.place, record.place)
    }

    func testFeedDate_usesCapturedAtElseTypicalHour() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day = cal.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        let noTime = MealRecord(date: day, mealType: .dinner)
        XCTAssertEqual(cal.component(.hour, from: noTime.feedDate(calendar: cal)), 18)
        let shot = day.addingTimeInterval(13 * 3600 + 120)
        XCTAssertEqual(MealRecord(date: day, mealType: .dinner, capturedAt: shot).feedDate(calendar: cal), shot)
    }

    /// 예전 버전이 남긴 기록(OpenAI 표시 · 찍은 곳 없음)도 그대로 읽힌다
    func testDecodesLegacyJSON() throws {
        let json = """
        {"id":"8F6A3C1E-0000-4000-8000-000000000001","date":0,"mealType":"점심",
         "visionAnalysis":{"foodItems":["밥"],"extractedText":[],"confidence":0.5,"analyzedDate":0,
                           "isOpenAI":true,"description":"예전 설명"}}
        """
        let record = try JSONDecoder().decode(MealRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.mealType, .lunch)
        XCTAssertNil(record.place)
        XCTAssertFalse(record.ateAll)
        XCTAssertEqual(record.visionAnalysis?.description, "예전 설명")
    }
}
