import XCTest
@testable import AsideCore

final class CompositionTests: XCTestCase {
    func testRewritePreservesSpacingBetweenSentences() throws {
        var state = SentenceComposition()
        state.append("  This could work. \n")
        XCTAssertTrue(state.acceptPreview(try .validated(expression: "This may be effective.", explanation: "保留不确定性。"), revision: state.revision))
        XCTAssertEqual(state.takeEnglish(), "  This may be effective. \n")
    }
    func testWordsAccumulateWithoutTranslatingFragments() {
        var state = SentenceComposition()
        state.append("我觉得")
        XCTAssertNil(state.completeSentence)
        state.append("这个方法")
        XCTAssertNil(state.completeSentence)
        state.append("可行。")
        XCTAssertEqual(state.completeSentence, "我觉得这个方法可行。")
    }
    func testLearningCandidateNeverBecomesHostText() throws {
        var state = SentenceComposition()
        state.append("你好。")
        let token = state.revision
        XCTAssertTrue(state.acceptPreview(try .validated(expression: "Hello.", explanation: "问候。"), revision: token))
        XCTAssertEqual(state.hostMarkedText(preedit: ""), "")
        XCTAssertEqual(state.takeOriginal(), "你好。")
        XCTAssertTrue(state.source.isEmpty)
    }
    func testStaleResultsAndFocusReset() throws {
        var state = SentenceComposition()
        state.append("Hello.")
        let token = state.revision
        state.append(" Next")
        XCTAssertFalse(state.acceptPreview(try .validated(expression: "Hi.", explanation: "问候。"), revision: token))
        state.reset()
        XCTAssertNil(state.preview)
        XCTAssertTrue(state.source.isEmpty)
    }
    func testEnglishOnlyAdoptedExplicitly() throws {
        var state = SentenceComposition()
        state.append("这个可能可行。")
        XCTAssertTrue(state.acceptPreview(try .validated(expression: "This may work.", explanation: "保留可能性。"), revision: state.revision))
        XCTAssertEqual(state.takeEnglish(), "This may work.")
        XCTAssertNil(state.takeEnglish())
    }
    func testBackspaceUsesWholeGraphemeAndInvalidatesPreview() {
        var state = SentenceComposition()
        state.append("你👨‍👩‍👧‍👦")
        state.backspace()
        XCTAssertEqual(state.source, "你")
        XCTAssertNil(state.preview)
    }
    func testEnglishAndChineseAreNotSplitIntoWords() {
        var state = SentenceComposition()
        for part in ["This ", "method ", "may work."] { state.append(part) }
        XCTAssertEqual(state.completeSentence, "This method may work.")
        XCTAssertEqual(state.hostMarkedText(preedit: "ni"), "ni")
        XCTAssertEqual(state.source, "This method may work.")
    }
}
