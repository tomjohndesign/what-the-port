import Foundation

/// Changes apply on restart so scans, sessions and windows retain their state.
enum InterfaceLanguage: String, CaseIterable {
    case system, simplifiedChinese = "zh-Hans", english = "en"

    var label: String {
        switch self {
        case .system: return L10n.text("System default")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    func resolved(preferredLanguages: [String]) -> InterfaceLanguage {
        guard self == .system else { return self }
        return preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english
    }
}

/// Explicit lookups in standard .lproj resources. English is the key and fallback;
/// names, commands, paths and machine-readable output never pass here.
enum L10n {
    static let language: InterfaceLanguage = {
        if TerminalCommand.isRequested { return .english }
        let arguments = CommandLine.arguments
        let override = arguments.firstIndex(of: "--ui-language").flatMap { index in
            index + 1 < arguments.count ? InterfaceLanguage(rawValue: arguments[index + 1]) : nil
        }
        let saved = UserDefaults.standard.string(forKey: Preferences.language)
        return (override ?? saved.flatMap(InterfaceLanguage.init(rawValue:)) ?? .system)
            .resolved(preferredLanguages: Locale.preferredLanguages)
    }()

    static var locale: Locale { Locale(identifier: language.rawValue) }

    // SwiftPM's generated accessor looks beside Bundle.main.bundleURL. The
    // packaged app instead keeps resources in the standard Contents/Resources.
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "WhatThePort_WhatThePort", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    private static let bundles: [InterfaceLanguage: Bundle] = {
        var result: [InterfaceLanguage: Bundle] = [:]
        for language in [InterfaceLanguage.english, .simplifiedChinese] {
            // SwiftPM normalizes zh-Hans.lproj to zh-hans.lproj. Use the bundle's
            // declared spelling rather than relying on filesystem case rules.
            if let name = resourceBundle.localizations.first(where: {
                $0.caseInsensitiveCompare(language.rawValue) == .orderedSame
            }), let bundle = Bundle(url: resourceBundle.bundleURL.appendingPathComponent("\(name).lproj")) {
                result[language] = bundle
            }
        }
        return result
    }()

    static func text(_ english: String, language: InterfaceLanguage = language) -> String {
        guard language != .english else { return english }
        return bundles[language]?.localizedString(forKey: english, value: english, table: nil) ?? english
    }

    static func format(_ english: String, _ arguments: CVarArg...) -> String {
        String(format: text(english), locale: locale, arguments: arguments)
    }

    /// GUI-only units. Format.duration remains unchanged for the terminal UI.
    static func duration(_ interval: TimeInterval, short: Bool = false) -> String {
        guard language == .simplifiedChinese else {
            return short ? Format.shortDuration(interval) : Format.duration(interval)
        }
        let minutes = Int(interval / 60)
        if minutes < 1 { return short ? format("%dm", 1) : text("<1m") }
        if minutes < 60 { return format("%dm", minutes) }
        let hours = minutes / 60
        if hours >= 24 { return format("%dd", hours / 24) }
        let rest = minutes % 60
        return short || rest == 0 ? format("%dh", hours) : format("%dh %dm", hours, rest)
    }

    static func time(_ date: Date) -> String {
        guard language == .simplifiedChinese else { return Format.time(date) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'今天' HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
