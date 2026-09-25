import Foundation

/// The app's Theme for the terminal: port colors and the translucent text
/// levels, blended over the terminal's own colors when it reports them.
struct TerminalPalette {
    let isDark: Bool
    let hasColor: Bool
    let text1: TextStyle
    let text2: TextStyle
    let text3: TextStyle
    /// Unlit dots and the other-apps baseline.
    let faint: TextStyle
    /// Free memory and dividers.
    let track: TextStyle
    /// Background of the selected row, like the app's hover highlight.
    let highlight: RGB?
    let amber: TextStyle
    let red: TextStyle
    let softRed: TextStyle
    private let foreground: RGB?
    private let background: RGB?

    init(screen: TerminalScreen) {
        let foreground = screen.foreground
        let background = screen.background
        let isDark = background.map { $0.luminance < 0.5 } ?? Self.systemIsDark
        self.isDark = isDark
        self.foreground = foreground
        self.background = background
        hasColor = screen.depth != .none

        func pair(_ pair: Palette.Pair) -> TextStyle {
            screen.depth == .none ? TextStyle() : TextStyle(fg: RGB(isDark ? pair.dark : pair.light))
        }
        amber = pair(Palette.amber)
        red = pair(Palette.red)
        softRed = pair(Palette.softRed)

        if screen.depth != .none, let foreground, let background {
            func text(_ dark: Double, _ light: Double) -> TextStyle {
                TextStyle(fg: foreground.over(background, alpha: isDark ? dark : light))
            }
            text1 = TextStyle(fg: foreground)
            text2 = text(0.6, 0.72)
            text3 = text(0.4, 0.62)
            faint = text(0.28, 0.28)
            track = text(0.12, 0.14)
            highlight = foreground.over(background, alpha: isDark ? 0.08 : 0.06)
        } else {
            // Unknown terminal colors: keep the terminal's own text and use dim for the quiet levels.
            text1 = TextStyle()
            text2 = TextStyle()
            text3 = TextStyle(dim: true)
            faint = TextStyle(dim: true)
            track = TextStyle(dim: true)
            highlight = nil
        }
    }

    func port(_ index: Int) -> TextStyle {
        guard hasColor else { return TextStyle() }
        let pair = Palette.ports[index % Palette.ports.count]
        return TextStyle(fg: RGB(isDark ? pair.dark : pair.light))
    }

    /// A style at partial opacity, for dimmed rows and unselected bar segments.
    func faded(_ style: TextStyle, _ alpha: Double) -> TextStyle {
        var style = style
        if let background, let color = style.fg ?? foreground {
            style.fg = color.over(background, alpha: alpha)
        } else {
            style.dim = true
        }
        return style
    }

    func faded(_ line: Line, _ alpha: Double) -> Line {
        line.map { Span($0.text, faded($0.style, alpha)) }
    }

    private static var systemIsDark: Bool {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleInterfaceStyle"] as? String == "Dark"
    }
}

/// A grid of braille characters, each holding 2×4 dots, for sparklines and charts.
struct BrailleCanvas {
    let columns: Int
    let rows: Int
    private var bits: [[UInt8]]
    private static let masks: [[UInt8]] = [[0x01, 0x08], [0x02, 0x10], [0x04, 0x20], [0x40, 0x80]]

    init(columns: Int, rows: Int) {
        self.columns = max(columns, 0)
        self.rows = max(rows, 0)
        bits = Array(repeating: Array(repeating: 0, count: max(columns, 0)), count: max(rows, 0))
    }

    var dotWidth: Int { columns * 2 }
    var dotHeight: Int { rows * 4 }

    mutating func set(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < dotWidth, y < dotHeight else { return }
        bits[y / 4][x / 2] |= Self.masks[y % 4][x % 2]
    }

    /// Straight line between two dots, so a sparkline has no gaps.
    mutating func line(from start: (x: Int, y: Int), to end: (x: Int, y: Int)) {
        var x = start.x, y = start.y
        let dx = abs(end.x - x), dy = -abs(end.y - y)
        let stepX = x < end.x ? 1 : -1, stepY = y < end.y ? 1 : -1
        var error = dx + dy
        while true {
            set(x, y)
            if x == end.x && y == end.y { break }
            let doubled = 2 * error
            if doubled >= dy { error += dy; x += stepX }
            if doubled <= dx { error += dx; y += stepY }
        }
    }

    /// Plots values in order across the full width, joined into one line.
    mutating func plot(_ points: [(x: Int, y: Int)]) {
        guard let first = points.first else { return }
        set(first.x, first.y)
        for (previous, next) in zip(points, points.dropFirst()) {
            line(from: previous, to: next)
        }
    }

    func isEmpty(row: Int, column: Int) -> Bool { bits[row][column] == 0 }

    func character(row: Int, column: Int) -> Character {
        Character(Unicode.Scalar(0x2800 + UInt32(bits[row][column]))!)
    }

    func text(row: Int) -> String {
        String((0..<columns).map { character(row: row, column: $0) })
    }
}
