import XCTest
@testable import RoutineCameraCore

final class FeedbackContentTests: XCTestCase {

    // MARK: - 반응으로 인정되는 것

    func testReaction_singleEmoji() {
        XCTAssertEqual(FeedbackContent.reactionEmoji("👍"), "👍")
        XCTAssertEqual(FeedbackContent.reactionEmoji("🎉"), "🎉")
    }

    func testReaction_paletteIsAllReactions() {
        for emoji in FeedbackContent.reactionPalette {
            XCTAssertTrue(FeedbackContent.isReaction(emoji), "\(emoji) 가 반응으로 인정되지 않음")
        }
    }

    func testReaction_trimsSurroundingWhitespace() {
        XCTAssertEqual(FeedbackContent.reactionEmoji("  👍\n"), "👍")
    }

    func testReaction_ignoresSpacesBetweenEmoji() {
        XCTAssertEqual(FeedbackContent.reactionEmoji("👍 🔥"), "👍🔥")
    }

    func testReaction_upToThree() {
        XCTAssertEqual(FeedbackContent.reactionEmoji("👍🔥🎉"), "👍🔥🎉")
    }

    // 변이 선택자가 붙어야 이모지가 되는 것들
    func testReaction_variationSelectorEmoji() {
        XCTAssertTrue(FeedbackContent.isReaction("❤️"))
    }

    // ZWJ 로 이어붙인 가족·직업 이모지도 한 글자로 센다
    func testReaction_zwjSequenceCountsAsOne() {
        XCTAssertTrue(FeedbackContent.isReaction("👨‍👩‍👧‍👦"))
    }

    // 피부색 변경자가 붙어도 한 글자
    func testReaction_skinToneModifier() {
        XCTAssertTrue(FeedbackContent.isReaction("👍🏽"))
    }

    // MARK: - 글로 취급해야 하는 것

    func testNotReaction_plainText() {
        XCTAssertNil(FeedbackContent.reactionEmoji("잘 먹었네"))
        XCTAssertNil(FeedbackContent.reactionEmoji("nice"))
    }

    func testNotReaction_textWithEmoji() {
        // 기존 콕 찌르기 문구 — 이모지가 섞여 있어도 글이다
        XCTAssertNil(FeedbackContent.reactionEmoji("👉 콕! 점심 기록을 기다리고 있어요"))
    }

    func testNotReaction_empty() {
        XCTAssertNil(FeedbackContent.reactionEmoji(""))
        XCTAssertNil(FeedbackContent.reactionEmoji("   \n "))
    }

    func testNotReaction_tooMany() {
        XCTAssertNil(FeedbackContent.reactionEmoji("👍👍👍👍"))
    }

    // 숫자는 이모지 표현이 가능하지만("1️⃣") 맨 숫자는 글이다
    func testNotReaction_bareDigits() {
        XCTAssertNil(FeedbackContent.reactionEmoji("1"))
        XCTAssertNil(FeedbackContent.reactionEmoji("123"))
    }

    func testNotReaction_punctuation() {
        XCTAssertNil(FeedbackContent.reactionEmoji("!!"))
        XCTAssertNil(FeedbackContent.reactionEmoji("#"))
    }

    // 키캡은 변이 선택자가 붙으므로 반응
    func testReaction_keycap() {
        XCTAssertTrue(FeedbackContent.isReaction("1️⃣"))
    }

    // MARK: - 요약

    func testPreview_shortStaysWhole() {
        XCTAssertEqual(FeedbackContent.preview("잘 먹었네"), "잘 먹었네")
    }

    func testPreview_collapsesNewlines() {
        XCTAssertEqual(FeedbackContent.preview("잘\n먹었네"), "잘 먹었네")
    }

    func testPreview_truncatesWithEllipsis() {
        let long = String(repeating: "가", count: 50)
        let result = FeedbackContent.preview(long, limit: 10)
        XCTAssertEqual(result, String(repeating: "가", count: 10) + "…")
    }
}
