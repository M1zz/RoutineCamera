import XCTest
@testable import RoutineCameraCore

/// 앱이 기록에서 위젯용 요약을 만드는 규칙.
final class WidgetSnapshotMakeTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func make(_ records: [MealRecord], cared: Set<MealType> = [.breakfast, .lunch, .dinner], now: Date) -> WidgetSnapshot {
        WidgetSnapshot.make(dietRecords: records, caredMeals: cared, now: now, calendar: calendar)
    }

    func testEmpty() {
        let snapshot = make([], now: at(20, 9))
        XCTAssertEqual(snapshot.todayCount, 0)
        XCTAssertNil(snapshot.inProgressMealType)
        XCTAssertEqual(snapshot.needsRecordCount, 0)
        XCTAssertEqual(snapshot.recordedMealTypes, [])
        XCTAssertEqual(snapshot.caredMealTypes, ["아침", "점심", "저녁"])
    }

    func testCountsTodayAndFindsTheMealInProgress() {
        let records = [
            MealRecord(date: at(20, 0), mealType: .breakfast, beforeImageData: Data([1]), afterImageData: Data([2]), capturedAt: at(20, 8)),
            MealRecord(date: at(20, 0), mealType: .lunch, beforeImageData: Data([1]), capturedAt: at(20, 12)),
            MealRecord(date: at(19, 0), mealType: .dinner, beforeImageData: Data([1]), capturedAt: at(19, 19)),
            MealRecord(date: at(20, 0), mealType: .dinner, memo: "빈 기록"),
        ]
        let snapshot = make(records, now: at(20, 13))
        XCTAssertEqual(snapshot.todayCount, 2)
        XCTAssertEqual(snapshot.inProgressMealType, "점심")
        XCTAssertEqual(snapshot.inProgressSince, at(20, 12))
        XCTAssertEqual(snapshot.lastRecordedAt, at(20, 12))
        XCTAssertEqual(snapshot.needsRecordCount, 1, "어제 식전만 남긴 저녁")
        XCTAssertEqual(Set(snapshot.recordedMealTypes ?? []), ["아침", "점심"])
    }

    /// 88b09f3 주변: 다 먹음으로 마친 끼니는 더는 "먹는 중" 이 아니다 (위젯 버튼이 사라져야 한다)
    func testFinishedMealIsNoLongerInProgress() {
        var ledger = MealLedger(calendar: calendar)
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: Data([1]), isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        XCTAssertEqual(make(ledger.records, now: at(20, 13)).inProgressMealType, "점심")
        ledger.recordAteAll(date: at(20, 12), mealType: .lunch, finishedAt: at(20, 13), now: at(20, 13))
        let snapshot = make(ledger.records, now: at(20, 13))
        XCTAssertNil(snapshot.inProgressMealType)
        XCTAssertEqual(snapshot.todayCount, 1)
    }

    func testCaredMealsKeepMealOrderAndDropSnacks() {
        XCTAssertEqual(make([], cared: [.dinner, .snack1, .breakfast], now: at(20, 9)).caredMealTypes, ["아침", "저녁"])
    }

    func testBackfilledYesterdayMealCountsForYesterdaysChecks() {
        // 어제 점심을 오늘 채우면: 먹은 시각은 어제라 오늘 수에 들지 않고, 오늘 체크에도 뜨지 않는다
        let record = MealRecord(date: at(19, 0), mealType: .lunch, recordedWithoutPhoto: true, capturedAt: at(19, 12))
        let snapshot = make([record], now: at(20, 9))
        XCTAssertEqual(snapshot.todayCount, 0)
        XCTAssertEqual(snapshot.recordedMealTypes, [])
    }

    func testContentSignature_sameContentSameDayDoesNotRedraw() {
        let records = [MealRecord(date: at(20, 0), mealType: .breakfast, capturedAt: at(20, 8), ateAll: true)]
        let morning = make(records, now: at(20, 9)).contentSignature(calendar: calendar)
        XCTAssertEqual(morning, make(records, now: at(20, 15)).contentSignature(calendar: calendar))
        XCTAssertNotEqual(morning, make(records, now: at(21, 9)).contentSignature(calendar: calendar), "날이 바뀌면 다시 그린다")
        XCTAssertNotEqual(morning, make([], now: at(20, 9)).contentSignature(calendar: calendar))
    }

    func testSnapshotRoundTripsThroughJSONForTheWidget() throws {
        let snapshot = make([MealRecord(date: at(20, 0), mealType: .lunch, beforeImageData: Data([1]), capturedAt: at(20, 12))], now: at(20, 13))
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
    }
}
