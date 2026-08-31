import XCTest
@testable import RoutineCameraCore

final class WidgetSharedStateTests: XCTestCase {

    // 2026-07-26 12:30 (점심 시간대)
    private let now = Date(timeIntervalSince1970: 1_785_000_000)

    private func snapshot(todayCount: Int,
                          inProgress: String? = nil,
                          since: Date? = nil,
                          needsRecord: Int = 0) -> WidgetSnapshot {
        WidgetSnapshot(todayCount: todayCount,
                       inProgressMealType: inProgress,
                       inProgressSince: since,
                       needsRecordCount: needsRecord,
                       generatedAt: now)
    }

    func testResolve_noSnapshot_usesFallbackCountPlusPending() {
        let state = WidgetStateResolver.resolve(
            snapshot: nil,
            pending: [PendingAteAll(mealType: "점심", date: now.timeIntervalSince1970)],
            fallbackTodayCount: 2,
            now: now)
        XCTAssertEqual(state.todayCount, 3)
        XCTAssertNil(state.inProgressMeal)
    }

    func testResolve_inProgressShownWhenNothingPending() {
        let state = WidgetStateResolver.resolve(
            snapshot: snapshot(todayCount: 1, inProgress: "점심", since: now, needsRecord: 2),
            pending: [],
            now: now)
        XCTAssertEqual(state.todayCount, 1)
        XCTAssertEqual(state.inProgressMeal, "점심")
        XCTAssertEqual(state.needsRecordCount, 2)
    }

    func testResolve_pendingOnInProgressMeal_clearsEatingAndKeepsCount() {
        // 버튼을 누른 직후: "먹는 중"이 사라지고, 기존 기록을 마감하는 것이라 개수는 그대로
        let state = WidgetStateResolver.resolve(
            snapshot: snapshot(todayCount: 3, inProgress: "점심", since: now),
            pending: [PendingAteAll(mealType: "점심", date: now.timeIntervalSince1970)],
            now: now)
        XCTAssertNil(state.inProgressMeal)
        XCTAssertEqual(state.todayCount, 3)
    }

    func testResolve_pendingOnOtherMeal_addsToCountAndKeepsEating() {
        let state = WidgetStateResolver.resolve(
            snapshot: snapshot(todayCount: 3, inProgress: "점심", since: now),
            pending: [PendingAteAll(mealType: "저녁", date: now.timeIntervalSince1970)],
            now: now)
        XCTAssertEqual(state.inProgressMeal, "점심")
        XCTAssertEqual(state.todayCount, 4)
    }

    func testResolve_ignoresPendingFromOtherDays() {
        let yesterday = now.addingTimeInterval(-24 * 60 * 60)
        let state = WidgetStateResolver.resolve(
            snapshot: snapshot(todayCount: 1),
            pending: [PendingAteAll(mealType: "점심", date: yesterday.timeIntervalSince1970)],
            now: now)
        XCTAssertEqual(state.todayCount, 1)
    }

    func testPendingItem_attachesToInProgressMealAndItsDay() {
        // 어제 밤에 식전만 찍고 아직 마감 안 된 기록이라도, 대기열은 그 기록의 날짜로 붙어야 한다
        let since = now.addingTimeInterval(-2 * 60 * 60)
        let item = WidgetStateResolver.pendingItem(
            snapshot: snapshot(todayCount: 1, inProgress: "아침", since: since),
            now: now)
        XCTAssertEqual(item.mealType, "아침")
        XCTAssertEqual(item.date, since.timeIntervalSince1970)
    }

    func testPendingItem_withoutInProgress_usesInferredMealAtNow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let item = WidgetStateResolver.pendingItem(snapshot: snapshot(todayCount: 0),
                                                  now: now,
                                                  calendar: cal)
        XCTAssertEqual(item.mealType, MealType.inferred(at: now, calendar: cal).rawValue)
        XCTAssertEqual(item.date, now.timeIntervalSince1970)
    }

    /// 앱이 쓰는 JSON(필드명)과 위젯이 읽는 스냅샷 타입이 어긋나면 위젯이 조용히 빈 상태가 된다.
    /// 앱의 WidgetSnapshot 인코딩 결과와 동일한 JSON을 디코딩해 계약을 고정한다.
    func testSnapshot_decodesAppSideJSON() throws {
        let json = """
        {"todayCount":2,"inProgressMealType":"점심","inProgressSince":806000000,
         "lastRecordedAt":806000001,"needsRecordCount":1,"generatedAt":806000002}
        """.data(using: .utf8)!
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: json)
        XCTAssertEqual(snap.todayCount, 2)
        XCTAssertEqual(snap.inProgressMealType, "점심")
        XCTAssertEqual(snap.needsRecordCount, 1)
        XCTAssertNotNil(snap.inProgressSince)
    }

    /// 옵셔널 필드가 빠진 JSON(앱이 nil을 인코딩하지 않는 경우)도 디코딩돼야 한다.
    func testSnapshot_decodesWithoutOptionalFields() throws {
        let json = """
        {"todayCount":0,"needsRecordCount":0,"generatedAt":806000002}
        """.data(using: .utf8)!
        let snap = try JSONDecoder().decode(WidgetSnapshot.self, from: json)
        XCTAssertEqual(snap.todayCount, 0)
        XCTAssertNil(snap.inProgressMealType)
        XCTAssertNil(snap.lastRecordedAt)
    }
}
