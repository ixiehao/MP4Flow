import Foundation

/// Stable resource identifiers are independent of translated menu labels.
/// Language changes do not alter the conversion queue or macOS preferences.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case chinese = "zh-Hans"
    case french = "fr"
    case russian = "ru"
    case spanish = "es"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: "简体中文"
        case .english: "English"
        case .french: "Français"
        case .russian: "Русский"
        case .spanish: "Español"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static var systemDefault: AppLanguage {
        preferred(in: Locale.preferredLanguages)
    }

    static func preferred(in identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            let language = identifier.replacingOccurrences(of: "_", with: "-")
                .lowercased().split(separator: "-").first.map(String.init) ?? ""
            if language == "zh" { return .chinese }
            if let supported = allCases.first(where: { $0.rawValue == language }) { return supported }
        }
        return .english
    }

    // Resolve resource bundles once, not for every label on every progress tick.
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues: allCases.compactMap { language in
        guard let bundle = language.bundle(in: .main) else { return nil }
        return (language, bundle)
    })

    private func bundle(in resources: Bundle) -> Bundle? {
        resources.url(forResource: rawValue, withExtension: "lproj").flatMap(Bundle.init(url:))
    }

    func text(_ key: String) -> String {
        let fallback = Self.bundles[.english]?.localizedString(forKey: key, value: key, table: nil) ?? key
        return Self.bundles[self]?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
    }

    /// Allows tests to exercise actual catalogs instead of silently testing keys
    /// when XCTest's main bundle has no application resources.
    func text(_ key: String, in resources: Bundle) -> String {
        let fallback = Self.english.bundle(in: resources)?.localizedString(forKey: key, value: key, table: nil) ?? key
        return bundle(in: resources)?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
    }

    func format(_ key: String, arguments: [CVarArg]) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    func list(_ items: [String]) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: items) ?? items.joined(separator: ", ")
    }

    func byteCount(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }
}

/// Dynamic state strings are not `LocalizedStringKey` values, so they use this
/// helper while static SwiftUI labels are resolved by the view locale.
enum L10n {
    private static var language: AppLanguage {
        let identifier = UserDefaults.standard.string(forKey: "appLanguage")
        return AppLanguage(rawValue: identifier ?? "") ?? AppLanguage.systemDefault
    }

    static func text(_ key: String) -> String { language.text(key) }
    static func format(_ key: String, _ arguments: CVarArg...) -> String { language.format(key, arguments: arguments) }
    static func list(_ items: [String]) -> String { language.list(items) }
    static func byteCount(_ bytes: Int64) -> String { language.byteCount(bytes) }
}
