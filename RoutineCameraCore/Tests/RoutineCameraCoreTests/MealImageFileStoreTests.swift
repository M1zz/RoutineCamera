import XCTest
@testable import RoutineCameraCore

final class MealImageFileStoreTests: XCTestCase {

    private var directory: URL!
    private var store: MealImageFileStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MealImageFileStoreTests-\(UUID().uuidString)")
        store = MealImageFileStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bytes(count: Int, seed: UInt8) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0) &+ seed })
    }

    func testFileName_isStablePerSlot() {
        XCTAssertEqual(MealImageFileStore.fileName(day: "2026-09-10", slot: "lunch", kind: "after"),
                       "2026-09-10_lunch_after.jpg")
    }

    func testWriteThenLoad_roundTrips() throws {
        let data = bytes(count: 50_000, seed: 3)
        XCTAssertTrue(try store.write(data, named: "a.jpg"))
        XCTAssertEqual(store.load(named: "a.jpg"), data)
    }

    func testLoad_missingFile_returnsNil() {
        XCTAssertNil(store.load(named: "missing.jpg"))
    }

    func testWrite_sameContent_skipsRewrite() throws {
        let data = bytes(count: 50_000, seed: 1)
        XCTAssertTrue(try store.write(data, named: "a.jpg"))
        XCTAssertFalse(try store.write(data, named: "a.jpg"))
    }

    func testWrite_replacedPhotoOfSameSize_rewrites() throws {
        XCTAssertTrue(try store.write(bytes(count: 50_000, seed: 1), named: "a.jpg"))
        let replacement = bytes(count: 50_000, seed: 9)
        XCTAssertTrue(try store.write(replacement, named: "a.jpg"))
        XCTAssertEqual(store.load(named: "a.jpg"), replacement)
    }

    func testWrite_smallFileDifferingInMiddle_rewrites() throws {
        var data = bytes(count: 1_000, seed: 0)
        XCTAssertTrue(try store.write(data, named: "a.jpg"))
        data[500] ^= 0xFF
        XCTAssertTrue(try store.write(data, named: "a.jpg"))
        XCTAssertEqual(store.load(named: "a.jpg"), data)
    }

    func testWrite_rejectsPathLikeNames() {
        let data = bytes(count: 10, seed: 0)
        XCTAssertThrowsError(try store.write(data, named: "../escape.jpg"))
        XCTAssertThrowsError(try store.write(data, named: ""))
        XCTAssertThrowsError(try store.write(data, named: ".."))
    }

    func testRemoveFiles_keepsListedPhotosAndIgnoresOtherFiles() throws {
        try store.write(bytes(count: 10, seed: 1), named: "keep.jpg")
        try store.write(bytes(count: 10, seed: 2), named: "orphan.jpg")
        let note = directory.appendingPathComponent("note.txt")
        try Data("x".utf8).write(to: note)

        XCTAssertEqual(store.removeFiles(keeping: ["keep.jpg"]), 1)
        XCTAssertNotNil(store.load(named: "keep.jpg"))
        XCTAssertNil(store.load(named: "orphan.jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: note.path))
    }

    func testRemoveFiles_missingDirectory_isNoOp() {
        XCTAssertEqual(store.removeFiles(keeping: []), 0)
    }

    /// 이미 읽은 파일과 같은 내용을 다시 쓰라고 하면 디스크를 건드리지 않는다
    func testWrite_afterLoad_sameContent_skipsDisk() throws {
        let store = MealImageFileStore(directory: directory)
        let data = Data((0..<20_000).map { UInt8($0 % 251) })
        try store.write(data, named: "a.jpg")
        let fresh = MealImageFileStore(directory: directory)
        let loaded = try XCTUnwrap(fresh.load(named: "a.jpg"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("a.jpg"))
        // 파일이 없어도 표시가 같으니 쓰지 않는다 — 디스크를 열지 않았다는 뜻
        XCTAssertFalse(try fresh.write(loaded, named: "a.jpg"))
        // 내용이 바뀌면 쓴다
        var changed = loaded
        changed[0] ^= 0xFF
        XCTAssertTrue(try fresh.write(changed, named: "a.jpg"))
    }

    /// 기록 저장은 메인 밖에서 하고 불러오기는 메인에서 한다 — 여러 스레드가 동시에 써도 깨지지 않아야 한다
    func testConcurrentWritesAndLoads_areSafe() throws {
        let store = MealImageFileStore(directory: directory)
        let photos = (0..<8).map { bytes(count: 10_000, seed: UInt8($0)) }
        DispatchQueue.concurrentPerform(iterations: 400) { i in
            let name = "p\(i % 8).jpg"
            if i % 3 == 0 {
                _ = store.load(named: name)
            } else {
                _ = try? store.write(photos[i % 8], named: name)
            }
        }
        for (i, photo) in photos.enumerated() {
            XCTAssertEqual(store.load(named: "p\(i).jpg"), photo)
        }
    }
}
