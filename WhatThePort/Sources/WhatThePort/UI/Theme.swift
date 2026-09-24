import AppKit
import CoreText
import SwiftUI

enum Theme {
    static let text1 = adaptive(light: 0x1D1D22, dark: 0xF5F5F7)
    static let text2 = adaptive(light: 0x1D1D22, dark: 0xEBEBF5, lightAlpha: 0.72, darkAlpha: 0.6)
    static let text3 = adaptive(light: 0x1D1D22, dark: 0xEBEBF5, lightAlpha: 0.62, darkAlpha: 0.4)
    static let separator = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.12, darkAlpha: 0.08)
    static let fill = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.08)
    static let hover = fill
    static let subtleFill = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.04, darkAlpha: 0.04)
    static let memoryTrack = adaptive(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.05)
    static let amber = adaptive(light: 0x966000, dark: 0xFFB224)
    static let red = adaptive(light: 0xC52D24, dark: 0xFF453A)
    static let softRed = adaptive(light: 0xBA3028, dark: 0xFF6961)
    /// Text on solid primary buttons and selected checkboxes.
    static let onPrimary = adaptive(light: 0xFAFAFC, dark: 0x0B0D12)
    static let windowBackground = adaptive(light: 0xF5F5F7, dark: 0x1E1E21)
    static let popoverBackground = adaptive(light: 0xF5F5F7, dark: 0x202024)
    static let snapshotBackground = adaptive(light: 0xE5E7EB, dark: 0x0B0D12)

    /// Port identity colors avoid the red, amber, and green status families.
    private static let portColors: [Color] = [
        adaptive(light: 0x126B8D, dark: 0x6EC7ED), // sky
        adaptive(light: 0x704CB0, dark: 0xB599F0), // lavender
        adaptive(light: 0xA23682, dark: 0xEB9CD4), // pink
        adaptive(light: 0x405CBC, dark: 0x7D9CF2), // periwinkle
        adaptive(light: 0x096D75, dark: 0x7DDBE0), // cyan
        adaptive(light: 0x87449E, dark: 0xD9A3F2), // lilac
        adaptive(light: 0x4C627D, dark: 0xABC2E0), // slate
    ]

    static func portColor(at index: Int) -> Color {
        portColors[index % portColors.count]
    }

    /// Resolve at drawing time so open windows follow macOS appearance changes.
    static func adaptive(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    static let popoverWidth: CGFloat = 400
    static let inset: CGFloat = 16

    // Three sizes (28 display, 13 body, 11 caption) and two weights.
    static let display = Font.custom("GeistMono-Medium", fixedSize: 28)
    /// Display size for names rather than numbers.
    static let displaySans = Font.custom("Geist-Medium", fixedSize: 28)
    static let body = Font.custom("Geist-Regular", fixedSize: 13)
    static let bodyMedium = Font.custom("Geist-Medium", fixedSize: 13)
    static let caption = Font.custom("Geist-Regular", fixedSize: 11)
    static let mono = Font.custom("GeistMono-Regular", fixedSize: 13)
    static let monoMedium = Font.custom("GeistMono-Medium", fixedSize: 13)
    static let monoCaption = Font.custom("GeistMono-Regular", fixedSize: 11)
}

enum FontLoader {
    private static var registered = false

    /// Registers the bundled Geist fonts for this process. In the .app they live
    /// in Contents/Resources/Fonts; when running from `swift run` we fall back to
    /// the package's Resources folder.
    static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Fonts")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // UI
            .deletingLastPathComponent() // WhatThePort
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Resources/Fonts")
        for directory in [bundled, source].compactMap({ $0 }) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            let fonts = files.filter { $0.pathExtension == "ttf" }
            guard !fonts.isEmpty else { continue }
            for font in fonts {
                CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
            }
            return
        }
    }

    static func nsFont(_ name: String, size: CGFloat) -> NSFont {
        NSFont(name: name, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }
}

enum Format {
    /// Binary units, matching Activity Monitor and "16 GB" on a 16 GB Mac.
    static let megabyte: Double = 1_048_576
    static let gigabyte: Double = 1_073_741_824

    static func bytes(_ value: UInt64) -> (number: String, unit: String) {
        let mb = Double(value) / Format.megabyte
        if mb >= 1024 { return (String(format: "%.2f", mb / 1024), "GB") }
        return (String(format: "%.0f", mb), "MB")
    }

    static func bytesString(_ value: UInt64) -> String {
        let parts = bytes(value)
        return "\(parts.number) \(parts.unit)"
    }

    /// Compact total for the header: "4.9 GB" or "612 MB".
    static func total(_ value: UInt64) -> (number: String, unit: String) {
        let mb = Double(value) / Format.megabyte
        if mb >= 1024 {
            let gb = mb / 1024
            // Whole numbers read cleaner for capacities like "16 GB".
            let text = String(format: "%.1f", gb)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text, "GB")
        }
        return (String(format: "%.0f", mb), "MB")
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 {
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        return "\(hours / 24)d"
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours)h" : "\(hours / 24)d"
    }

    /// Whole numbers from 10% up; one decimal below that, so an idle-but-alive
    /// server reads "0.3%" rather than a flat "0%".
    static func percent(_ value: Double) -> String {
        if value <= 0 { return "0%" }
        if value < 0.1 { return "<0.1%" }
        if value < 10 { return String(format: "%.1f%%", value) }
        return "\(Int(value.rounded()))%"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'Today' h:mm a" : "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
