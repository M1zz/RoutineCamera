import XCTest
@testable import RoutineCameraCore

final class MealTypeTests: XCTestCase {

    private func date(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 15; c.hour = hour; c.minute = 30
        return Calendar.current.date(from: c)!
    }

    func testInferredByHour() {
        XCTAssertEqual(MealType.inferred(at: date(hour: 7)), .breakfast)
        XCTAssertEqual(MealType.inferred(at: date(hour: 10)), .breakfast)
        XCTAssertEqual(MealType.inferred(at: date(hour: 11)), .lunch)
        XCTAssertEqual(MealType.inferred(at: date(hour: 15)), .lunch)
        XCTAssertEqual(MealType.inferred(at: date(hour: 16)), .dinner)
        XCTAssertEqual(MealType.inferred(at: date(hour: 21)), .dinner)
        XCTAssertEqual(MealType.inferred(at: date(hour: 23)), .snack1)
        XCTAssertEqual(MealType.inferred(at: date(hour: 3)), .snack1)
    }

    func testTypicalHourOrdering() {
        XCTAssertLessThan(MealType.breakfast.typicalHour, MealType.lunch.typicalHour)
        XCTAssertLessThan(MealType.lunch.typicalHour, MealType.dinner.typicalHour)
    }

    func testIsSnack() {
        XCTAssertFalse(MealType.breakfast.isSnack)
        XCTAssertFalse(MealType.lunch.isSnack)
        XCTAssertFalse(MealType.dinner.isSnack)
        XCTAssertTrue(MealType.snack1.isSnack)
        XCTAssertTrue(MealType.snack2.isSnack)
        XCTAssertTrue(MealType.snack3.isSnack)
    }

    func testRawValuesStable() {
        // rawValue는 저장/CloudKit 키에 쓰이므로 변경 금지
        XCTAssertEqual(MealType.breakfast.rawValue, "아침")
        XCTAssertEqual(MealType.lunch.rawValue, "점심")
        XCTAssertEqual(MealType.dinner.rawValue, "저녁")
        XCTAssertEqual(MealType.snack1.rawValue, "간식1")
    }
}
