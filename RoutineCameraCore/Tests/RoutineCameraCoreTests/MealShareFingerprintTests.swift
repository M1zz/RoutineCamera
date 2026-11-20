import XCTest
@testable import RoutineCameraCore

/// 친구 공유: 지문이 달라진 날만 다시 올린다.
final class MealShareFingerprintTests: XCTestCase {

    private let day1 = Date(timeIntervalSince1970: 1_790_000_000)
    private var day2: Date { day1.addingTimeInterval(86_400) }

    private func records() -> [MealRecord] {
        [MealRecord(date: day1, mealType: .lunch, beforeImageData: Data([1, 2]), memo: "a", capturedAt: day1),
         MealRecord(date: day1, mealType: .dinner, capturedAt: day1, ateAll: true),
         MealRecord(date: day2, mealType: .breakfast, afterImageData: Data([3]), capturedAt: day2)]
    }

    func testByDay_groupsByCalendarDay() {
        let prints = MealShareFingerprint.byDay(records())
        XCTAssertEqual(Set(prints.keys), [DayKey.string(from: day1), DayKey.string(from: day2)])
    }

    /// ad6cf9d: 실행마다 값이 달라지는 해시를 써서 앱을 켤 때마다 모든 날짜가 다시 올라갔다.
    /// 같은 기록이면 언제 · 어떤 순서로 계산해도 같은 값이어야 한다.
    func testRegression_fingerprintIsStableAcrossRunsAndOrder() {
        let a = MealShareFingerprint.byDay(records())
        let b = MealShareFingerprint.byDay(records().reversed().map { $0.replacingImages(before: $0.beforeImageData, after: $0.afterImageData) })
        XCTAssertEqual(a, b)

        // 프로세스가 달라도 같아야 하므로 값 자체를 고정한다 (id 와 날짜에 기대지 않는 한 끼)
        let fixed = [MealRecord(date: day1, mealType: .lunch, beforeImageData: Data([1, 2]), memo: "a",
                                capturedAt: Date(timeIntervalSince1970: 1_700_000_000), ateAll: true)]
        XCTAssertEqual(MealShareFingerprint.byDay(fixed).values.first, PINNED_SHARE_FINGERPRINT)
    }

    func testChangedDays_onlyTheDayThatChanged() {
        let stored = MealShareFingerprint.byDay(records())
        var edited = records()
        edited[2].memo = "고침"
        let changed = MealShareFingerprint.changedDays(current: MealShareFingerprint.byDay(edited), stored: stored)
        XCTAssertEqual(changed, [DayKey.string(from: day2)])
    }

    func testChangedDays_nothingWhenNothingChanged() {
        let prints = MealShareFingerprint.byDay(records())
        XCTAssertTrue(MealShareFingerprint.changedDays(current: prints, stored: prints).isEmpty)
    }

    func testChangedDays_dayWithAllRecordsDeletedIsUploadedSoTheServerDeletesIt() {
        let stored = MealShareFingerprint.byDay(records())
        let remaining = records().filter { $0.mealType != .breakfast }
        XCTAssertEqual(MealShareFingerprint.changedDays(current: MealShareFingerprint.byDay(remaining), stored: stored),
                       [DayKey.string(from: day2)])
    }

    func testChangedDays_newDayAndPhotoSizeChange() {
        let stored = MealShareFingerprint.byDay([records()[0]])
        var edited = records()
        edited[0].beforeImageData = Data([1, 2, 3])
        XCTAssertEqual(MealShareFingerprint.changedDays(current: MealShareFingerprint.byDay(edited), stored: stored),
                       [DayKey.string(from: day1), DayKey.string(from: day2)])
    }

    func testFingerprint_ignoresWhatFriendsNeverSee() {
        // 찍은 곳 · 먹은 양은 친구에게 올리지 않는다 — 고쳐도 다시 올릴 이유가 없다
        var edited = records()
        edited[0].place = MealPlace(latitude: 1, longitude: 2)
        edited[0].portion = .half
        XCTAssertEqual(MealShareFingerprint.byDay(edited), MealShareFingerprint.byDay(records()))
    }
}

private let PINNED_SHARE_FINGERPRINT = -4_387_882_548_777_793_102
