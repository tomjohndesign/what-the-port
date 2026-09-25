import AppKit
import SwiftUI

/// A 5×5 dot-matrix glyph. `#` is lit, `a` is lit amber, `.` is unlit.
struct DotGlyph: Equatable {
    let rows: [String]

    static let colon = DotGlyph(rows: [".....", "..#..", ".....", "..#..", "....."])
    static let idle = DotGlyph(rows: [".....", ".....", ".....", ".....", "....."])
    static let alert = DotGlyph(rows: ["aaaaa", "aa.aa", "aaaaa", "aa.aa", "aaaaa"])
    static let question = DotGlyph(rows: [".###.", "#...#", "..##.", ".....", "..#.."])
    static let prompt = DotGlyph(rows: ["#....", ".#...", "..#..", ".#...", "#.###"])
    static let leak = DotGlyph(rows: ["....a", "...a.", "..#..", ".#...", "#...."])
    static let burst = DotGlyph(rows: ["#.#.#", ".....", "#...#", ".....", "#.#.#"])
    static let triangle = DotGlyph(rows: [".....", "..#..", ".###.", "#####", "....."])
    /// The colon with a cursor after it, for the terminal.
    static let cursor = DotGlyph(rows: [".....", ".#...", ".....", ".#.##", "....."])
    static let bars = DotGlyph(rows: ["....#", "..#.#", "..#.#", "#.#.#", "#.#.#"])

    private static let digits: [[String]] = [
        [".###.", "#..##", "#.#.#", "##..#", ".###."],
        ["..#..", ".##..", "..#..", "..#..", ".###."],
        ["####.", "....#", ".###.", "#....", "#####"],
        ["####.", "....#", ".###.", "....#", "####."],
        ["#..#.", "#..#.", "#####", "...#.", "...#."],
        ["#####", "#....", "####.", "....#", "####."],
        [".###.", "#....", "####.", "#...#", ".###."],
        ["#####", "....#", "...#.", "..#..", "..#.."],
        [".###.", "#...#", ".###.", "#...#", ".###."],
        [".###.", "#...#", ".####", "....#", ".###."],
    ]

    /// A single digit drawn in the grid, for the "Count" menu bar style.
    static func digit(_ value: Int) -> DotGlyph? {
        (0...9).contains(value) ? DotGlyph(rows: digits[value]) : nil
    }

    func dot(row: Int, column: Int) -> Character {
        let line = Array(rows[row])
        return column < line.count ? line[column] : "."
    }
}

/// SwiftUI rendering of a dot glyph, used in the popover's empty state.
struct DotGridView: View {
    let glyph: DotGlyph
    var size: CGFloat = 64

    var body: some View {
        let pitch = size / 5
        Canvas { context, _ in
            for row in 0..<5 {
                for column in 0..<5 {
                    let rect = CGRect(x: CGFloat(column) * pitch + pitch * 0.18,
                                      y: CGFloat(row) * pitch + pitch * 0.18,
                                      width: pitch * 0.64, height: pitch * 0.64)
                    let dot = glyph.dot(row: row, column: column)
                    let color: Color = dot == "a" ? Theme.amber : (dot == "#" ? Theme.text1 : Theme.text1.opacity(0.12))
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Draws the menu bar icon: a dot grid, optionally followed by a count.
enum MenuBarIcon {
    static func image(glyph: DotGlyph, count: Int?) -> NSImage {
        let height: CGFloat = 18
        let gridSize: CGFloat = 16
        let font = FontLoader.nsFont("GeistMono-Medium", size: 13)
        let countText = count.map { String($0) }
        let textWidth = countText.map { ($0 as NSString).size(withAttributes: [.font: font]).width } ?? 0
        let width = gridSize + (countText == nil ? 0 : 5 + ceil(textWidth))
        let isAlert = glyph.rows.joined().contains("a")

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let pitch = gridSize / 5
            let origin = CGPoint(x: 0, y: (height - gridSize) / 2)
            for row in 0..<5 {
                for column in 0..<5 {
                    let rect = CGRect(x: origin.x + CGFloat(column) * pitch + pitch * 0.12,
                                      y: origin.y + CGFloat(row) * pitch + pitch * 0.12,
                                      width: pitch * 0.76, height: pitch * 0.76)
                    let dot = glyph.dot(row: row, column: column)
                    let color: NSColor
                    switch dot {
                    case "a":
                        color = isDark ? NSColor(srgbRed: 1, green: 0.7, blue: 0.14, alpha: 1)
                                       : NSColor(srgbRed: 0.886, green: 0.604, blue: 0, alpha: 1)
                    case "#":
                        color = .black
                    default:
                        // Unlit dots only show when the grid is saying something (an alert);
                        // at rest the icon is just its lit dots, like other menu bar icons.
                        guard isAlert else { continue }
                        // Alert holes go dark so the colon reads against amber.
                        color = isDark ? NSColor(white: 0.25, alpha: 1) : .black
                    }
                    color.setFill()
                    NSBezierPath(ovalIn: rect).fill()
                }
            }
            if let countText {
                let textColor: NSColor = isAlert ? .labelColor : .black
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let size = (countText as NSString).size(withAttributes: attributes)
                (countText as NSString).draw(at: CGPoint(x: gridSize + 5, y: (height - size.height) / 2), withAttributes: attributes)
            }
            return true
        }
        // Template images follow the menu bar's light/dark and highlight state.
        image.isTemplate = !isAlert
        return image
    }
}
