import AppKit
import CoreText
import SwiftUI

enum Theme {
    static let text1 = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let text2 = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.6)
    static let text3 = Color(red: 235 / 255, green: 235 / 255, blue: 245 / 255).opacity(0.4)
    static let separator = Color.white.opacity(0.08)
    static let fill = Color.white.opacity(0.08)
    static let hover = Color.white.opacity(0.08)
    static let amber = Color(red: 1, green: 178 / 255, blue: 36 / 255)
    static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)
    static let softRed = Color(red: 1, green: 105 / 255, blue: 97 / 255)
    static let ink = Color(red: 11 / 255, green: 13 / 255, blue: 18 / 255)

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
