import XCTest
@testable import RoutineCameraCore

final class HabitsTests: XCTestCase {
    private let cal = Calendar.current

    private func day(_ offset: Int, from base: Date = Date()) -> Date {
        cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: base))!
    }

    private func logs(_ offsets: [Int], stamp: String = "fish") -> [String: DayLog] {
        Dictionary(uniqueKeysWithValues: offsets.map { (DayKey.string(from: day($0)), DayLog(stamps: [stamp])) })
    }

    func testDefaults_haveUniqueIDsAndAreInCatalog() {
        XCTAssertEqual(Set(Stamp.catalog.map(\.id)).count, Stamp.catalog.count)
        XCTAssertTrue(Stamp.defaults.allSatisfy { d in Stamp.catalog.contains(d) })
        XCTAssertFalse(Stamp.defaults.contains { $0.isCustom })
    }

    func testCustomStamp_isMarkedCustom() {
        let stamp = Stamp.custom(symbol: "🍣", name: "초밥", kind: .more)
        XCTAssertTrue(stamp.isCustom)
        XCTAssertEqual(stamp.name, "초밥")
    }

    func testDayLog_roundTripsAndEncodesStably() throws {
        let log = DayLog(stamps: ["nuts", "fish", "avocado"], water: 6, caffeine: 2)
        let a = try JSONEncoder().encode(log)
        let b = try JSONEncoder().encode(DayLog(stamps: ["avocado", "nuts", "fish"], water: 6, caffeine: 2))
        XCTAssertEqual(a, b, "같은 내용은 같은 바이트여야 동기화 지문이 흔들리지 않는다")
        XCTAssertEqual(try JSONDecoder().decode(DayLog.self, from: a), log)
    }

    func testDayLog_decodesMissingFields() throws {
        let log = try JSONDecoder().decode(DayLog.self, from: Data(#"{"water":3}"#.utf8))
        XCTAssertEqual(log, DayLog(water: 3))
    }

    func testClampedCups() {
        XCTAssertEqual(DayLog.clampedCups(-1), 0)
        XCTAssertEqual(DayLog.clampedCups(8), 8)
        XCTAssertEqual(DayLog.clampedCups(99), 30)
    }

    func testCurrentStreak_countsThroughToday() {
        XCTAssertEqual(HabitStats.currentStreak(of: "fish", in: logs([0, -1, -2, -4])), 3)
    }

    func testCurrentStreak_todayNotYetStamped_countsFromYesterday() {
        XCTAssertEqual(HabitStats.currentStreak(of: "fish", in: logs([-1, -2])), 2)
    }

    func testCurrentStreak_brokenYesterday_isZero() {
        XCTAssertEqual(HabitStats.currentStreak(of: "fish", in: logs([-2, -3])), 0)
        XCTAssertEqual(HabitStats.currentStreak(of: "nuts", in: logs([0, -1])), 0)
    }

    func testLongestStreak() {
        XCTAssertEqual(HabitStats.longestStreak(of: "fish", in: logs([0, -3, -4, -5, -6, -9, -10])), 4)
        XCTAssertEqual(HabitStats.longestStreak(of: "fish", in: [:]), 0)
    }

    func testCount_onlyInsideRange() {
        let all = logs([0, -1, -5, -40])
        XCTAssertEqual(HabitStats.count(of: "fish", in: all, from: day(-6), to: day(0)), 3)
    }

    func testPortionCounts_ignoresUnmarkedMeals() {
        let records = [
            MealRecord(date: day(0), mealType: .lunch, portion: .half),
            MealRecord(date: day(0), mealType: .dinner, portion: .half),
            MealRecord(date: day(-1), mealType: .lunch, portion: .all),
            MealRecord(date: day(-1), mealType: .dinner),
        ]
        XCTAssertEqual(HabitStats.portionCounts(of: records), [.half: 2, .all: 1])
    }

    func testMealRecord_portionRoundTripsAndUnknownValueIsDropped() throws {
        let record = MealRecord(date: day(0), mealType: .lunch, ateAll: true, portion: .little)
        let decoded = try JSONDecoder().decode(MealRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.portion, .little)
        XCTAssertEqual(record.replacingImages(before: nil, after: nil).portion, .little)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        json["portion"] = "quarter"
        let future = try JSONDecoder().decode(MealRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(future.portion)
        XCTAssertTrue(future.ateAll, "모르는 양 때문에 기록 전체를 버리지 않는다")
    }
}
