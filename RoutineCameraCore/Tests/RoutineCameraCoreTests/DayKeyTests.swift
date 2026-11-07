import XCTest
@testable import RoutineCameraCore

final class DayKeyTests: XCTestCase {
    func testRoundTrip() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 13))!
        XCTAssertEqual(DayKey.string(from: date), "2026-11-07")
        XCTAssertEqual(DayKey.date(from: "2026-11-07"), cal.startOfDay(for: date))
    }

    /// 사용자 달력이 불기여도 열쇠는 그레고리력 숫자다 — 만들 때와 읽을 때가 같아야 한다
    func testIgnoresUserCalendar() {
        let buddhist = DateFormatter()
        buddhist.calendar = Calendar(identifier: .buddhist)
        buddhist.dateFormat = "yyyy-MM-dd"
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        XCTAssertNotEqual(buddhist.string(from: date), DayKey.string(from: date))
        XCTAssertEqual(DayKey.string(from: DayKey.date(from: DayKey.string(from: date))!), DayKey.string(from: date))
    }

    func testRejectsMalformed() {
        XCTAssertNil(DayKey.date(from: "lunch"))
        XCTAssertNil(DayKey.date(from: ""))
    }
}
