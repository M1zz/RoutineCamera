import XCTest
@testable import RoutineCameraCore

final class MealPaceTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func meal(_ type: MealType, minutes: Double?) -> MealRecord {
        MealRecord(date: start, mealType: type, beforeImageData: Data([1]), ateAll: true,
                   startedAt: minutes == nil ? nil : start,
                   finishedAt: minutes.map { start.addingTimeInterval($0 * 60) })
    }

    func testMinutes_roundsAndRejectsUntrustedLengths() {
        XCTAssertEqual(MealPace.minutes(from: start, to: start.addingTimeInterval(14 * 60 + 40)), 15)
        // 사진 두 장을 이어 남긴 것
        XCTAssertNil(MealPace.minutes(from: start, to: start.addingTimeInterval(30)))
        // 마감을 잊었다가 뒤늦게 누른 것
        XCTAssertNil(MealPace.minutes(from: start, to: start.addingTimeInterval(3 * 3600)))
        XCTAssertNil(MealPace.minutes(from: start, to: start.addingTimeInterval(-60)))
        XCTAssertNil(MealPace.minutes(from: nil, to: start))
        XCTAssertNil(MealPace.minutes(from: start, to: nil))
    }

    func testElapsedMinutes() {
        XCTAssertEqual(MealPace.elapsedMinutes(since: start, now: start.addingTimeInterval(8 * 60 + 50)), 8)
        XCTAssertNil(MealPace.elapsedMinutes(since: start, now: start.addingTimeInterval(5 * 3600)))
        XCTAssertNil(MealPace.elapsedMinutes(since: nil, now: start))
    }

    func testSummary_usesMedianAndSkipsUntimedMeals() {
        let records = [meal(.breakfast, minutes: 8), meal(.lunch, minutes: 12), meal(.lunch, minutes: 16),
                       meal(.dinner, minutes: 90), meal(.dinner, minutes: nil)]
        let summary = MealPace.summary(of: records)
        XCTAssertEqual(summary?.mealCount, 4)
        XCTAssertEqual(summary?.usualMinutes, 14)          // 8, 12, 16, 90 의 가운데 — 회식 한 번에 끌려가지 않는다
        XCTAssertEqual(summary?.usualByMeal[.lunch], 14)
        XCTAssertEqual(summary?.usualByMeal[.breakfast], 8)
        XCTAssertEqual(summary?.unhurriedCount, 1)
        XCTAssertEqual(summary?.minutesToSlowDown, 6)
        XCTAssertEqual(summary?.isUnhurried, false)
    }

    func testSummary_nilWhenNothingTimed() {
        XCTAssertNil(MealPace.summary(of: [meal(.lunch, minutes: nil)]))
    }

    func testSummary_unhurriedWhenUsualReachesRecommendation() {
        let summary = MealPace.summary(of: [meal(.lunch, minutes: 22), meal(.dinner, minutes: 25)])
        XCTAssertEqual(summary?.minutesToSlowDown, 0)
        XCTAssertEqual(summary?.isUnhurried, true)
    }

    func testRecord_decodesWithoutPaceFields() throws {
        // 예전 버전이 저장한 기록 (시작 · 끝 시각 없음)
        let old = MealRecord(date: start, mealType: .lunch, beforeImageData: Data([1]))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "startedAt"); json.removeValue(forKey: "finishedAt")
        let decoded = try JSONDecoder().decode(MealRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.eatingMinutes)

        let timed = meal(.lunch, minutes: 18)
        let roundTrip = try JSONDecoder().decode(MealRecord.self, from: JSONEncoder().encode(timed))
        XCTAssertEqual(roundTrip.eatingMinutes, 18)
        XCTAssertEqual(roundTrip.replacingImages(before: nil, after: nil).eatingMinutes, 18)
    }
}
