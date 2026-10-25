import AppKit
import XCTest
@testable import FastConvert

final class MenuBarLocalizationTests: XCTestCase {
    private var resourceURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("AppResources")
    }

    func testEveryLanguageShipsNativeMenuTitlesAndFormatArguments() throws {
        let keys = [
            "menu.file", "menu.edit", "menu.view", "menu.window", "menu.help", "menu.services",
            "menu.close", "menu.minimize", "menu.zoom", "menu.bringAllToFront",
            "menu.enterFullScreen", "menu.exitFullScreen", "menu.undo", "menu.redo",
            "menu.cut", "menu.copy", "menu.paste", "menu.pasteAndMatchStyle", "menu.delete", "menu.selectAll",
            "menu.about", "menu.settings", "menu.hide", "menu.hideOthers", "menu.showAll", "menu.quit"
        ]
        let formatKeys: Set<String> = ["menu.about", "menu.hide", "menu.quit"]
        for language in AppLanguage.allCases {
            let data = try Data(contentsOf: resourceURL.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings"))
            let catalog = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for key in keys {
                let value = try XCTUnwrap(catalog[key], "\(language.rawValue): \(key)")
                XCTAssertFalse(value.isEmpty)
                XCTAssertNotEqual(value, key)
                if formatKeys.contains(key) {
                    XCTAssertEqual(value.components(separatedBy: "%@").count - 1, 1, "\(language.rawValue): \(key)")
                    let formatted = String(format: value, locale: language.locale, arguments: ["MP4Flow"])
                    XCTAssertTrue(formatted.contains("MP4Flow"))
                    XCTAssertFalse(formatted.contains("%@"))
                }
            }
        }
    }

    @MainActor
    func testRelocalizesUnorderedNativeMenusWithoutChangingCommandBehavior() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let file = submenu(in: main, title: "unrecognized file heading")
        let help = submenu(in: main, title: "unrecognized help heading")
        let app = submenu(in: main, title: "MP4Flow")
        let view = submenu(in: main, title: "unrecognized view heading")
        let edit = submenu(in: main, title: "unrecognized edit heading")
        let window = submenu(in: main, title: "unrecognized window heading")
        let close = item(in: file, action: "performClose:", key: "w")
        let cut = item(in: edit, action: "cut:", key: "x")
        let undo = item(in: edit, action: "undo:", key: "z")
        undo.title = UndoManager().undoMenuItemTitle
        let fullScreen = item(in: view, action: "toggleFullScreen:", key: "f")
        let minimize = item(in: window, action: "performMiniaturize:", key: "m")
        let quit = item(in: app, action: "terminate:", key: "q")

        let target = NSObject()
        let payload = NSObject()
        cut.target = target
        cut.representedObject = payload
        cut.keyEquivalentModifierMask = [.command, .shift]
        cut.isEnabled = false
        cut.state = .on
        let originalAction = cut.action

        for language in AppLanguage.allCases {
            localizer.localize(main, language: language, windowsMenu: window, helpMenu: help)
            for (menu, key) in [(file, "menu.file"), (edit, "menu.edit"), (view, "menu.view"), (window, "menu.window"), (help, "menu.help")] {
                XCTAssertEqual(menu.title, displayedTitle(language.text(key, in: bundle)), language.rawValue)
                XCTAssertEqual(main.items.first { $0.submenu === menu }?.title, menu.title)
            }
            for (command, key) in [(close, "menu.close"), (cut, "menu.cut"), (undo, "menu.undo"), (fullScreen, "menu.enterFullScreen"), (minimize, "menu.minimize")] {
                XCTAssertEqual(command.title, displayedTitle(language.text(key, in: bundle)), language.rawValue)
            }
            XCTAssertEqual(quit.title, displayedTitle(String(format: language.text("menu.quit", in: bundle), locale: language.locale, arguments: ["MP4Flow"])))
            XCTAssertEqual(app.title, "MP4Flow")
            XCTAssertTrue(cut.target === target)
            XCTAssertTrue((cut.representedObject as AnyObject?) === payload)
            XCTAssertEqual(cut.action, originalAction)
            XCTAssertEqual(cut.keyEquivalent, "x")
            XCTAssertEqual(cut.keyEquivalentModifierMask, [.command, .shift])
            XCTAssertFalse(cut.isEnabled)
            XCTAssertEqual(cut.state, .on)
        }
    }

    @MainActor
    func testPreservesDynamicUndoWindowTitlesAndServiceProviderItems() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let edit = submenu(in: main, title: "edit")
        let undo = item(in: edit, action: "undo:")
        undo.title = "Undo Rename ‘My Video’"
        let redo = item(in: edit, action: "redo:")
        redo.title = "Redo Trim Clip"
        let custom = item(in: edit, action: "customAction:")
        custom.title = "An application-owned action"
        let window = submenu(in: main, title: "window")
        let document = item(in: window, action: "makeKeyAndOrderFront:")
        document.title = "Copy — my video.mp4"
        let app = submenu(in: main, title: "MP4Flow")
        let services = submenu(in: app, title: "system services")
        let provider = item(in: services, action: "copy:")
        provider.title = "Provider-owned Copy service"

        localizer.localize(main, language: .french, windowsMenu: window, servicesMenu: services)

        XCTAssertEqual(undo.title, "Undo Rename ‘My Video’")
        XCTAssertEqual(redo.title, "Redo Trim Clip")
        XCTAssertEqual(custom.title, "An application-owned action")
        XCTAssertEqual(document.title, "Copy — my video.mp4")
        XCTAssertEqual(provider.title, "Provider-owned Copy service")
        XCTAssertEqual(services.title, displayedTitle(AppLanguage.french.text("menu.services", in: bundle)))
    }

    @MainActor
    func testFullScreenTitleTracksWindowStateAndNewMenuInstances() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        for isFullScreen in [false, true, false] {
            // SwiftUI may replace the entire menu tree when commands change.
            let main = NSMenu(title: "replacement")
            let view = submenu(in: main, title: "opaque")
            let command = item(in: view, action: "toggleFullScreen:", key: "f")
            localizer.localize(main, language: .japanese, isFullScreen: isFullScreen)
            let key = isFullScreen ? "menu.exitFullScreen" : "menu.enterFullScreen"
            XCTAssertEqual(command.title, AppLanguage.japanese.text(key, in: bundle))
            XCTAssertEqual(view.title, AppLanguage.japanese.text("menu.view", in: bundle))
            localizer.localize(main, language: .japanese, isFullScreen: isFullScreen)
            XCTAssertEqual(command.title, AppLanguage.japanese.text(key, in: bundle))
        }
    }

    @MainActor
    func testNonbreakingSpaceTitlesDoNotCauseRepeatedWrites() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let window = submenu(in: main, title: "window")
        let minimize = TitleCountingMenuItem(title: "opaque", action: NSSelectorFromString("performMiniaturize:"), keyEquivalent: "m")
        window.addItem(minimize)
        minimize.titleWriteCount = 0

        XCTAssertEqual(AppLanguage.russian.text("menu.minimize", in: bundle), "Убрать в\u{00A0}Dock")
        localizer.localize(main, language: .russian, windowsMenu: window)
        XCTAssertEqual(minimize.title, "Убрать в Dock")
        XCTAssertEqual(minimize.titleWriteCount, 1)

        for _ in 0..<5 {
            localizer.localize(main, language: .russian, windowsMenu: window)
        }
        XCTAssertEqual(minimize.titleWriteCount, 1, "An unchanged menu must not post repeated title-change notifications")

        localizer.localize(main, language: .english, windowsMenu: window)
        XCTAssertEqual(minimize.title, "Minimize")
        XCTAssertEqual(minimize.titleWriteCount, 2)
    }

    @MainActor
    func testViewHeadingIsRecognizedBeforeFullScreenCommandIsAdded() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let view = submenu(in: main, title: "opaque")
        _ = item(in: view, action: "toggleTabBar:")
        _ = item(in: view, action: "toggleTabOverview:")
        localizer.localize(main, language: .korean)
        XCTAssertEqual(view.title, AppLanguage.korean.text("menu.view", in: bundle))
        let fullScreen = item(in: view, action: "toggleFullScreen:")
        localizer.localize(main, language: .korean)
        XCTAssertEqual(fullScreen.title, AppLanguage.korean.text("menu.enterFullScreen", in: bundle))
    }

    @MainActor
    func testEmptyViewPlaceholderUsesOnlyExactShippedCaptions() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        for sourceLanguage in AppLanguage.allCases {
            let main = NSMenu(title: "test")
            let view = submenu(in: main, title: sourceLanguage.text("menu.view", in: bundle))
            let unrelated = submenu(in: main, title: "Custom View Tools")
            let nonemptyCustom = submenu(in: main, title: "View")
            _ = item(in: nonemptyCustom, action: "customAction:")
            localizer.localize(main, language: .korean)
            XCTAssertEqual(view.title, AppLanguage.korean.text("menu.view", in: bundle))
            XCTAssertEqual(view.numberOfItems, 0)
            XCTAssertEqual(unrelated.title, "Custom View Tools")
            XCTAssertEqual(nonemptyCustom.title, "View")
        }
    }

    @MainActor
    func testPublicRolesAndActionsOverrideViewCaptionFallback() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let window = submenu(in: main, title: "View")
        let edit = submenu(in: main, title: "View")
        _ = item(in: edit, action: "copy:")
        localizer.localize(main, language: .english, windowsMenu: window)
        XCTAssertEqual(window.title, "Window")
        XCTAssertEqual(edit.title, "Edit")
    }

    @MainActor
    func testForwardedCommandsUseObservedPublicSelectorIdentifiers() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let edit = submenu(in: main, title: "opaque")
        let view = submenu(in: main, title: "opaque")
        var commands: [(NSMenuItem, String)] = []
        for (selector, key) in [
            ("undo:", "menu.undo"), ("redo:", "menu.redo"), ("cut:", "menu.cut"),
            ("copy:", "menu.copy"), ("paste:", "menu.paste"), ("delete:", "menu.delete"),
            ("selectAll:", "menu.selectAll")
        ] {
            let command = item(in: edit, action: "forwardCommand:")
            command.identifier = NSUserInterfaceItemIdentifier(selector)
            command.title = AppLanguage.chinese.text(key, in: bundle)
            command.setAccessibilityTitle(command.title)
            command.setAccessibilityLabel(command.title)
            commands.append((command, key))
        }
        let tabBar = item(in: view, action: "forwardCommand:")
        tabBar.identifier = NSUserInterfaceItemIdentifier("toggleTabBar:")
        let fullScreen = item(in: view, action: "forwardCommand:")
        fullScreen.identifier = NSUserInterfaceItemIdentifier("toggleFullScreen:")
        commands.append((fullScreen, "menu.enterFullScreen"))

        localizer.localize(main, language: .english)

        XCTAssertEqual(edit.title, "Edit")
        XCTAssertEqual(view.title, "View")
        for (command, key) in commands {
            XCTAssertEqual(command.title, displayedTitle(AppLanguage.english.text(key, in: bundle)))
            XCTAssertEqual(command.accessibilityTitle(), command.title)
            XCTAssertEqual(command.accessibilityLabel(), command.title)
            XCTAssertEqual(command.action, NSSelectorFromString("forwardCommand:"))
        }
    }

    @MainActor
    func testUncooperativeAccessibilityTitleIsAttemptedOnlyOncePerTranslation() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let edit = submenu(in: main, title: "opaque")
        let copy = FixedAccessibilityTitleMenuItem(title: "拷贝", action: NSSelectorFromString("copy:"), keyEquivalent: "c")
        edit.addItem(copy)
        copy.accessibilityTitleWriteCount = 0

        for _ in 0..<5 { localizer.localize(main, language: .english) }
        XCTAssertEqual(copy.accessibilityTitleWriteCount, 1)
        XCTAssertEqual(copy.title, "Copy")
        XCTAssertEqual(copy.accessibilityLabel(), "Copy")
        localizer.localize(main, language: .french)
        XCTAssertEqual(copy.accessibilityTitleWriteCount, 2)
    }

    @MainActor
    func testDynamicUndoClearsPreviouslyLocalizedAccessibilityLabels() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let main = NSMenu(title: "test")
        let edit = submenu(in: main, title: "opaque")
        let undo = item(in: edit, action: "undo:")
        undo.title = AppLanguage.chinese.text("menu.undo", in: bundle)
        undo.setAccessibilityTitle(undo.title)
        undo.setAccessibilityLabel(undo.title)
        localizer.localize(main, language: .english)
        XCTAssertEqual(undo.accessibilityLabel(), "Undo")

        undo.title = "Undo Typing"
        localizer.localize(main, language: .english)
        XCTAssertEqual(undo.title, "Undo Typing")
        XCTAssertEqual(undo.accessibilityTitle(), "Undo Typing")
        XCTAssertEqual(undo.accessibilityLabel(), "Undo Typing")
    }

    @MainActor
    func testNativeValidationResetAllowsAccessibilityToBeLocalizedAgain() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let menu = NSMenu(title: "MP4Flow")
        let hide = FixedAccessibilityTitleMenuItem(title: "隐藏MP4Flow", action: NSSelectorFromString("hide:"), keyEquivalent: "h")
        menu.addItem(hide)
        localizer.localize(menu, language: .french)
        XCTAssertEqual(hide.accessibilityTitleWriteCount, 1)
        hide.title = "隐藏MP4Flow"
        hide.setAccessibilityLabel("隐藏MP4Flow")
        localizer.localize(menu, language: .french)
        XCTAssertEqual(hide.accessibilityTitleWriteCount, 2, "Native validation invalidates the previous AX attempt")
        XCTAssertEqual(hide.title, "Masquer MP4Flow")
        XCTAssertEqual(hide.accessibilityLabel(), "Masquer MP4Flow")
        localizer.localize(menu, language: .french)
        XCTAssertEqual(hide.accessibilityTitleWriteCount, 2, "Stable items must still avoid repeated writes")
    }

    @MainActor
    func testSettingsMenuPreservesItsActionAndShortcutAcrossLanguages() async throws {
        let bundle = try XCTUnwrap(Bundle(url: resourceURL))
        let localizer = MenuBarLocalization(resources: bundle)
        let menu = NSMenu(title: "MP4Flow")
        let settings = item(in: menu, action: "showSettingsWindow:", key: ",")
        for language in AppLanguage.allCases {
            localizer.localize(menu, language: language)
            XCTAssertEqual(settings.title, language.text("menu.settings", in: bundle))
            XCTAssertEqual(settings.action, NSSelectorFromString("showSettingsWindow:"))
            XCTAssertEqual(settings.keyEquivalent, ",")
        }
    }

    @MainActor
    private func displayedTitle(_ title: String) -> String {
        let native = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        native.title = title
        return native.title
    }

    @MainActor
    private func submenu(in parent: NSMenu, title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    @MainActor
    private func item(in menu: NSMenu, action: String, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: "opaque", action: NSSelectorFromString(action), keyEquivalent: key)
        menu.addItem(item)
        return item
    }
}

@MainActor
private final class TitleCountingMenuItem: NSMenuItem {
    var titleWriteCount = 0

    override var title: String {
        get { super.title }
        set {
            titleWriteCount += 1
            super.title = newValue
        }
    }
}

@MainActor
private final class FixedAccessibilityTitleMenuItem: NSMenuItem {
    var accessibilityTitleWriteCount = 0

    override func accessibilityTitle() -> String? { "Original AX title" }

    override func setAccessibilityTitle(_ title: String?) {
        accessibilityTitleWriteCount += 1
        super.setAccessibilityTitle(title)
    }
}
