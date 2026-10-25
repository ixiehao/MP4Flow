import AppKit

/// Relabels existing native commands without replacing their targets, actions,
/// validation, keyboard equivalents, delegates, or first-responder behavior.
@MainActor
final class MenuBarLocalization: NSObject {
    static let shared = MenuBarLocalization()

    private var language = AppLanguage.systemDefault
    private let resources: Bundle?
    private let systemUndoTitle: String
    private let systemRedoTitle: String
    private var isInstalled = false
    private var isRefreshing = false
    private var refreshQueued = false
    private let pendingMenus = NSHashTable<NSMenu>.weakObjects()
    private let accessibilityTitleAttempts = NSMapTable<NSMenuItem, NSString>.weakToStrongObjects()
    private let localizedAccessibilityItems = NSHashTable<NSMenuItem>.weakObjects()

    /// An explicit bundle lets tests exercise the shipped catalogs.
    init(resources: Bundle? = nil) {
        self.resources = resources
        let undoManager = UndoManager()
        systemUndoTitle = undoManager.undoMenuItemTitle
        systemRedoTitle = undoManager.redoMenuItemTitle
        super.init()
    }

    func install(language: AppLanguage) {
        self.language = language
        if !isInstalled {
            isInstalled = true
            let center = NotificationCenter.default
            for name in [
                NSMenu.didAddItemNotification,
                NSMenu.didRemoveItemNotification,
                NSMenu.didChangeItemNotification,
                NSMenu.didEndTrackingNotification,
                NSApplication.didFinishLaunchingNotification,
                NSApplication.didBecomeActiveNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ] {
                center.addObserver(self, selector: #selector(queueRefresh(_:)), name: name, object: nil)
            }
            center.addObserver(self, selector: #selector(menuWillTrack(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        }
        refresh()
        scheduleRefresh()
    }

    func update(language: AppLanguage) {
        install(language: language)
    }

    @objc private func queueRefresh(_ notification: Notification) {
        guard !isRefreshing else { return }
        if let menu = notification.object as? NSMenu, containsNativeCommands(menu) {
            // Native validation and SwiftUI may populate a tracked menu lazily.
            // Apply to the notified instance as well as the main-menu model.
            refresh(additionalMenu: menu)
            pendingMenus.add(menu)
        }
        scheduleRefresh()
    }

    @objc private func menuWillTrack(_ notification: Notification) {
        guard !isRefreshing else { return }
        let menu = notification.object as? NSMenu
        if let menu, containsNativeCommands(menu), !isServicesMenu(menu) {
            // AppKit validates commands while opening a menu and can replace
            // SwiftUI's visible menu copy after the first synchronous pass.
            pendingMenus.add(menu)
        }
        refresh(additionalMenu: menu)
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        guard !isRefreshing, !refreshQueued else { return }
        refreshQueued = true
        // Coalesce SwiftUI's remove/add/change notifications into one pass after
        // its menu rebuild. Common modes also cover native menu tracking.
        RunLoop.main.perform(inModes: [.common, .eventTracking]) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refreshQueued = false
                self.refresh()
                let menus = self.pendingMenus.allObjects
                self.pendingMenus.removeAllObjects()
                for menu in menus {
                    self.refresh(additionalMenu: menu)
                }
            }
        }
    }

    private func refresh(additionalMenu: NSMenu? = nil) {
        guard let mainMenu = NSApp.mainMenu else { return }
        let applicationName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        var menus = [mainMenu]
        if let additionalMenu, additionalMenu !== mainMenu, containsNativeCommands(additionalMenu), !isServicesMenu(additionalMenu) {
            menus.append(additionalMenu)
        }
        for menu in menus {
            localize(
                menu,
                language: language,
                windowsMenu: NSApp.windowsMenu,
                helpMenu: NSApp.helpMenu,
                servicesMenu: NSApp.servicesMenu,
                isFullScreen: (NSApp.keyWindow ?? NSApp.mainWindow)?.styleMask.contains(.fullScreen) == true,
                applicationName: applicationName
            )
        }
    }

    /// Kept separate from installation so native menu fixtures can be verified
    /// without replacing the application's real main menu or invoking commands.
    func localize(
        _ mainMenu: NSMenu,
        language: AppLanguage,
        windowsMenu: NSMenu? = nil,
        helpMenu: NSMenu? = nil,
        servicesMenu: NSMenu? = nil,
        isFullScreen: Bool = false,
        applicationName: String = "MP4Flow"
    ) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for item in mainMenu.items {
            guard let submenu = item.submenu else { continue }
            if let key = headingKey(for: submenu, windowsMenu: windowsMenu, helpMenu: helpMenu, emptyMenuTitle: item.title) {
                if let title = translated(key, language: language) {
                    setTitle(title, on: item)
                    setTitle(title, on: submenu)
                }
            }
        }

        var visited = Set<ObjectIdentifier>()
        localizeItems(
            in: mainMenu,
            language: language,
            servicesMenu: servicesMenu,
            isFullScreen: isFullScreen,
            applicationName: applicationName,
            visited: &visited
        )
    }

    private func headingKey(for submenu: NSMenu, windowsMenu: NSMenu?, helpMenu: NSMenu?, emptyMenuTitle: String? = nil) -> String? {
        if submenu === windowsMenu { return "menu.window" }
        if submenu === helpMenu { return "menu.help" }
        // Prefer public responder actions for the remaining standard menus;
        // no item positions or private SwiftUI identifiers are assumed.
        let actions = Set(submenu.items.compactMap(nativeAction))
        if !actions.isDisjoint(with: ["hide:", "terminate:", "hideOtherApplications:"]) { return nil }
        if !actions.isDisjoint(with: ["performMiniaturize:", "miniaturize:", "arrangeInFront:"]) { return "menu.window" }
        if !actions.isDisjoint(with: ["cut:", "copy:", "paste:", "selectAll:"]) { return "menu.edit" }
        if !actions.isDisjoint(with: ["performClose:", "newDocument:", "openDocument:", "saveDocument:"]) { return "menu.file" }
        if !actions.isDisjoint(with: ["toggleFullScreen:", "toggleToolbarShown:", "toggleTabBar:", "toggleTabOverview:"]) { return "menu.view" }
        if actions.contains("showHelp:") { return "menu.help" }
        // The fixed application menu has no user-created top-level menus. Its
        // built-in View placeholder can be empty until opened, with no public
        // role/action yet. Only for that empty heading, accept an exact shipped
        // View caption; public roles/actions above always take precedence.
        if submenu.items.allSatisfy(\.isSeparatorItem), let emptyMenuTitle,
           AppLanguage.allCases.contains(where: { translated("menu.view", language: $0) == emptyMenuTitle }) {
            return "menu.view"
        }
        return nil
    }

    private func localizeItems(
        in menu: NSMenu,
        language: AppLanguage,
        servicesMenu: NSMenu?,
        isFullScreen: Bool,
        applicationName: String,
        visited: inout Set<ObjectIdentifier>
    ) {
        guard menu !== servicesMenu, visited.insert(ObjectIdentifier(menu)).inserted else { return }
        for item in menu.items where !item.isSeparatorItem {
            if let submenu = item.submenu, submenu === servicesMenu {
                if let title = translated("menu.services", language: language) {
                    setTitle(title, on: item)
                    setTitle(title, on: submenu)
                }
                continue // Service providers own the titles below this heading.
            }

            if let action = nativeAction(item) {
                var key = Self.actionKeys[action]
                if action == "toggleFullScreen:" {
                    let targetIsFullScreen = (item.target as? NSWindow)?.styleMask.contains(.fullScreen) ?? isFullScreen
                    key = targetIsFullScreen ? "menu.exitFullScreen" : "menu.enterFullScreen"
                }
                if let key, !shouldTranslate(item, key: key) {
                    clearLocalizedAccessibility(on: item)
                } else if let key, let template = translated(key, language: language) {
                    let title: String
                    if Self.applicationNameKeys.contains(key) {
                        title = String(format: template, locale: language.locale, arguments: [applicationName])
                    } else {
                        title = template
                    }
                    setTitle(title, on: item)
                }
            }
            if let submenu = item.submenu {
                localizeItems(
                    in: submenu,
                    language: language,
                    servicesMenu: servicesMenu,
                    isFullScreen: isFullScreen,
                    applicationName: applicationName,
                    visited: &visited
                )
            }
        }
    }

    private func shouldTranslate(_ item: NSMenuItem, key: String) -> Bool {
        guard key == "menu.undo" || key == "menu.redo" else { return true }
        // Preserve "Undo Typing", custom action names, and unfamiliar system
        // titles. A fresh manager supplies the OS language's plain base title.
        let systemTitle = key == "menu.undo" ? systemUndoTitle : systemRedoTitle
        if item.title == nativeTitle(systemTitle) { return true }
        return AppLanguage.allCases.contains { translated(key, language: $0).map(nativeTitle) == item.title }
    }

    private func nativeAction(_ item: NSMenuItem) -> String? {
        if let action = item.action.map(NSStringFromSelector), Self.nativeActions.contains(action) {
            return action
        }
        // Observed SwiftUI command items expose the public selector as their
        // NSUserInterfaceItemIdentifier while forwarding through an opaque
        // action. Accept only exact public selectors already in our allowlist.
        if let identifier = item.identifier?.rawValue, Self.nativeActions.contains(identifier) {
            return identifier
        }
        return nil
    }

    private func containsNativeCommands(_ menu: NSMenu) -> Bool {
        menu.items.contains { nativeAction($0) != nil }
    }

    private func isServicesMenu(_ menu: NSMenu) -> Bool {
        var ancestor: NSMenu? = menu
        var visited = Set<ObjectIdentifier>()
        while let current = ancestor, visited.insert(ObjectIdentifier(current)).inserted {
            if current === NSApp.servicesMenu { return true }
            ancestor = current.supermenu
        }
        return false
    }

    private func translated(_ key: String, language: AppLanguage) -> String? {
        let value = resources.map { language.text(key, in: $0) } ?? language.text(key)
        return value == key || value.isEmpty ? nil : value
    }

    private func setTitle(_ title: String, on item: NSMenuItem) {
        let title = nativeTitle(title)
        if item.title != title {
            item.title = title
            // A native validation pass may restore the system title and its
            // AX value. The cache only applies while that title stays intact.
            accessibilityTitleAttempts.removeObject(forKey: item)
        }
        // SwiftUI can retain an explicit accessibility title/label after its
        // native menu item's display title changes. Keep the same known command
        // name available to VoiceOver without changing its action or shortcut.
        let beforeTitle = item.accessibilityTitle()
        let beforeLabel = item.accessibilityLabel()
        let shouldAttemptTitle = beforeTitle != title && (accessibilityTitleAttempts.object(forKey: item) as String?) != title
        if shouldAttemptTitle {
            accessibilityTitleAttempts.setObject(title as NSString, forKey: item)
            localizedAccessibilityItems.add(item)
            item.setAccessibilityTitle(title)
            if item.accessibilityTitle() != title {
                // macOS 27 SwiftUI menu items ignore the modern title setter.
                // This public compatibility API overrides an individual AX
                // attribute without replacing the native command or swizzling.
                // An attempt is cached even if unsupported, so it cannot churn.
                _ = item.accessibilitySetOverrideValue(title, forAttribute: .title)
            }
        }
        if beforeLabel != title {
            localizedAccessibilityItems.add(item)
            item.setAccessibilityLabel(title)
        }
    }

    private func clearLocalizedAccessibility(on item: NSMenuItem) {
        guard localizedAccessibilityItems.contains(item) else { return }
        // A responder-owned title such as "Undo Typing" must be exposed as-is.
        // Explicit nil disables the native AX name rather than restoring its
        // fallback, so clear our override then follow the unchanged native text.
        let title = item.title
        guard (accessibilityTitleAttempts.object(forKey: item) as String?) != title else { return }
        _ = item.accessibilitySetOverrideValue(nil, forAttribute: .title)
        accessibilityTitleAttempts.removeObject(forKey: item)
        setTitle(title, on: item)
        accessibilityTitleAttempts.setObject(title as NSString, forKey: item)
    }

    private func setTitle(_ title: String, on menu: NSMenu) {
        let title = nativeTitle(title)
        if menu.title != title { menu.title = title }
    }

    private func nativeTitle(_ title: String) -> String {
        // NSMenuItem replaces U+00A0 in its setter, while NSMenu preserves it.
        // Compare their shared rendered form to avoid rewriting on every pass.
        // Other spacing (including narrow NBSP) is preserved by AppKit.
        title.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static let applicationNameKeys: Set<String> = ["menu.about", "menu.hide", "menu.quit"]
    private static let nativeActions = Set(actionKeys.keys).union([
        "toggleFullScreen:", "toggleToolbarShown:", "toggleTabBar:", "toggleTabOverview:",
        "newDocument:", "openDocument:", "saveDocument:", "showHelp:"
    ])
    private static let actionKeys: [String: String] = [
        "showSettingsWindow:": "menu.settings", "showPreferencesWindow:": "menu.settings",
        "performClose:": "menu.close",
        "performMiniaturize:": "menu.minimize", "miniaturize:": "menu.minimize",
        "performZoom:": "menu.zoom", "zoom:": "menu.zoom",
        "arrangeInFront:": "menu.bringAllToFront",
        "undo:": "menu.undo", "redo:": "menu.redo",
        "cut:": "menu.cut", "copy:": "menu.copy", "paste:": "menu.paste",
        "pasteAsPlainText:": "menu.pasteAndMatchStyle",
        "delete:": "menu.delete", "selectAll:": "menu.selectAll",
        "orderFrontStandardAboutPanel:": "menu.about",
        "hide:": "menu.hide", "hideOtherApplications:": "menu.hideOthers",
        "unhideAllApplications:": "menu.showAll", "terminate:": "menu.quit"
    ]
}
