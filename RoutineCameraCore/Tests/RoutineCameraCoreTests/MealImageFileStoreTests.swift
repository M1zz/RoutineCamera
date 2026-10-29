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
}
