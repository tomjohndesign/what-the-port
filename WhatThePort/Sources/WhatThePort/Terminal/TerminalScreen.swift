import Darwin
import Foundation

// MARK: - Colors and styled text

struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    /// This color at `alpha` over `background`, like the app's translucent text.
    func over(_ background: RGB, alpha: Double) -> RGB {
        RGB(r: r * alpha + background.r * (1 - alpha),
            g: g * alpha + background.g * (1 - alpha),
            b: b * alpha + background.b * (1 - alpha))
    }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    var bytes: (Int, Int, Int) {
        (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

struct TextStyle: Equatable {
    var fg: RGB?
    var bg: RGB?
    var bold = false
    var dim = false

    func bold(_ on: Bool = true) -> TextStyle { var copy = self; copy.bold = on; return copy }
    func background(_ color: RGB?) -> TextStyle { var copy = self; copy.bg = color; return copy }
}

struct Span {
    var text: String
    var style: TextStyle

    init(_ text: String, _ style: TextStyle = TextStyle()) {
        self.text = text
        self.style = style
    }

    var width: Int { TextWidth.of(text) }
}

typealias Line = [Span]

extension Array where Element == Span {
    var width: Int { reduce(0) { $0 + $1.width } }

    /// Cuts to `width` columns, ending in an ellipsis when anything was dropped.
    func truncated(to width: Int) -> Line {
        guard self.width > width else { return self }
        guard width > 0 else { return [] }
        var result: Line = []
        var remaining = width - 1
        for span in self {
            let spanWidth = span.width
            if spanWidth <= remaining {
                result.append(span)
                remaining -= spanWidth
            } else {
                result.append(Span(TextWidth.prefix(span.text, width: remaining) + "…", span.style))
                return result
            }
        }
        return result
    }

    /// Exactly `width` columns: truncated, then padded in `style`.
    func fitted(to width: Int, padding style: TextStyle = TextStyle()) -> Line {
        let line = truncated(to: width)
        let gap = width - line.width
        return gap > 0 ? line + [Span(String(repeating: " ", count: gap), style)] : line
    }

    /// Left and right content on one line; the left side truncates first.
    static func split(_ left: Line, _ right: Line, width: Int, padding style: TextStyle = TextStyle()) -> Line {
        let rightWidth = right.width
        let leftLine = left.truncated(to: Swift.max(width - rightWidth - (rightWidth > 0 ? 1 : 0), 0))
        let gap = Swift.max(width - leftLine.width - rightWidth, 0)
        return (leftLine + [Span(String(repeating: " ", count: gap), style)] + right).truncated(to: width)
    }

    /// Applies a background to every span that doesn't set its own.
    func background(_ color: RGB?) -> Line {
        guard let color else { return self }
        return map { span in
            var span = span
            if span.style.bg == nil { span.style.bg = color }
            return span
        }
    }
}

/// Terminal column widths: wide East Asian characters and emoji take two,
/// combining marks and joiners take none.
enum TextWidth {
    static func of(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + of($1) }
    }

    static func of(_ scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value < 0x20 || (0x7F..<0xA0).contains(value) { return 0 }
        if value < 0x300 { return 1 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format: return 0
        default: break
        }
        if (0xFE00...0xFE0F).contains(value) || value == 0x200D { return 0 }
        if scalar.properties.isEmojiPresentation { return 2 }
        switch value {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    static func prefix(_ text: String, width: Int) -> String {
        var result = ""
        var used = 0
        for character in text {
            let characterWidth = of(String(character))
            if used + characterWidth > width { break }
            result.append(character)
            used += characterWidth
        }
        return result
    }

    static func suffix(_ text: String, width: Int) -> String {
        var result = ""
        var used = 0
        for character in text.reversed() {
            let characterWidth = of(String(character))
            if used + characterWidth > width { break }
            result.insert(character, at: result.startIndex)
            used += characterWidth
        }
        return result
    }

    /// Keeps both ends, like the app's `.truncationMode(.middle)` for paths and commands.
    static func middle(_ text: String, width: Int) -> String {
        guard of(text) > width else { return text }
        guard width > 1 else { return prefix("…", width: width) }
        let head = (width - 1) / 2
        return prefix(text, width: head) + "…" + suffix(text, width: width - 1 - head)
    }
}

// MARK: - Terminal

enum ColorDepth {
    case none, ansi256, truecolor

    static func detect(environment: [String: String] = ProcessInfo.processInfo.environment) -> ColorDepth {
        if let noColor = environment["NO_COLOR"], !noColor.isEmpty { return .none }
        if environment["TERM"] == "dumb" { return .none }
        let colorTerm = environment["COLORTERM"]?.lowercased() ?? ""
        if colorTerm == "truecolor" || colorTerm == "24bit" { return .truecolor }
        let program = environment["TERM_PROGRAM"] ?? ""
        let truecolorPrograms: Set<String> = ["iTerm.app", "WezTerm", "ghostty", "vscode", "WarpTerminal", "Hyper", "Tabby", "rio", "zed"]
        if truecolorPrograms.contains(program) { return .truecolor }
        let term = environment["TERM"] ?? ""
        if ["kitty", "ghostty", "alacritty", "direct"].contains(where: term.contains) { return .truecolor }
        // Terminal gained 24-bit color in macOS 26.
        if program == "Apple_Terminal" {
            return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 ? .truecolor : .ansi256
        }
        return .ansi256
    }
}

enum InputEvent: Equatable {
    case character(Character)
    case up, down, left, right
    case enter, escape, tab, backTab, backspace
    case pageUp, pageDown, home, end
    case control(Character)
    case click(x: Int, y: Int)
    case scrollUp, scrollDown
}

/// Raw-mode, alternate-screen terminal output with line-level diffing, and
/// a parser for keys and SGR mouse reports.
final class TerminalScreen {
    private(set) var columns = 80
    private(set) var rows = 24
    let depth: ColorDepth
    /// The terminal's own colors, when it answers OSC 10/11.
    private(set) var foreground: RGB?
    private(set) var background: RGB?

    private var original = termios()
    private var isActive = false
    private var previous: [String] = []

    init() {
        depth = ColorDepth.detect()
        updateSize()
    }

    func updateSize() {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0, size.ws_row > 0 {
            columns = Int(size.ws_col)
            rows = Int(size.ws_row)
        }
        previous = []
    }

    func enter() {
        guard !isActive else { return }
        tcgetattr(STDIN_FILENO, &original)
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_cc.16 = 1 // VMIN
        raw.c_cc.17 = 0 // VTIME
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        isActive = true
        // Alternate screen, hidden cursor, no autowrap, button and wheel mouse reports.
        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?7l\u{1B}[?1000h\u{1B}[?1006h\u{1B}[2J")
        previous = []
    }

    func leave() {
        guard isActive else { return }
        write("\u{1B}[?1006l\u{1B}[?1000l\u{1B}[?7h\u{1B}[?25h\u{1B}[0m\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        isActive = false
    }

    /// Asks the terminal for its foreground and background colors. Terminals
    /// that don't support OSC 10/11 still answer the device-attributes query
    /// that follows, so this never waits the full timeout on them.
    func queryColors(timeout: TimeInterval = 0.3) {
        guard isActive else { return }
        write("\u{1B}]10;?\u{07}\u{1B}]11;?\u{07}\u{1B}[c")
        var buffer: [UInt8] = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            let wait = Int32(max(deadline.timeIntervalSinceNow * 1000, 1))
            guard poll(&descriptor, 1, wait) > 0 else { break }
            var chunk = [UInt8](repeating: 0, count: 256)
            let count = read(STDIN_FILENO, &chunk, chunk.count)
            guard count > 0 else { break }
            buffer.append(contentsOf: chunk[0..<count])
            // Device attributes reply: ESC [ ? … c
            if let text = String(bytes: buffer, encoding: .utf8), text.range(of: "\u{1B}\\[\\?[0-9;]*c", options: .regularExpression) != nil {
                break
            }
        }
        let text = String(decoding: buffer, as: UTF8.self)
        foreground = Self.parseColor(in: text, code: 10)
        background = Self.parseColor(in: text, code: 11)
    }

    private static func parseColor(in text: String, code: Int) -> RGB? {
        let pattern = "\u{1B}\\]\(code);rgba?:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let components: [Double] = (1...3).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            let hex = String(text[range])
            guard let value = UInt64(hex, radix: 16) else { return nil }
            let maximum = pow(16, Double(hex.count)) - 1
            return Double(value) / maximum
        }
        guard components.count == 3 else { return nil }
        return RGB(r: components[0], g: components[1], b: components[2])
    }

    // MARK: Drawing

    /// Draws a full frame, rewriting only the lines that changed.
    func draw(_ lines: [Line]) {
        let rendered = (0..<rows).map { index in
            encode((index < lines.count ? lines[index] : []).fitted(to: columns))
        }
        var output = "\u{1B}[?2026h"
        if previous.count != rendered.count {
            output += "\u{1B}[2J"
            previous = []
        }
        for (index, line) in rendered.enumerated() where index >= previous.count || previous[index] != line {
            output += "\u{1B}[\(index + 1);1H" + line
        }
        output += "\u{1B}[?2026l"
        write(output)
        previous = rendered
    }

    func invalidate() { previous = [] }

    private func encode(_ line: Line) -> String {
        var output = ""
        var current: TextStyle?
        for span in line where !span.text.isEmpty {
            if span.style != current {
                output += sgr(span.style)
                current = span.style
            }
            output += span.text
        }
        return output + "\u{1B}[0m"
    }

    private func sgr(_ style: TextStyle) -> String {
        var codes = ["0"]
        if style.bold { codes.append("1") }
        if style.dim { codes.append("2") }
        if let fg = style.fg, let code = color(fg, base: 38) { codes.append(code) }
        if let bg = style.bg, let code = color(bg, base: 48) { codes.append(code) }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }

    private func color(_ color: RGB, base: Int) -> String? {
        switch depth {
        case .none: return nil
        case .truecolor:
            let (r, g, b) = color.bytes
            return "\(base);2;\(r);\(g);\(b)"
        case .ansi256:
            return "\(base);5;\(Self.ansi256(color))"
        }
    }

    /// Nearest color in the xterm 256-color cube or grayscale ramp.
    static func ansi256(_ color: RGB) -> Int {
        let (r, g, b) = color.bytes
        let levels = [0, 95, 135, 175, 215, 255]
        func nearestLevel(_ value: Int) -> Int {
            levels.indices.min { abs(levels[$0] - value) < abs(levels[$1] - value) }!
        }
        let (ri, gi, bi) = (nearestLevel(r), nearestLevel(g), nearestLevel(b))
        let cube = (levels[ri], levels[gi], levels[bi])
        let grayIndex = min(max((((r + g + b) / 3) - 8 + 5) / 10, 0), 23)
        let gray = 8 + grayIndex * 10
        func distance(_ other: (Int, Int, Int)) -> Int {
            let dr = r - other.0, dg = g - other.1, db = b - other.2
            return dr * dr + dg * dg + db * db
        }
        return distance((gray, gray, gray)) < distance(cube) ? 232 + grayIndex : 16 + 36 * ri + 6 * gi + bi
    }

    func write(_ string: String) {
        var bytes = Array(string.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeMutableBytes { buffer in
                Darwin.write(STDOUT_FILENO, buffer.baseAddress! + offset, buffer.count - offset)
            }
            if written <= 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            offset += written
        }
    }

    // MARK: Input

    static func parse(_ bytes: [UInt8]) -> [InputEvent] {
        var events: [InputEvent] = []
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x1B:
                guard index + 1 < bytes.count else {
                    events.append(.escape)
                    index += 1
                    continue
                }
                let next = bytes[index + 1]
                if next == UInt8(ascii: "[") {
                    var end = index + 2
                    while end < bytes.count, !(0x40...0x7E).contains(bytes[end]) { end += 1 }
                    guard end < bytes.count else { index = bytes.count; continue }
                    let parameters = String(decoding: bytes[(index + 2)..<end], as: UTF8.self)
                    if let event = csi(parameters: parameters, final: bytes[end]) { events.append(event) }
                    index = end + 1
                } else if next == UInt8(ascii: "O"), index + 2 < bytes.count {
                    if let event = csi(parameters: "", final: bytes[index + 2]) { events.append(event) }
                    index += 3
                } else if next == UInt8(ascii: "]") {
                    // Late OSC reply: skip to BEL or ST.
                    var end = index + 2
                    while end < bytes.count, bytes[end] != 0x07, !(bytes[end] == 0x1B && end + 1 < bytes.count && bytes[end + 1] == UInt8(ascii: "\\")) { end += 1 }
                    index = min(end + (end < bytes.count && bytes[end] == 0x1B ? 2 : 1), bytes.count)
                } else if next == 0x1B {
                    events.append(.escape)
                    index += 1
                } else {
                    // Option-key combinations arrive as ESC + key; treat them as the key.
                    index += 1
                }
            case 0x0D, 0x0A: events.append(.enter); index += 1
            case 0x09: events.append(.tab); index += 1
            case 0x7F, 0x08: events.append(.backspace); index += 1
            case 0x01...0x1A:
                events.append(.control(Character(Unicode.Scalar(byte + 0x60))))
                index += 1
            case 0x00...0x1F:
                index += 1
            default:
                var end = index + 1
                while end < bytes.count, bytes[end] >= 0x20, bytes[end] != 0x7F, bytes[end] != 0x1B { end += 1 }
                for character in String(decoding: bytes[index..<end], as: UTF8.self) {
                    events.append(.character(character))
                }
                index = end
            }
        }
        return events
    }

    private static func csi(parameters: String, final: UInt8) -> InputEvent? {
        if parameters.hasPrefix("<") {
            // SGR mouse: ESC [ < button ; x ; y (M press | m release)
            let parts = parameters.dropFirst().split(separator: ";").compactMap { Int($0) }
            guard parts.count == 3, final == UInt8(ascii: "M") else { return nil }
            switch parts[0] {
            case 64: return .scrollUp
            case 65: return .scrollDown
            case 0: return .click(x: parts[1] - 1, y: parts[2] - 1)
            default: return nil
            }
        }
        switch final {
        case UInt8(ascii: "A"): return .up
        case UInt8(ascii: "B"): return .down
        case UInt8(ascii: "C"): return .right
        case UInt8(ascii: "D"): return .left
        case UInt8(ascii: "H"): return .home
        case UInt8(ascii: "F"): return .end
        case UInt8(ascii: "Z"): return .backTab
        case UInt8(ascii: "~"):
            switch parameters {
            case "1", "7": return .home
            case "4", "8": return .end
            case "5": return .pageUp
            case "6": return .pageDown
            default: return nil
            }
        default: return nil
        }
    }
}
