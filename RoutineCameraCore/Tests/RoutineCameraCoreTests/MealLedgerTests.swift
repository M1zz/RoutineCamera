import XCTest
@testable import RoutineCameraCore

/// 기록 장부의 규칙. 실제로 났던 버그는 "되돌아오면 깨지는 테스트" 로 남긴다 (이름에 고친 커밋을 적는다).
final class MealLedgerTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func ledger(_ records: [MealRecord] = []) -> MealLedger {
        MealLedger(records: records, calendar: calendar)
    }

    private let photo = Data([1, 2, 3])
    private let other = Data([9, 9])

    // MARK: 어느 칸에 들어가나

    func testRecordableMealType_followsTimeOfDayWhenSlotIsFree() {
        XCTAssertEqual(ledger().recordableMealType(at: at(20, 8)), .breakfast)
        XCTAssertEqual(ledger().recordableMealType(at: at(20, 12, 30)), .lunch)
        XCTAssertEqual(ledger().recordableMealType(at: at(20, 19)), .dinner)
        XCTAssertEqual(ledger().recordableMealType(at: at(20, 23)), .snack3)
        XCTAssertEqual(ledger().recordableMealType(at: at(20, 2)), .snack1)
    }

    /// 5dd84f1: 점심을 찍은 뒤 오후에 또 찍으면 점심 사진이 덮어써졌다
    func testRegression_secondPhotoInSameMealWindowGoesToSnackNotOverTheMeal() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))

        let next = ledger.recordableMealType(at: at(20, 15))
        XCTAssertEqual(next, .snack2)
        ledger.addPhoto(date: at(20, 15), mealType: next, imageData: other, isBefore: true, capturedAt: at(20, 15), now: at(20, 15))

        XCTAssertEqual(ledger.meal(on: at(20, 0), .lunch)?.beforeImageData, photo)
        XCTAssertEqual(ledger.records.count, 2)
    }

    func testRecordableMealType_fillsOtherSnackSlotsBeforeOverwriting() {
        var ledger = ledger()
        for meal in [MealType.lunch, .snack2] {
            ledger.recordWithoutPhoto(date: at(20, 12), mealType: meal, capturedAt: at(20, 12))
        }
        XCTAssertEqual(ledger.recordableMealType(at: at(20, 14)), .snack1)
        ledger.recordWithoutPhoto(date: at(20, 12), mealType: .snack1, capturedAt: at(20, 12))
        XCTAssertEqual(ledger.recordableMealType(at: at(20, 14)), .snack3)
        ledger.recordWithoutPhoto(date: at(20, 12), mealType: .snack3, capturedAt: at(20, 12))
        // 세 칸이 차도 늘어난 간식 칸으로
        XCTAssertEqual(ledger.recordableMealType(at: at(20, 14)), .snack4)
        for snack in MealType.snacks.dropFirst(3) {
            ledger.recordWithoutPhoto(date: at(20, 12), mealType: snack, capturedAt: at(20, 12))
        }
        // 간식 칸이 다 찼으면 끼니가 아니라 시간대 간식 칸을 덮는다
        XCTAssertEqual(ledger.recordableMealType(at: at(20, 14)), .snack2)
    }

    /// 리뷰 "간식을 여러 번 먹으면 새로 올려도 기존 간식이 바뀐다": 간식 칸이 셋뿐이라 네 번째부터 앞 간식을 덮어썼다
    func testRegression_manySnacksAfterFinishingWithoutAfterPhotoEachGetTheirOwnRecord() {
        var ledger = ledger()
        for meal in [MealType.breakfast, .lunch, .dinner] {
            ledger.recordWithoutPhoto(date: at(20, 8), mealType: meal, capturedAt: at(20, 8))
        }
        for i in 0..<7 {
            let now = at(20, 13 + i)
            let slot = ledger.recordableMealType(at: now)
            XCTAssertTrue(slot.isSnack)
            ledger.addPhoto(date: now, mealType: slot, imageData: Data([UInt8(i)]), isBefore: true, capturedAt: now, now: now)
            // 식후 사진 없이 마치기
            ledger.recordAteAll(date: now, mealType: slot, finishedAt: now, now: now)
        }
        let snacks = ledger.records.filter(\.mealType.isSnack)
        XCTAssertEqual(snacks.count, 7)
        XCTAssertEqual(Set(snacks.compactMap(\.beforeImageData)).count, 7)
    }

    /// 위젯 · 단축어 "다 먹음" 을 먹는 중인 식사 없이 누르면, 이미 끝난 기록에 붙지 않고 새 칸에 남는다
    func testAteAllTarget_startsNewRecordWhenSlotIsAlreadyFinished() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        // 먹는 중이면 그 식사를 마친다
        XCTAssertEqual(ledger.ateAllTarget(date: at(20, 12, 20), mealType: .lunch, now: at(20, 12, 20)), .lunch)
        ledger.recordAteAll(date: at(20, 12), mealType: .lunch, finishedAt: at(20, 12, 20), now: at(20, 12, 20))
        // 끝난 점심에 또 누르면 간식 칸으로
        XCTAssertEqual(ledger.ateAllTarget(date: at(20, 14), mealType: .lunch, now: at(20, 14)), .snack2)
        // 빈 칸이면 그대로
        XCTAssertEqual(ledger.ateAllTarget(date: at(20, 19), mealType: .dinner, now: at(20, 19)), .dinner)
    }

    func testRecordableMealType_ignoresYesterdayAndIncompleteRecords() {
        var ledger = ledger([MealRecord(date: at(19, 0), mealType: .lunch, beforeImageData: photo)])
        XCTAssertEqual(ledger.recordableMealType(at: at(20, 12)), .lunch)
        // 메모만 있는 빈 기록은 칸을 차지하지 않는다
        ledger = self.ledger([MealRecord(date: at(20, 0), mealType: .lunch, memo: "나중에")])
        XCTAssertEqual(ledger.recordableMealType(at: at(20, 12)), .lunch)
    }

    // MARK: 덮어써도 되나

    /// "고칠 때마다 열한 칸을 다시 적어 새 기록을 만들었다 — 칸을 빠뜨리면 그 값이 조용히 사라졌다"
    func testAddingAfterPhotoKeepsEverythingElse() {
        let place = MealPlace(latitude: 37.5, longitude: 127.0, name: "집")
        var ledger = ledger()
        let first = ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true,
                                    capturedAt: at(20, 12), now: at(20, 12), place: place)
        ledger.update(date: at(20, 12), mealType: .lunch) {
            $0.memo = "비빔밥"
            $0.portion = .half
            $0.hidePhotoCountBadge = true
        }
        let saved = ledger.addPhoto(date: at(20, 13), mealType: .lunch, imageData: other, isBefore: false,
                                    capturedAt: at(20, 13), now: at(20, 12, 25))

        XCTAssertEqual(saved.id, first.id, "사진을 더해도 같은 기록이다")
        XCTAssertEqual(saved.beforeImageData, photo)
        XCTAssertEqual(saved.afterImageData, other)
        XCTAssertEqual(saved.memo, "비빔밥")
        XCTAssertEqual(saved.portion, .half)
        XCTAssertTrue(saved.hidePhotoCountBadge)
        XCTAssertEqual(saved.place, place)
        XCTAssertEqual(saved.capturedAt, at(20, 12), "먹은 시각은 처음 남긴 것 그대로")
        XCTAssertEqual(ledger.records.count, 1)
    }

    func testPhotoReplacesRecordedWithoutPhotoFlag() {
        var ledger = ledger()
        ledger.recordWithoutPhoto(date: at(20, 8), mealType: .breakfast, capturedAt: at(20, 8))
        let saved = ledger.addPhoto(date: at(20, 8), mealType: .breakfast, imageData: photo, isBefore: true,
                                    capturedAt: at(20, 8), now: at(20, 9))
        XCTAssertFalse(saved.recordedWithoutPhoto)
        XCTAssertEqual(ledger.records.count, 1)
    }

    func testRecordWithoutPhoto_neverTouchesAnExistingRecord() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        let before = ledger.changeCount
        XCTAssertFalse(ledger.recordWithoutPhoto(date: at(20, 12), mealType: .lunch, capturedAt: at(20, 14)))
        XCTAssertEqual(ledger.changeCount, before, "바뀐 것이 없으면 저장하지 않는다")
        XCTAssertEqual(ledger.meal(on: at(20, 0), .lunch)?.beforeImageData, photo)
    }

    func testAteAll_marksExistingRecordWithoutLosingPhoto() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        ledger.recordAteAll(date: at(20, 12), mealType: .lunch, finishedAt: at(20, 12, 20), now: at(20, 12, 20))
        let meal = ledger.meal(on: at(20, 0), .lunch)
        XCTAssertEqual(meal?.ateAll, true)
        XCTAssertEqual(meal?.beforeImageData, photo)
        XCTAssertEqual(ledger.records.count, 1)
    }

    func testAteAll_withoutRecordCreatesOne() {
        var ledger = ledger()
        ledger.recordAteAll(date: at(20, 19), mealType: .dinner, finishedAt: nil, now: at(20, 21))
        let meal = ledger.meal(on: at(20, 0), .dinner)
        XCTAssertEqual(meal?.ateAll, true)
        XCTAssertEqual(meal?.date, at(20, 0), "날짜는 그날 0시로 맞춘다")
        XCTAssertEqual(meal?.capturedAt, at(20, 21))
        XCTAssertTrue(meal?.isComplete == true)
    }

    func testUpdate_missingRecordChangesNothing() {
        var ledger = ledger()
        XCTAssertFalse(ledger.update(date: at(20, 12), mealType: .lunch) { $0.memo = "x" })
        XCTAssertEqual(ledger.changeCount, 0)
        XCTAssertTrue(ledger.records.isEmpty)
    }

    // MARK: 식사 시간 재기

    func testPace_measuredFromLiveBeforePhotoToAfterPhoto() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12, 1))
        let saved = ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: other, isBefore: false,
                                    capturedAt: at(20, 12, 26), now: at(20, 12, 26))
        XCTAssertEqual(saved.startedAt, at(20, 12, 1))
        XCTAssertEqual(saved.finishedAt, at(20, 12, 26))
        XCTAssertEqual(saved.eatingMinutes, 25)
    }

    func testPace_notMeasuredForBackfilledMeal() {
        var ledger = ledger()
        // 저녁에 점심을 뒤늦게 채운다
        let saved = ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true,
                                    capturedAt: at(20, 12), now: at(20, 19))
        XCTAssertNil(saved.startedAt)
        ledger.recordAteAll(date: at(20, 12), mealType: .lunch, finishedAt: at(20, 19, 5), now: at(20, 19, 5))
        XCTAssertNil(ledger.meal(on: at(20, 0), .lunch)?.finishedAt)
    }

    func testDiscardPace_keepsMealButDropsTiming() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        ledger.recordAteAll(date: at(20, 12), mealType: .lunch, finishedAt: at(20, 13, 50), now: at(20, 13, 50))
        XCTAssertEqual(ledger.meal(on: at(20, 0), .lunch)?.eatingMinutes, 110)

        ledger.discardPace(date: at(20, 12), mealType: .lunch)
        let meal = ledger.meal(on: at(20, 0), .lunch)
        XCTAssertNil(meal?.eatingMinutes)
        XCTAssertNil(meal?.startedAt)
        XCTAssertEqual(meal?.ateAll, true)
        XCTAssertEqual(meal?.beforeImageData, photo)
    }

    func testPace_ateAllFromLateReminderIsNotMeasured() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        ledger.recordAteAll(date: at(20, 12), mealType: .lunch, finishedAt: nil, now: at(20, 13, 30))
        let meal = ledger.meal(on: at(20, 0), .lunch)
        XCTAssertNotNil(meal?.startedAt)
        XCTAssertNil(meal?.finishedAt)
        XCTAssertNil(meal?.eatingMinutes)
    }

    func testPace_finishIsNotOverwrittenBySecondSignal() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        ledger.recordAteAll(date: at(20, 12), mealType: .lunch, finishedAt: at(20, 12, 15), now: at(20, 12, 15))
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: other, isBefore: false, capturedAt: at(20, 13), now: at(20, 13))
        XCTAssertEqual(ledger.meal(on: at(20, 0), .lunch)?.finishedAt, at(20, 12, 15))
    }

    // MARK: 지우면 무엇이 남나

    func testDelete_removesOnlyThatSlotAndReportsIDs() {
        var ledger = ledger()
        let lunch = ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        ledger.addPhoto(date: at(20, 19), mealType: .dinner, imageData: photo, isBefore: true, capturedAt: at(20, 19), now: at(20, 19))
        ledger.addPhoto(date: at(19, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(19, 12), now: at(19, 12))

        XCTAssertEqual(ledger.delete(date: at(20, 15), mealType: .lunch), [lunch.id])
        XCTAssertNil(ledger.meal(on: at(20, 0), .lunch))
        XCTAssertNotNil(ledger.meal(on: at(20, 0), .dinner))
        XCTAssertNotNil(ledger.meal(on: at(19, 0), .lunch))
    }

    func testDelete_removesDuplicatesInTheSameSlot() {
        // 동기화가 같은 칸에 둘을 남긴 경우 — 하나만 지우면 지운 기록이 다시 보인다
        var ledger = ledger([MealRecord(date: at(20, 0), mealType: .lunch, beforeImageData: photo),
                             MealRecord(date: at(20, 0), mealType: .lunch, beforeImageData: other)])
        XCTAssertEqual(ledger.delete(date: at(20, 0), mealType: .lunch).count, 2)
        XCTAssertTrue(ledger.records.isEmpty)
    }

    // MARK: 날짜를 옮기면

    func testMove_sameDayOnlyChangesTime() {
        var ledger = ledger()
        let lunch = ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        XCTAssertEqual(ledger.moveTarget(date: at(20, 0), mealType: .lunch, to: at(20, 13, 30)),
                       .slot(day: at(20, 0), mealType: .lunch, dayChanged: false))
        XCTAssertTrue(ledger.move(id: lunch.id, toDay: at(20, 0), mealType: .lunch, capturedAt: at(20, 13, 30), before: photo, after: nil))
        XCTAssertEqual(ledger.meal(on: at(20, 0), .lunch)?.capturedAt, at(20, 13, 30))
    }

    func testMove_toAnotherDayIsBlockedWhenThatMealExists() {
        var ledger = ledger()
        ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        ledger.addPhoto(date: at(19, 12), mealType: .lunch, imageData: other, isBefore: true, capturedAt: at(19, 12), now: at(19, 12))
        XCTAssertEqual(ledger.moveTarget(date: at(20, 0), mealType: .lunch, to: at(19, 12, 30)), .slotTaken)
    }

    func testMove_snackGoesToFreeSnackSlotOnTheNewDay() {
        var ledger = ledger()
        ledger.recordWithoutPhoto(date: at(19, 15), mealType: .snack1, capturedAt: at(19, 15))
        ledger.recordWithoutPhoto(date: at(20, 15), mealType: .snack1, capturedAt: at(20, 15))
        XCTAssertEqual(ledger.moveTarget(date: at(20, 0), mealType: .snack1, to: at(19, 16)),
                       .slot(day: at(19, 0), mealType: .snack2, dayChanged: true))
        // 간식 칸이 다 차 있으면 옮기지 않는다
        for snack in MealType.snacks.dropFirst() {
            ledger.recordWithoutPhoto(date: at(19, 15), mealType: snack, capturedAt: at(19, 15))
        }
        XCTAssertEqual(ledger.moveTarget(date: at(20, 0), mealType: .snack1, to: at(19, 16)), .slotTaken)
    }

    func testMove_carriesEverythingAndClearsEmptyRecordAtTarget() {
        var ledger = ledger([MealRecord(date: at(19, 0), mealType: .lunch, memo: "빈 기록")])
        let lunch = ledger.addPhoto(date: at(20, 12), mealType: .lunch, imageData: photo, isBefore: true, capturedAt: at(20, 12), now: at(20, 12))
        ledger.update(date: at(20, 0), mealType: .lunch) { $0.memo = "옮길 기록"; $0.portion = .little }

        XCTAssertEqual(ledger.moveTarget(date: at(20, 0), mealType: .lunch, to: at(19, 12)),
                       .slot(day: at(19, 0), mealType: .lunch, dayChanged: true), "빈 기록은 칸을 막지 않는다")
        XCTAssertTrue(ledger.move(id: lunch.id, toDay: at(19, 0), mealType: .lunch, capturedAt: at(19, 12), before: photo, after: nil))

        XCTAssertEqual(ledger.records.count, 1)
        let moved = ledger.meal(on: at(19, 0), .lunch)
        XCTAssertEqual(moved?.id, lunch.id)
        XCTAssertEqual(moved?.memo, "옮길 기록")
        XCTAssertEqual(moved?.portion, .little)
        XCTAssertEqual(moved?.startedAt, lunch.startedAt, "잰 식사 시간은 먹은 시각을 고쳐도 그대로다")
        XCTAssertNil(ledger.meal(on: at(20, 0), .lunch))
    }

    func testMove_unknownRecord() {
        var ledger = ledger()
        XCTAssertEqual(ledger.moveTarget(date: at(20, 0), mealType: .lunch, to: at(19, 12)), .notFound)
        XCTAssertFalse(ledger.move(id: UUID(), toDay: at(19, 0), mealType: .lunch, capturedAt: at(19, 12), before: nil, after: nil))
    }

    // MARK: 먹는 중

    func testLatestEatingInProgress_onlyToday() {
        var ledger = ledger([MealRecord(date: at(19, 0), mealType: .dinner, beforeImageData: photo, capturedAt: at(19, 19))])
        XCTAssertNil(ledger.latestEatingInProgress(asOf: at(20, 9)), "날이 지난 미마감 기록은 원탭 다 먹음의 대상이 아니다")
        ledger.addPhoto(date: at(20, 8), mealType: .breakfast, imageData: photo, isBefore: true, capturedAt: at(20, 8), now: at(20, 8))
        XCTAssertEqual(ledger.latestEatingInProgress(asOf: at(20, 9))?.mealType, .breakfast)
    }
}
