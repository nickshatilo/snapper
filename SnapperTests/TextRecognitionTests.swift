import CoreGraphics
import XCTest
@testable import Snapper

final class TextRecognitionTests: XCTestCase {
    // MARK: - Tokenizing

    private func tokens(in text: String) -> [String] {
        TextRecognitionService.tokenRanges(in: text).map { String(text[$0]) }
    }

    func testTokensKeepPunctuationAttached() {
        XCTAssertEqual(tokens(in: "Hello, world!"), ["Hello,", "world!"])
        XCTAssertEqual(tokens(in: "it's (done) — really."), ["it's", "(done)", "—", "really."])
    }

    func testURLAndEmailStayWhole() {
        XCTAssertEqual(
            tokens(in: "See https://snapper.tools/docs?page=2#top or mail hi@snapper.tools"),
            ["See", "https://snapper.tools/docs?page=2#top", "or", "mail", "hi@snapper.tools"]
        )
    }

    func testCodeKeepsItsSymbols() {
        XCTAssertEqual(
            tokens(in: "let x = foo(bar: 1) ?? [0];"),
            ["let", "x", "=", "foo(bar:", "1)", "??", "[0];"]
        )
    }

    func testSurroundingAndRepeatedWhitespaceIsSkipped() {
        XCTAssertEqual(tokens(in: "  two   words \t"), ["two", "words"])
        XCTAssertEqual(tokens(in: "a\nb\tc\r\nd"), ["a", "b", "c", "d"])
    }

    func testEmptyAndBlankStringsHaveNoTokens() {
        XCTAssertEqual(tokens(in: ""), [])
        XCTAssertEqual(tokens(in: " \n\t "), [])
    }

    func testTokenRangesIndexTheOriginalString() {
        let text = " a,  bc"
        let ranges = TextRecognitionService.tokenRanges(in: text)

        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(text.distance(from: text.startIndex, to: ranges[0].lowerBound), 1)
        XCTAssertEqual(text.distance(from: text.startIndex, to: ranges[0].upperBound), 3)
        XCTAssertEqual(text.distance(from: text.startIndex, to: ranges[1].lowerBound), 5)
        XCTAssertEqual(ranges[1].upperBound, text.endIndex)
    }

    // MARK: - Reading order

    /// Image rects are y-up: a larger `y` is higher on the page.
    private func block(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 40,
        height: CGFloat = 20
    ) -> OCRTextBlock {
        OCRTextBlock(text: text, imageRect: CGRect(x: x, y: y, width: width, height: height))
    }

    func testLinesComeBackTopToBottomAndLeftToRight() {
        let blocks = [
            block("world!", x: 60, y: 60),
            block("second", x: 10, y: 100),
            block("Hello,", x: 10, y: 60),
            block("line.", x: 60, y: 100),
        ]

        let lines = TextRecognitionService.lines(from: blocks)

        XCTAssertEqual(lines.map { $0.map(\.text) }, [["second", "line."], ["Hello,", "world!"]])
        XCTAssertEqual(TextRecognitionService.composeText(from: blocks), "second line.\nHello, world!")
    }

    func testUnevenBaselinesStayOnOneLine() {
        // Centres wander by a few pixels, and the highest block is not the
        // leftmost one.
        let blocks = [
            block("fox", x: 110, y: 104),
            block("quick", x: 10, y: 100),
            block("brown", x: 60, y: 97),
            block("jumps", x: 160, y: 101),
        ]

        XCTAssertEqual(TextRecognitionService.lines(from: blocks).count, 1)
        XCTAssertEqual(TextRecognitionService.composeText(from: blocks), "quick brown fox jumps")
    }

    func testSmallTextSplitsOnTheMinimumTolerance() {
        // 4px-tall blocks: the tolerance bottoms out at 5px between centres.
        let sameLine = [
            block("b", x: 20, y: 10, width: 6, height: 4),
            block("a", x: 10, y: 14, width: 6, height: 4),
        ]
        XCTAssertEqual(TextRecognitionService.composeText(from: sameLine), "a b")

        let twoLines = [
            block("b", x: 20, y: 10, width: 6, height: 4),
            block("a", x: 10, y: 17, width: 6, height: 4),
        ]
        XCTAssertEqual(TextRecognitionService.composeText(from: twoLines), "a\nb")
    }

    func testStackedLinesStaySeparate() {
        // Single-spaced text: each line's centre is one line height from the next.
        let blocks = [
            block("two", x: 10, y: 80),
            block("three", x: 40, y: 60),
            block("one", x: 70, y: 100),
        ]

        XCTAssertEqual(TextRecognitionService.composeText(from: blocks), "one\ntwo\nthree")
    }

    func testOrderDoesNotDependOnInputOrder() {
        let blocks = [
            block("a", x: 10, y: 100),
            block("b", x: 60, y: 103),
            block("c", x: 110, y: 98),
            block("d", x: 10, y: 70),
            block("e", x: 60, y: 72),
        ]

        let expected = "a b c\nd e"
        XCTAssertEqual(TextRecognitionService.composeText(from: blocks), expected)
        XCTAssertEqual(TextRecognitionService.composeText(from: blocks.reversed()), expected)
        XCTAssertEqual(
            TextRecognitionService.composeText(from: [blocks[3], blocks[1], blocks[4], blocks[0], blocks[2]]),
            expected
        )
    }

    func testSingleBlockAndNoBlocks() {
        XCTAssertEqual(TextRecognitionService.composeText(from: []), "")
        XCTAssertTrue(TextRecognitionService.lines(from: []).isEmpty)
        XCTAssertEqual(
            TextRecognitionService.composeText(from: [block("user@example.com", x: 0, y: 0)]),
            "user@example.com"
        )
    }
}
