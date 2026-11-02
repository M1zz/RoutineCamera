import XCTest
@testable import RoutineCameraCore

final class MealSyncResolverTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_000)
    private let newer = Date(timeIntervalSince1970: 2_000)

    func testNoPendingChange_appliesRemote() {
        XCTAssertEqual(MealSyncResolver.resolveRemoteSave(localExists: true, localHasPendingChange: false,
                                                          localModifiedAt: newer, remoteModifiedAt: older),
                       .applyRemote)
    }

    /// 재설치한 기기: 기록도 변경도 없으니 받은 것을 그대로 복원한다
    func testFreshInstall_restoresRemote() {
        XCTAssertEqual(MealSyncResolver.resolveRemoteSave(localExists: false, localHasPendingChange: false,
                                                          localModifiedAt: nil, remoteModifiedAt: older),
                       .applyRemote)
    }

    func testBothChanged_remoteNewer_fillsMissingPhotosFromLocal() {
        XCTAssertEqual(MealSyncResolver.resolveRemoteSave(localExists: true, localHasPendingChange: true,
                                                          localModifiedAt: older, remoteModifiedAt: newer),
                       .applyRemoteFillingPhotos)
    }

    func testBothChanged_localNewer_keepsLocal() {
        XCTAssertEqual(MealSyncResolver.resolveRemoteSave(localExists: true, localHasPendingChange: true,
                                                          localModifiedAt: newer, remoteModifiedAt: older),
                       .keepLocalFillingPhotos)
    }

    func testLocalDeleteNewer_ignoresRemote() {
        XCTAssertEqual(MealSyncResolver.resolveRemoteSave(localExists: false, localHasPendingChange: true,
                                                          localModifiedAt: newer, remoteModifiedAt: older),
                       .ignore)
    }

    func testRemoteEditNewerThanLocalDelete_restoresRecord() {
        XCTAssertEqual(MealSyncResolver.resolveRemoteSave(localExists: false, localHasPendingChange: true,
                                                          localModifiedAt: older, remoteModifiedAt: newer),
                       .applyRemote)
    }

    func testRemoteDelete_doesNotDropUnsentLocalChange() {
        XCTAssertFalse(MealSyncResolver.shouldApplyRemoteDelete(localHasPendingChange: true))
        XCTAssertTrue(MealSyncResolver.shouldApplyRemoteDelete(localHasPendingChange: false))
    }
}
