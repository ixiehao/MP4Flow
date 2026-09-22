import Foundation

/// The app language is chosen inside MP4Flow so people can switch between
/// Simplified Chinese and English without changing their macOS language.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .chinese : .english
    }

    private var localizationBundle: Bundle {
        guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    func text(_ key: String) -> String {
        localizationBundle.localizedString(forKey: key, value: key, table: nil)
    }

    func format(_ key: String, arguments: [CVarArg]) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
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
}
