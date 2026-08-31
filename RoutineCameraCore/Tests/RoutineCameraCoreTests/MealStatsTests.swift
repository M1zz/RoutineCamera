import XCTest
@testable import RoutineCameraCore

final class MealStatsTests: XCTestCase {

    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    private func rec(_ date: Date, _ type: MealType = .breakfast, complete: Bool = true) -> MealRecord {
        MealRecord(date: date, mealType: type, beforeImageData: complete ? Data([1]) : nil)
    }

    // MARK: isDayRecorded

    func testIsDayRecorded_anyMealCounts() {
        let recs = [rec(today, .lunch)]
        XCTAssertTrue(MealStats.isDayRecorded(today, in: recs))
        XCTAssertFalse(MealStats.isDayRecorded(day(-1), in: recs))
    }

    func testIsDayRecorded_incompleteDoesNotCount() {
        let recs = [rec(today, .lunch, complete: false)]
        XCTAssertFalse(MealStats.isDayRecorded(today, in: recs))
    }

    func testIsDayRecorded_exerciseCountsAnySlot() {
        // 운동은 시각에 맞는 슬롯에 저장되므로 아침이든 저녁이든 그날 기록이면 인정
        XCTAssertTrue(MealStats.isDayRecorded(today, in: [rec(today, .breakfast)], exerciseMode: true))
        XCTAssertTrue(MealStats.isDayRecorded(today, in: [rec(today, .dinner)], exerciseMode: true))
        XCTAssertFalse(MealStats.isDayRecorded(today, in: [rec(today, .dinner, complete: false)], exerciseMode: true))
    }

    // MARK: currentStreak

    func testCurrentStreak_consecutive() {
        let recs = [rec(today), rec(day(-1)), rec(day(-2))]
        XCTAssertEqual(MealStats.currentStreak(records: recs, today: today), 3)
    }

    func testCurrentStreak_stopsAtGap() {
        let recs = [rec(today), rec(day(-1)), rec(day(-3))] // day(-2) 없음
        XCTAssertEqual(MealStats.currentStreak(records: recs, today: today), 2)
    }

    func testCurrentStreak_todayInProgressNotBroken() {
        // 오늘 미기록이어도 어제까지 이어졌으면 끊기지 않음
        let recs = [rec(day(-1)), rec(day(-2))]
        XCTAssertEqual(MealStats.currentStreak(records: recs, today: today), 2)
    }

    func testCurrentStreak_empty() {
        XCTAssertEqual(MealStats.currentStreak(records: [], today: today), 0)
    }

    // MARK: maxStreak

    func testMaxStreak() {
        // 연속 3 (day -10,-9,-8), 연속 2 (day -2,-1) → 최고 3
        let recs = [rec(day(-10)), rec(day(-9)), rec(day(-8)), rec(day(-2)), rec(day(-1))]
        XCTAssertEqual(MealStats.maxStreak(records: recs), 3)
    }

    func testMaxStreak_empty() {
        XCTAssertEqual(MealStats.maxStreak(records: []), 0)
    }

    // MARK: totalRecordedDays

    func testTotalRecordedDays_dedupsSameDay() {
        // 같은 날 3끼 → 1일로 카운트
        let recs = [rec(today, .breakfast), rec(today, .lunch), rec(today, .dinner), rec(day(-1))]
        XCTAssertEqual(MealStats.totalRecordedDays(records: recs), 2)
    }

    func testTotalRecordedDays_ignoresIncomplete() {
        let recs = [rec(today, .breakfast, complete: false)]
        XCTAssertEqual(MealStats.totalRecordedDays(records: recs), 0)
    }

    // MARK: feedSortValue

    func testFeedSortValue_usesCapturedAt() {
        var r = rec(today, .breakfast)
        let stamp = cal.date(byAdding: .hour, value: 20, to: today)!
        r.capturedAt = stamp
        XCTAssertEqual(MealStats.feedSortValue(r), stamp)
    }

    func testFeedSortValue_fallsBackToTypicalHour_breakfastBeforeDinner() {
        let b = rec(today, .breakfast)  // capturedAt 없음 → 08시
        let d = rec(today, .dinner)     // capturedAt 없음 → 18시
        XCTAssertLessThan(MealStats.feedSortValue(b), MealStats.feedSortValue(d))
    }
}
