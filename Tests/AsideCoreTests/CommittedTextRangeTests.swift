import XCTest
@testable import AsideCore

final class CommittedTextRangeTests: XCTestCase {
    private let noMark = NSRange(location: NSNotFound, length: 0)
    func testUsesUTF16AndKeepsEarlierDocumentTextOutsideReplacement() {
        let text = "你好😀"
        XCTAssertEqual(CommittedTextRange.candidate(start: 12, utf16Length: text.utf16.count,
            selection: NSRange(location: 16, length: 0), marked: noMark), NSRange(location: 12, length: 4))
    }
    func testRejectsMovedCaretSelectionsAndActivePreedit() {
        XCTAssertNil(CommittedTextRange.candidate(start: 2, utf16Length: 3, selection: NSRange(location: 4, length: 0), marked: noMark))
        XCTAssertNil(CommittedTextRange.candidate(start: 2, utf16Length: 3, selection: NSRange(location: 5, length: 1), marked: noMark))
        XCTAssertNil(CommittedTextRange.candidate(start: 2, utf16Length: 3, selection: NSRange(location: 5, length: 0), marked: NSRange(location: 5, length: 2)))
    }
    func testRejectsUnknownAndOverflowingAnchors() {
        XCTAssertNil(CommittedTextRange.candidate(start: NSNotFound, utf16Length: 1, selection: noMark, marked: noMark))
        XCTAssertNil(CommittedTextRange.candidate(start: Int.max - 1, utf16Length: 4, selection: noMark, marked: noMark))
    }
}
