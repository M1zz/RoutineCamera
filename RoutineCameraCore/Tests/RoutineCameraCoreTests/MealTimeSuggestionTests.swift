import XCTest
@testable import RoutineCameraCore

final class MealTimeSuggestionTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testCapturedAt_currentMealToday_isNow() {
        let now = date(19, 12, 40)
        XCTAssertEqual(MealTimeSuggestion.capturedAt(day: now, mealType: .lunch, now: now, calendar: calendar), now)
    }

    /// 점심을 깜빡하고 저녁 7시에 남기면 오늘 12시로 제안한다
    func testCapturedAt_forgottenMealToday_isTypicalHour() {
        let now = date(19, 19, 5)
        XCTAssertEqual(MealTimeSuggestion.capturedAt(day: now, mealType: .lunch, now: now, calendar: calendar),
                       date(19, 12))
    }

    func testCapturedAt_pastDay_isTypicalHour() {
        let now = date(19, 9)
        XCTAssertEqual(MealTimeSuggestion.capturedAt(day: date(17, 0), mealType: .dinner, now: now, calendar: calendar),
                       date(17, 18))
    }

    /// 아침 9시에 저녁을 남기면 미래 시각(18시) 대신 지금
    func testCapturedAt_laterMealToday_isClampedToNow() {
        let now = date(19, 9)
        XCTAssertEqual(MealTimeSuggestion.capturedAt(day: now, mealType: .dinner, now: now, calendar: calendar), now)
    }

    func testCombine_usesDayAndTimeOfDay() {
        let now = date(19, 20)
        let combined = MealTimeSuggestion.combine(day: date(18, 0), time: date(19, 13, 25), now: now, calendar: calendar)
        XCTAssertEqual(combined, date(18, 13, 25))
    }

    func testCombine_futureIsClampedToNow() {
        let now = date(19, 10)
        XCTAssertEqual(MealTimeSuggestion.combine(day: now, time: date(19, 15), now: now, calendar: calendar), now)
    }

}
