import Foundation
import Testing
@testable import WhatThePort

struct LocalizationTests {
    @Test func resolvesSavedAndSystemLanguages() {
        #expect(InterfaceLanguage.system.resolved(preferredLanguages: ["zh-Hans-US"]) == .simplifiedChinese)
        #expect(InterfaceLanguage.system.resolved(preferredLanguages: ["en-US"]) == .english)
        #expect(InterfaceLanguage.system.resolved(preferredLanguages: ["fr-FR"]) == .english)
        #expect(InterfaceLanguage.system.resolved(preferredLanguages: []) == .english)
        #expect(InterfaceLanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == .english)
        #expect(InterfaceLanguage.simplifiedChinese.resolved(preferredLanguages: ["en"]) == .simplifiedChinese)
    }

    @Test func loadsBothLanguagesAndPreservesUnknownUserContent() {
        #expect(L10n.text("Settings", language: .simplifiedChinese) == "设置")
        #expect(L10n.text("Settings", language: .english) == "Settings")
        #expect(L10n.text("my-project / npm run dev", language: .simplifiedChinese) == "my-project / npm run dev")
        let zh = String(format: L10n.text("Stop %d processes", language: .simplifiedChinese), 3)
        #expect(zh == "停止 3 个进程")
        let reordered = String(format: L10n.text("+%@ in %@", language: .simplifiedChinese), "500 MB", "10 分钟")
        #expect(reordered == "10 分钟内增加 500 MB")
        #expect(String(format: L10n.text("Found %d %@ running", language: .english), 1, "server") == "Found 1 server running")
        #expect(String(format: L10n.text("Found %d %@ running", language: .english), 2, "servers") == "Found 2 servers running")
    }

    @Test func resourceTablesHaveMatchingKeysAndFormatArguments() throws {
        func table(_ language: String) throws -> [String: String] {
            let name = try #require(L10n.resourceBundle.localizations.first {
                $0.caseInsensitiveCompare(language) == .orderedSame
            })
            let url = L10n.resourceBundle.bundleURL.appendingPathComponent("\(name).lproj/Localizable.strings")
            let data = try Data(contentsOf: url)
            return try #require(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String])
        }
        let english = try table("en")
        let chinese = try table("zh-Hans")
        #expect(Set(english.keys) == Set(chinese.keys))
        let pattern = try NSRegularExpression(pattern: "%([0-9]+\\$)?([@df])")
        func arguments(_ value: String) -> [String] {
            let range = NSRange(value.startIndex..., in: value)
            return pattern.matches(in: value, range: range).map { match in
                String(value[Range(match.range(at: 2), in: value)!])
            }.sorted()
        }
        for (key, englishValue) in english {
            let chineseValue = try #require(chinese[key])
            #expect(!chineseValue.isEmpty, "Empty translation for \(key)")
            #expect(englishValue == key)
            #expect(arguments(englishValue) == arguments(chineseValue), "Format mismatch for \(key)")
        }
    }
}
