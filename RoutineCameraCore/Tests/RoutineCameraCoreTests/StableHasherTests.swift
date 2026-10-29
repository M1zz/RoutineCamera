import XCTest
@testable import RoutineCameraCore

final class StableHasherTests: XCTestCase {

    private func hash(_ build: (inout StableHasher) -> Void) -> Int {
        var h = StableHasher()
        build(&h)
        return h.finalize()
    }

    /// 실행이 바뀌어도 같은 값이어야 저장해 둔 지문과 비교할 수 있다 — 값을 고정해 둔다.
    func testValueIsFixedAcrossRuns() {
        XCTAssertEqual(hash { _ in }, Int(truncatingIfNeeded: UInt64(0xcbf2_9ce4_8422_2325)))
        let a = hash { $0.combine("점심"); $0.combine(1024); $0.combine(true); $0.combine(1_785_000_000.0) }
        let b = hash { $0.combine("점심"); $0.combine(1024); $0.combine(true); $0.combine(1_785_000_000.0) }
        XCTAssertEqual(a, b)
    }

    func testDifferentInputsDiffer() {
        XCTAssertNotEqual(hash { $0.combine("ab"); $0.combine("c") }, hash { $0.combine("a"); $0.combine("bc") })
        XCTAssertNotEqual(hash { $0.combine(1) }, hash { $0.combine(2) })
        XCTAssertNotEqual(hash { $0.combine(false) }, hash { $0.combine(true) })
        XCTAssertNotEqual(hash { $0.combine(0.0) }, hash { $0.combine(1.0) })
    }
}
