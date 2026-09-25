import Testing
@testable import WhatThePort

struct TerminalTests {
    @Test func testParsesKeysMouseAndText() {
        let bytes: [UInt8] = Array("\u{1B}[A\u{1B}[B\u{1B}OC\r\u{1B}[5~\u{1B}[<0;12;3M\u{1B}[<0;12;3m\u{1B}[<65;1;1Mqé\u{03}".utf8)
        #expect(TerminalScreen.parse(bytes) == [
            .up, .down, .right, .enter, .pageUp, .click(x: 11, y: 2), .scrollDown,
            .character("q"), .character("é"), .control("c"),
        ])
        #expect(TerminalScreen.parse([0x1B]) == [.escape])
        // A late color reply is skipped rather than read as keys.
        #expect(TerminalScreen.parse(Array("\u{1B}]11;rgb:1e1e/1e1e/2121\u{07}j".utf8)) == [.character("j")])
    }

    @Test func testMeasuresAndTruncatesByColumns() {
        #expect(TextWidth.of("wtp") == 3)
        #expect(TextWidth.of("端口") == 4)
        #expect(TextWidth.of("é") == 1)
        #expect(TextWidth.middle("~/code/project/apps/web", width: 11) == "~/cod…s/web")

        let line: Line = [Span("feature"), Span("/login-flow")]
        #expect(line.truncated(to: 10).map(\.text).joined() == "feature/l…")
        #expect(line.fitted(to: 20).width == 20)
        let split = Line.split([Span("fix resize crash tablet")], [Span("1.24 GB")], width: 20)
        #expect(split.map(\.text).joined() == "fix resize … 1.24 GB")
    }

    @Test func testMapsColorsToThe256Palette() {
        #expect(TerminalScreen.ansi256(RGB(0x000000)) == 16)
        #expect(TerminalScreen.ansi256(RGB(0xFFFFFF)) == 231)
        #expect(TerminalScreen.ansi256(RGB(0x808080)) == 244)
        #expect(ColorDepth.detect(environment: ["NO_COLOR": "1", "COLORTERM": "truecolor"]) == .none)
        #expect(ColorDepth.detect(environment: ["COLORTERM": "truecolor"]) == .truecolor)
        #expect(ColorDepth.detect(environment: ["TERM": "xterm-256color"]) == .ansi256)
    }

    @Test func testBrailleLinesHaveNoGaps() {
        var canvas = BrailleCanvas(columns: 2, rows: 1)
        canvas.plot([(x: 0, y: 3), (x: 3, y: 0)])
        #expect(canvas.text(row: 0) == "⡠⠊")
    }
}
