import Foundation
import XCTest
@testable import FastConvert

final class AppLanguageTests: XCTestCase {
    private var resourceURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("AppResources")
    }

    func testSupportedLanguagesAndRegionalPreferences() {
        XCTAssertEqual(AppLanguage.allCases.first, .english)
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), Set(["en", "zh-Hans", "fr", "ru", "es", "ja", "ko"]))
        let cases: [(String, AppLanguage)] = [
            ("en-GB", .english), ("zh-Hans-CN", .chinese), ("zh-TW", .chinese),
            ("fr-CA", .french), ("ru_RU", .russian), ("es-MX", .spanish),
            ("ja-JP", .japanese), ("KO-kr", .korean)
        ]
        for (identifier, expected) in cases {
            XCTAssertEqual(AppLanguage.preferred(in: [identifier]), expected, identifier)
        }
        XCTAssertEqual(AppLanguage.preferred(in: ["de-DE", "fr-FR", "en"]), .french)
        XCTAssertEqual(AppLanguage.preferred(in: ["ar", "de-DE"]), .english)
        XCTAssertEqual(AppLanguage.preferred(in: []), .english)
        XCTAssertEqual(AppLanguage.preferred(in: ["french", "russian"]), .english)
    }

    func testActualCatalogsAndEveryFormattedMessage() throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let expression = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l)?[@df]|%%"#)
        for language in AppLanguage.allCases {
            let data = try Data(contentsOf: resourceURL.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings"))
            let catalog = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertEqual(catalog.count, 385, language.rawValue)
            XCTAssertEqual(language.text("添加视频", in: bundle), catalog["添加视频"])
            XCTAssertEqual(language.text("__unknown_key__", in: bundle), "__unknown_key__")
            for (key, translation) in catalog {
                // Exercise actual strings and printf arguments through Foundation;
                // the validator separately enforces argument position/type parity.
                let format = language == .english ? translation : AppLanguage.english.text(key, in: bundle)
                let matches = expression.matches(in: format, range: NSRange(format.startIndex..., in: format))
                let arguments: [CVarArg] = matches.compactMap { match in
                    let token = (format as NSString).substring(with: match.range)
                    if token == "%%" { return nil }
                    if token.hasSuffix("@") { return "sample.mp4" }
                    if token.hasSuffix("f") { return 1.5 }
                    return 2
                }
                let rendered = String(format: language.text(key, in: bundle), locale: language.locale, arguments: arguments)
                XCTAssertFalse(rendered.isEmpty, "\(language.rawValue): \(key)")
                if arguments.isEmpty { XCTAssertEqual(rendered, translation) }
            }
        }
    }

    func testEnglishFallbackWhenSelectedCatalogIsMissingAKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for language in ["en", "fr"] {
            let directory = root.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let contents = language == "en" ? "\"known\" = \"English fallback\";" : "\"other\" = \"Autre\";"
            try contents.write(to: directory.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        let bundle = try XCTUnwrap(Bundle(url: root))
        XCTAssertEqual(AppLanguage.french.text("known", in: bundle), "English fallback")
        XCTAssertEqual(AppLanguage.korean.text("known", in: bundle), "English fallback")
        XCTAssertEqual(AppLanguage.french.text("other", in: bundle), "Autre")
    }

    func testListsAndFileSizesUseSelectedLanguage() {
        XCTAssertEqual(AppLanguage.english.list(["Trim", "Crop"]), "Trim and Crop")
        XCTAssertEqual(AppLanguage.french.list(["A", "B"]), "A et B")
        XCTAssertEqual(AppLanguage.spanish.list(["A", "B"]), "A y B")
        XCTAssertEqual(AppLanguage.russian.list(["A", "B"]), "A и B")
        XCTAssertTrue(AppLanguage.french.byteCount(1_500_000).contains("Mo"))
        XCTAssertTrue(AppLanguage.english.byteCount(1_500_000).contains("MB"))
    }

    func testPresentationRelocalizesWithoutReloadingMedia() {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: "NSArgumentDomain")
        defer { defaults.setVolatileDomain(original, forName: "NSArgumentDomain") }
        let presentation = VideoPresentation(duration: 65, fileSize: 1_500_000, thumbnail: nil, width: 1920, height: 1080)
        var domain = original
        domain["appLanguage"] = "en"
        defaults.setVolatileDomain(domain, forName: "NSArgumentDomain")
        let english = presentation.summary ?? ""
        domain["appLanguage"] = "fr"
        defaults.setVolatileDomain(domain, forName: "NSArgumentDomain")
        let french = presentation.summary ?? ""
        XCTAssertTrue(english.contains("MB"))
        XCTAssertTrue(french.contains("Mo"))
        XCTAssertTrue(french.contains("1920 × 1080 · 01:05"))
    }
}
