import XCTest
@testable import RoutineCameraCore

final class MealReminderPlannerTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private let slots = [
        MealReminderSlot(mealKey: "breakfast", hour: 8, minute: 0),
        MealReminderSlot(mealKey: "lunch", hour: 12, minute: 30),
        MealReminderSlot(mealKey: "dinner", hour: 18, minute: 0),
    ]

    func testFiresLeadMinutesBeforeMeal() {
        let plan = MealReminderPlanner.plan(slots: slots, leadMinutes: 10, now: date(10, 7, 0), calendar: calendar)
        XCTAssertEqual(plan.first?.mealKey, "breakfast")
        XCTAssertEqual(plan.first?.fireDate, date(10, 7, 50))
        XCTAssertEqual(plan.first?.mealTime, date(10, 8, 0))
    }

    func testLeadZero_firesAtMealTime() {
        let plan = MealReminderPlanner.plan(slots: slots, leadMinutes: 0, now: date(10, 7, 0), calendar: calendar)
        XCTAssertEqual(plan.first?.fireDate, date(10, 8, 0))
    }

    func testCoversEverySlotForEveryDay() {
        let plan = MealReminderPlanner.plan(slots: slots, leadMinutes: 10, now: date(10, 6, 0), days: 7, calendar: calendar)
        XCTAssertEqual(plan.count, 21)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, 21)
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())
    }

    func testPassedTimesToday_areSkippedNotFiredLate() {
        // 12:25 — 점심 알림(12:20)은 이미 지났다. 늦게라도 울리지 않고 내일로 넘어간다.
        let plan = MealReminderPlanner.plan(slots: slots, leadMinutes: 10, now: date(10, 12, 25), days: 2, calendar: calendar)
        XCTAssertEqual(plan.map(\.mealKey), ["dinner", "breakfast", "lunch", "dinner"])
        XCTAssertEqual(plan.first?.fireDate, date(10, 17, 50))
    }

    func testRecordedMeal_skipsOnlyToday() {
        let plan = MealReminderPlanner.plan(slots: slots, leadMinutes: 10, now: date(10, 7, 0), days: 2,
                                            recordedToday: ["breakfast"], calendar: calendar)
        let breakfasts = plan.filter { $0.mealKey == "breakfast" }
        XCTAssertEqual(breakfasts.map(\.fireDate), [date(11, 7, 50)])
        XCTAssertEqual(plan.filter { $0.mealKey == "lunch" }.count, 2)
    }

    func testIdentifier_isStablePerMealAndDay() {
        let id = MealReminderPlanner.identifier(mealKey: "lunch", day: date(3, 0, 0), calendar: calendar)
        XCTAssertEqual(id, "mealreminder-lunch-2026-09-03")
        XCTAssertTrue(id.hasPrefix(MealReminderPlanner.identifierPrefix))
    }

    func testNoSlots_planIsEmpty() {
        XCTAssertTrue(MealReminderPlanner.plan(slots: [], leadMinutes: 10, now: date(10, 7, 0), calendar: calendar).isEmpty)
    }
}
