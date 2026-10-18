import AppKit
import AVFoundation
import AVKit
import SwiftUI

@main
struct MP4FlowApp: App {
    @NSApplicationDelegateAdaptor(MP4FlowAppDelegate.self) private var appDelegate
    @StateObject private var store = ConverterStore()
    @StateObject private var updateChecker = UpdateChecker()
    @AppStorage("appLanguage") private var appLanguageIdentifier = AppLanguage.systemDefault.rawValue

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(store: store, updateChecker: updateChecker, appDelegate: appDelegate)
                .frame(minWidth: 980, minHeight: 650)
                .environment(\.locale, (AppLanguage(rawValue: appLanguageIdentifier) ?? AppLanguage.systemDefault).locale)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L10n.text("关于 MP4Flow")) {
                    appDelegate.showAboutPanel(availableUpdate: updateChecker.availableUpdate)
                }
            }
            CommandGroup(replacing: .help) {
                Button(L10n.text("MP4Flow 使用帮助")) {
                    appDelegate.showHelpPanel(updateChecker: updateChecker)
                }
                Divider()
                Button(updateChecker.hasUpdate ? L10n.format("发现新版本 v%@", updateChecker.availableUpdate?.version ?? "") : (updateChecker.isChecking ? L10n.text("正在检查…") : L10n.text("检查更新…"))) {
                    if updateChecker.hasUpdate {
                        updateChecker.openDownloadPage()
                    } else {
                        appDelegate.requestManualUpdateCheck?()
                    }
                }
                .disabled(updateChecker.isChecking)
                Divider()
                Button(L10n.text("在 GitHub 查看项目")) { NSWorkspace.shared.open(ProjectLinks.repository) }
                Button(L10n.text("反馈问题或建议")) { NSWorkspace.shared.open(ProjectLinks.issues) }
            }
        }
        Settings {
            UpdateSettingsView(updateChecker: updateChecker)
        }
    }
}

private enum ProjectLinks {
    static let repository = URL(string: "https://github.com/ixiehao/MP4Flow")!
    static let issues = URL(string: "https://github.com/ixiehao/MP4Flow/issues/new/choose")!
    static let developer = URL(string: "https://github.com/ixiehao")!
}

private enum AboutCredits {
    static func make(availableUpdate: AvailableUpdate?) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.paragraphSpacing = 5
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let link: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: paragraph,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        let credits = NSMutableAttributedString()
        func appendBody(_ text: String) { credits.append(NSAttributedString(string: text, attributes: body)) }
        func appendLink(_ text: String, _ destination: URL) {
            var attributes = link
            attributes[.link] = destination
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }

        appendBody(L10n.text("免费开源的本地视频转换工具") + "\n")
        appendBody(L10n.text("开发者："))
        appendLink("ixiehao\n", ProjectLinks.developer)
        appendLink("github.com/ixiehao/MP4Flow\n", ProjectLinks.repository)
        appendLink(L10n.text("反馈问题或建议"), ProjectLinks.issues)
        if let availableUpdate {
            appendBody("\n\n" + L10n.format("发现新版本 v%@", availableUpdate.version) + "\n")
            appendLink(L10n.text("下载更新"), availableUpdate.downloadURL)
        }
        appendBody("\n\n" + L10n.text("本地处理，不上传视频或使用数据。") + "\n" + L10n.text("MIT License"))
        return credits
    }
}

@MainActor
final class MP4FlowAppDelegate: NSObject, NSApplicationDelegate {
    var openMainWindow: (() -> Void)?
    var requestManualUpdateCheck: (() -> Void)?
    private var helpWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { restoreMainWindow(in: sender) }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let application = notification.object as? NSApplication { restoreMainWindow(in: application) }
    }

    private func restoreMainWindow(in application: NSApplication) {
        guard !application.windows.contains(where: { $0.isVisible }) else { return }
        if let window = application.windows.first(where: { $0.canBecomeKey }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        application.activate(ignoringOtherApps: true)
    }

    func showAboutPanel(availableUpdate: AvailableUpdate?) {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: AboutCredits.make(availableUpdate: availableUpdate)])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func showHelpPanel(updateChecker: UpdateChecker) {
        let window: NSWindow
        if let existingWindow = helpWindow {
            window = existingWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.center()
            helpWindow = window
        }
        window.title = L10n.text("MP4Flow 使用帮助")
        window.contentView = NSHostingView(rootView: HelpPanel(updateChecker: updateChecker))
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct HelpStep: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(index)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(BrandColor.blue)
                .frame(width: 24, height: 24)
                .background(BrandColor.blue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct HelpPanel: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("MP4Flow 使用帮助"))
                        .font(.system(size: 18, weight: .bold))
                    Text(L10n.text("三步完成本地视频转换。"))
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColor.textSecondary)
                }
            }
            Divider()

            if let update = updateChecker.availableUpdate {
                HStack(spacing: 10) {
                    Mark(kind: .bolt, color: BrandColor.blue).frame(width: 16, height: 16)
                    Text(L10n.format("发现新版本 v%@", update.version))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button { updateChecker.openDownloadPage() } label: {
                        HStack(spacing: 5) {
                            TablerIcon(name: .download, color: .white).frame(width: 13, height: 13)
                            Text(L10n.text("下载更新"))
                        }
                    }
                    .buttonStyle(AppActionButtonStyle(primary: true, minWidth: 86, height: 32))
                }
                .padding(10)
                .background(BrandColor.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Divider()
            }

            VStack(alignment: .leading, spacing: 14) {
                HelpStep(index: "1", title: L10n.text("添加视频"), detail: L10n.text("点击「添加视频」或将文件拖入窗口。"))
                HelpStep(index: "2", title: L10n.text("选择转换方式"), detail: L10n.text("选择预设、画质、分辨率与输出位置。"))
                HelpStep(index: "3", title: L10n.text("开始转换"), detail: L10n.text("确认队列后点击「开始转换」，完成后可在访达中打开文件。"))
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("遇到问题？"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.text("请确认已安装 FFmpeg；智能增强需要 Apple 芯片与 macOS 27+。不支持的素材可先用「智能转换」生成新文件后重试。"))
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L10n.text("所有转换均在本机完成。更新检查只读取 GitHub 公开版本信息，不上传视频或使用数据。"))
                .font(.system(size: 11))
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button { NSWorkspace.shared.open(ProjectLinks.repository) } label: {
                    HStack(spacing: 5) {
                        TablerIcon(name: .externalLink, color: BrandColor.textPrimary).frame(width: 13, height: 13)
                        Text(L10n.text("在 GitHub 查看项目"))
                    }
                }
                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 126, height: 32))
                Button { NSWorkspace.shared.open(ProjectLinks.issues) } label: {
                    HStack(spacing: 5) {
                        TablerIcon(name: .externalLink, color: BrandColor.textPrimary).frame(width: 13, height: 13)
                        Text(L10n.text("反馈问题或建议"))
                    }
                }
                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 126, height: 32))
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct UpdateSettingsView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @AppStorage(UpdateCheckSchedule.automaticChecksEnabledKey) private var automaticallyCheckForUpdates = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                TablerIcon(name: .download, color: BrandColor.blue)
                    .frame(width: 20, height: 20)
                    .padding(8)
                    .background(BrandColor.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("更新设置"))
                        .font(.system(size: 17, weight: .bold))
                    Text(L10n.text("更新不会自动下载或安装。"))
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColor.textSecondary)
                }
            }

            Toggle(L10n.text("自动检查更新"), isOn: $automaticallyCheckForUpdates)
                .toggleStyle(.switch)

            Text(automaticallyCheckForUpdates
                 ? L10n.text("首次启动不自动检查更新；之后通常每天检查一次，失败后稍后重试。")
                 : L10n.text("自动检查已关闭。你仍可随时通过“帮助 > 检查更新”手动检查。"))
                .font(.system(size: 12))
                .foregroundStyle(BrandColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                TablerIcon(name: updateChecker.isChecking ? .loader2 : .infoCircle, color: BrandColor.textSecondary)
                    .frame(width: 14, height: 14)
                Text(updateChecker.isChecking ? L10n.text("正在检查更新…") : (updateChecker.lastCheckFailed ? L10n.text("上次未能检查更新，可手动重试。") : L10n.text("更新检查只读取 GitHub 公开发布信息，不上传视频或使用数据。")))
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColor.textSecondary)
            }
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
    }
}

private struct UpdateAvailableBanner: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        if let update = updateChecker.availableUpdate, updateChecker.shouldShowUpdateBanner {
            HStack(spacing: 12) {
                TablerIcon(name: .download, color: BrandColor.blue)
                    .frame(width: 18, height: 18)
                    .padding(7)
                    .background(BrandColor.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("发现新版本 v%@", update.version))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.text("可在 GitHub Release 查看更新说明并下载。"))
                        .font(.system(size: 11))
                        .foregroundStyle(BrandColor.textSecondary)
                }
                Spacer(minLength: 12)
                Button(L10n.text("查看更新与下载")) {
                    updateChecker.openDownloadPage()
                }
                .buttonStyle(AppActionButtonStyle(primary: true, minWidth: 126, height: 32))
                Button(L10n.text("暂不提醒此版本")) {
                    updateChecker.dismissAvailableUpdateBanner()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BrandColor.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(BrandColor.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BrandColor.blue.opacity(0.22), lineWidth: 1) }
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: ConverterStore
    @ObservedObject var updateChecker: UpdateChecker
    let appDelegate: MP4FlowAppDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var isDropTargeted = false
    @StateObject private var dependencyHealth = DependencyHealthMonitor()
    @State private var showUpdateNotice = false
    @State private var showProcessingPolicy = false
    @State private var updateNoticeMessage = ""
    @State private var updateDownloadURL: URL?
    @State private var clipItem: ConversionItem?
    @State private var cropItem: ConversionItem?
    @AppStorage("appLanguage") private var appLanguageIdentifier = AppLanguage.systemDefault.rawValue
    private let configurationControlHeight: CGFloat = 40
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    var body: some View {
        VStack(spacing: 0) {
            header
            UpdateAvailableBanner(updateChecker: updateChecker)
                .padding(.bottom, updateChecker.shouldShowUpdateBanner ? 12 : 0)
            configuration
            queue
            footer
        }
        .padding(.horizontal, 24)
        // Draw into the hidden title bar, leaving a compact 34 pt clearance for
        // macOS window controls instead of a second, empty title-bar band.
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColor.canvas)
        .ignoresSafeArea(.container, edges: .top)
        .font(AppFont.body)
        .onAppear {
            appDelegate.openMainWindow = { openWindow(id: "main") }
            appDelegate.requestManualUpdateCheck = checkForUpdates
            Task { _ = await updateChecker.checkAtLaunchIfEligible() }
            refreshDependencyHealth()
        }
        .onChange(of: store.outputDirectory) { _ in refreshDependencyHealth() }
        .onChange(of: store.items.count) { _ in refreshDependencyHealth() }
        .onChange(of: store.preset) { preset in
            if preset == .smartEnhanceUpscale {
                store.reconcileSmartEnhanceTarget()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: store.acceptDrop)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BrandColor.blue, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .alert(L10n.text("转换组件不可用"), isPresented: $store.showFFmpegSetup) {
            Button(L10n.text("复制安装命令")) { store.copyFFmpegInstallCommand() }
            Button(L10n.text("打开 Homebrew 官网")) { store.openHomebrewWebsite() }
            Button(L10n.text("稍后再说"), role: .cancel) {}
        } message: {
            Text(L10n.text("FFmpeg 或 ffprobe 未安装，或无法运行。请先在「环境体检」查看缺少的组件与修复方法。\n\n如未安装，可在终端执行：brew install ffmpeg\n安装后重新检查。"))
        }
        .alert(L10n.text("检查更新"), isPresented: $showUpdateNotice) {
            if updateDownloadURL != nil {
                Button(L10n.text("下载更新")) { updateChecker.openDownloadPage() }
            }
            Button(L10n.text("知道了"), role: .cancel) {}
        } message: {
            Text(updateNoticeMessage)
        }
        .alert(L10n.text(store.mergeOutput == nil ? "无法无损合并" : "合并完成"), isPresented: $store.showMergeNotice) {
            if store.mergeOutput != nil {
                Button(L10n.text("在访达中显示")) { store.revealMergeOutput() }
            }
            Button(L10n.text("知道了"), role: .cancel) {}
        } message: {
            Text(store.mergeNotice)
        }
        .alert(L10n.text("兼容合并，需重新编码"), isPresented: $store.showCompatibleMergePrompt) {
            Button(L10n.text("取消"), role: .cancel) { store.cancelCompatibleMerge() }
            Button(L10n.text("开始兼容合并")) { store.startCompatibleMerge() }
        } message: {
            Text(L10n.text("这些片段暂不适合直接拼接。建议先做统一规格的转码，再合并。\n\n也可选择「开始兼容合并」，自动统一规格后合并。以最大分辨率为目标，等比例缩放并居中补边，输出 H.264 + AAC MP4。"))
        }
        .sheet(item: $clipItem) { item in
            TrimEditor(source: item.source, initialRange: item.trimRange) { start, end in
                store.scheduleTrim(item, start: start, end: end)
            }
        }
        .sheet(item: $cropItem) { item in
            CropEditor(source: item.source, initialCrop: item.crop) { crop in
                store.scheduleCrop(item, crop: crop)
            }
        }
    }

    private func checkForUpdates() {
        guard !updateChecker.isChecking else { return }
        Task { @MainActor in
            let result = await updateChecker.checkForUpdate(force: true)
            switch result {
            case .available(let update):
                updateNoticeMessage = L10n.format("发现新版本 v%@，可前往 GitHub 下载。", update.version)
                updateDownloadURL = update.downloadURL
            case .upToDate:
                updateNoticeMessage = L10n.format("MP4Flow 已是最新版本（v%@）。", appVersion)
                updateDownloadURL = nil
            case .failed:
                updateNoticeMessage = L10n.text("暂时无法检查更新。请确认网络连接，或稍后重试。")
                updateDownloadURL = nil
            case .checking:
                return
            }
            showUpdateNotice = true
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("MP4Flow").font(AppFont.brand)
                    Text(L10n.text("视频转 MP4")).font(AppFont.subtitle).foregroundStyle(BrandColor.textSecondary)
                }
                HStack(spacing: 6) {
                    Mark(kind: .shield, color: BrandColor.textSecondary).frame(width: 16, height: 16)
                    Text(L10n.text("本地处理，保护隐私")).font(AppFont.privacy).foregroundStyle(BrandColor.textSecondary)
                }
            }
            .padding(.leading, 16)
            Spacer(minLength: 26)
            dependencyHealthGuide
                .frame(minWidth: 280, maxWidth: 440)
            Spacer(minLength: 18)
            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        appLanguageIdentifier = language.rawValue
                    } label: {
                        HStack(spacing: 8) {
                            if (AppLanguage(rawValue: appLanguageIdentifier) ?? AppLanguage.systemDefault) == language {
                                TablerIcon(name: .check, color: BrandColor.blue).frame(width: 14, height: 14)
                            } else {
                                Color.clear.frame(width: 14, height: 14)
                            }
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    TablerIcon(name: .language, color: BrandColor.textSecondary)
                        .frame(width: 14, height: 14)
                    Text((AppLanguage(rawValue: appLanguageIdentifier) ?? AppLanguage.systemDefault).displayName)
                        .font(AppFont.captionMedium)
                }
                .foregroundStyle(BrandColor.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.trailing, 14)
            Button { store.chooseFiles() } label: {
                HStack(spacing: 7) {
                    Mark(kind: .plus, color: .white).frame(width: 14, height: 14)
                    Text(L10n.text("添加视频")).font(AppFont.medium)
                }
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(store.isBusy)
        }
        .frame(height: 84)
        .padding(.horizontal, 8)
    }

    private var configuration: some View {
        GeometryReader { geometry in
            // Four fixed proportions preserve the design's hierarchy from compact
            // windows through the recommended 1440 pt layout.
            let usableWidth = max(0, geometry.size.width - 87)
            HStack(alignment: .top, spacing: 0) {
                configurationColumn(title: "转换预设", mark: .film, width: usableWidth * 0.31) {
                    MP4FlowMenuPicker(
                        selection: $store.preset,
                        options: ConversionPreset.menuOrder.map {
                            ConfigurationOption(
                                value: $0,
                                title: $0.title,
                                section: $0.menuSection,
                                isAvailable: $0 != .smartEnhanceUpscale || SmartEnhanceAvailability.isSupported
                            )
                        },
                        isEnabled: !store.isBusy,
                        menuWidth: usableWidth * 0.31
                    )
                    .frame(maxWidth: .infinity).frame(height: configurationControlHeight)
                    configurationHint(store.preset.detail)
                }
                configurationDivider
                configurationColumn(title: "画质大小", mark: .hardDrive, width: usableWidth * 0.25) {
                    QualitySegmentedControl(selection: $store.quality, isEnabled: !store.isBusy && !store.preset.usesFixedQuality)
                        .frame(height: configurationControlHeight)
                    configurationHint(store.qualityDescription)
                }
                configurationDivider
                configurationColumn(title: "分辨率", mark: .resolution, width: usableWidth * 0.16) {
                    if store.preset == .smartEnhanceUpscale {
                        if store.smartEnhanceTargets.isEmpty {
                            MP4FlowMenuTrigger(title: L10n.text("添加视频"), isEnabled: false, isHovering: false)
                                .frame(maxWidth: .infinity).frame(height: configurationControlHeight)
                        } else {
                            MP4FlowMenuPicker(
                                selection: $store.smartEnhanceTarget,
                                options: store.smartEnhanceTargets.map { ConfigurationOption(value: $0, title: $0.title) },
                                isEnabled: !store.isBusy,
                                menuWidth: usableWidth * 0.16
                            )
                            .frame(maxWidth: .infinity).frame(height: configurationControlHeight)
                        }
                        configurationHint(store.smartEnhanceTargets.isEmpty ? L10n.text("添加视频后显示可选分辨率。") : L10n.text("最高增强 2 倍。"))
                    } else {
                        MP4FlowMenuPicker(
                            selection: $store.outputResolution,
                            options: OutputResolution.allCases.map { ConfigurationOption(value: $0, title: $0.title) },
                            isEnabled: !store.isBusy,
                            menuWidth: usableWidth * 0.16
                        )
                        .frame(maxWidth: .infinity).frame(height: configurationControlHeight)
                        configurationHint(store.outputResolution.detail)
                    }
                }
                configurationDivider
                configurationColumn(title: "输出位置", mark: .folder, width: usableWidth * 0.28) {
                    OutputLocationMenuPicker(
                        outputDirectory: $store.outputDirectory,
                        isEnabled: !store.isBusy,
                        chooseDirectory: store.chooseOutputDirectory,
                        menuWidth: usableWidth * 0.28
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: configurationControlHeight)
                    configurationHint(L10n.text(store.outputDirectory == nil ? "默认输出至源文件夹" : "已选择自定义输出文件夹"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 116)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(height: 148)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BrandColor.stroke, lineWidth: 1) }
    }

    private var configurationDivider: some View {
        Rectangle().fill(BrandColor.stroke).frame(width: 1, height: 106).padding(.horizontal, 14)
    }

    private func configurationHint(_ text: String) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(BrandColor.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help(text)
    }

    private func configurationColumn<Content: View>(title: String, mark: MarkKind, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Mark(kind: mark, color: BrandColor.blue)
                    .frame(width: 18, height: 18)
                    .padding(5)
                    .background(BrandColor.blue.opacity(0.085), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(L10n.text(title)).font(AppFont.section)
            }
            content()
        }
        .frame(width: width, alignment: .topLeading)
    }

    private var dependencyHealthGuide: some View {
        DependencyHealthStatusBar(
            monitor: dependencyHealth,
            refresh: { refreshDependencyHealth(forceToolCheck: true) },
            copyFFmpegInstallCommand: store.copyFFmpegInstallCommand,
            openHomebrewWebsite: store.openHomebrewWebsite
        )
    }

    private func refreshDependencyHealth(forceToolCheck: Bool = false) {
        dependencyHealth.refresh(
            outputDirectory: store.outputDirectory,
            sourceDirectories: store.items.map(\.source),
            forceToolCheck: forceToolCheck
        )
    }

    private var queue: some View {
        Group {
            if store.items.isEmpty {
                emptyQueue
            } else {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(L10n.format("转换队列（%d）", store.items.count)).font(AppFont.section)
                            Spacer()
                            Button { showProcessingPolicy.toggle() } label: {
                                HStack(spacing: 4) {
                                    TablerIcon(name: .infoCircle, color: BrandColor.textSecondary).frame(width: 12, height: 12)
                                    Text(L10n.text("处理策略")).font(AppFont.caption)
                                }
                                .foregroundStyle(BrandColor.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.text("处理策略"))
                            .popover(isPresented: $showProcessingPolicy, arrowEdge: .bottom) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L10n.text("处理策略")).font(AppFont.section)
                                    Text(L10n.text("默认仅输出第一路视频和音频，并移除容器元数据和章节。开始转换时会检测多音轨、字幕和 HDR，并在队列中提示。"))
                                        .font(AppFont.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack {
                                        Spacer()
                                        Button(L10n.text("知道了")) { showProcessingPolicy = false }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(BrandColor.blue)
                                    }
                                }
                                .padding(16)
                                .frame(width: 340)
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    Divider().overlay(BrandColor.stroke)
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                                QueueRow(
                                    item: item,
                                    reveal: { store.reveal(item) },
                                    remove: { store.remove(item) },
                                    canRemove: store.canRemove(item),
                                    edit: { clipItem = item },
                                    canEdit: !store.isBusy,
                                    crop: { cropItem = item },
                                    rotate: { store.scheduleRotation(item, rotation: $0) },
                                    mergeModeTitle: store.mergeModeTitle,
                                    isCancelling: store.isCancelling,
                                    isMergeVerifying: store.isVerifyingMerge
                                )
                                .id("\(item.id.uuidString)-\(appLanguageIdentifier)")
                                if index < store.items.count - 1 {
                                    Divider().overlay(BrandColor.stroke)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(BrandColor.stroke, lineWidth: 1) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 14)
    }

    private var emptyQueue: some View {
        VStack(spacing: 10) {
            Mark(kind: .film, color: BrandColor.icon).frame(width: 40, height: 40)
            Text(L10n.text("拖入视频文件")).font(AppFont.headline)
            Text(L10n.text("支持 AVI、WMV、MKV、RMVB 及常见视频格式")).font(AppFont.body).foregroundStyle(BrandColor.textSecondary)
            Button { store.chooseFiles() } label: {
                HStack(spacing: 7) { Mark(kind: .plus, color: .white).frame(width: 14, height: 14); Text(L10n.text("添加视频")).font(AppFont.medium) }
            }
            .buttonStyle(AppActionButtonStyle(primary: true, minWidth: 132, height: 38))
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(footerStatus)
                    .font(AppFont.captionMedium)
                    .foregroundStyle(BrandColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(footerStatus)
                if store.isRunning, let progress = store.overallProgress {
                    ProgressView(value: progress).tint(BrandColor.blue).frame(maxWidth: .infinity)
                } else if store.isRunning {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                } else if store.isMerging, let progress = store.mergeProgress {
                    ProgressView(value: progress).tint(BrandColor.blue).frame(maxWidth: .infinity)
                } else if store.isMerging {
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                }
                if !store.isBusy {
                    HStack(spacing: 7) {
                        Text("v\(appVersion)")
                        Text("·").foregroundStyle(BrandColor.textSecondary.opacity(0.65))
                        if let update = updateChecker.availableUpdate {
                            Button(L10n.format("发现新版本 v%@", update.version)) { updateChecker.openDownloadPage() }
                                .buttonStyle(.plain)
                                .foregroundStyle(BrandColor.blue)
                                .accessibilityLabel(L10n.format("发现新版本 v%@", update.version))
                        } else {
                            Button(updateChecker.isChecking ? L10n.text("正在检查…") : L10n.text("检查更新")) { checkForUpdates() }
                                .buttonStyle(.plain)
                                .foregroundStyle(BrandColor.blue)
                                .accessibilityLabel(L10n.format("检查更新，当前版本 v%@", appVersion))
                                .disabled(updateChecker.isChecking)
                        }
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(1)
                }
            }
            // Keep the summary inside the content inset at the 980 pt minimum
            // window width; a fixed 340 pt column pushed the whole footer out.
            .frame(minWidth: 160, idealWidth: 260, maxWidth: 340, alignment: .leading)
            .layoutPriority(-1)
            Spacer(minLength: 0)
            Button(L10n.text("清空列表")) { store.clearQueue() }
                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 96, height: 36, horizontalPadding: 10))
                .fixedSize(horizontal: true, vertical: false)
                .disabled(store.isBusy || store.items.isEmpty)
            Button(L10n.format("清理已完成（%d）", completedCount)) { store.clearCompleted() }
                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 124, height: 36, horizontalPadding: 10))
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!store.hasCompleted)
            Button(L10n.text("重排失败项")) { store.retryIncomplete() }
                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 108, height: 36, horizontalPadding: 10))
                .fixedSize(horizontal: true, vertical: false)
                .disabled(store.isBusy || !store.hasIncomplete)
            Button(L10n.format("合并（%d）", store.mergeDisplayCount)) { store.mergeWaitingItems() }
                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 96, height: 36, horizontalPadding: 10))
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!store.canMerge)
            if store.isBusy {
                Button(L10n.text(store.isCancelling ? "正在取消…" : "取消任务")) { store.cancel() }
                    .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 96, height: 36, horizontalPadding: 10))
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(store.isCancelling)
            } else {
                Button(L10n.text(store.isMerging ? "正在合并" : "开始转换")) { store.start() }
                    .buttonStyle(AppActionButtonStyle(primary: true, minWidth: 112, height: 36, horizontalPadding: 10))
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(store.isBusy || !store.hasWaiting)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(minHeight: 58)
    }

    private var completedCount: Int { store.items.reduce(into: 0) { if case .complete = $1.state { $0 += 1 } } }
    private var footerStatus: String {
        if store.isCancelling { return L10n.text("正在停止转换并清理临时文件") }
        if store.isMerging {
            if store.isVerifyingMerge { return L10n.text("正在验证输出") }
            if let progress = store.mergeProgress { return L10n.format("正在%@ %d 个片段 · %d%%", store.mergeModeTitle, store.mergeDisplayCount, Int(progress * 100)) }
            return L10n.text("正在检查片段兼容性")
        }
        guard store.isRunning else {
            if store.items.isEmpty { return L10n.text("准备就绪") }
            if store.hasWaiting { return L10n.format("已添加 %d 个视频", store.items.count) }
            let failures = store.items.filter { if case .failed = $0.state { return true }; return false }.count
            let cancelled = store.items.filter { if case .cancelled = $0.state { return true }; return false }.count
            if failures > 0 || cancelled > 0 {
                return L10n.format("完成 %d · 失败 %d · 取消 %d", completedCount, failures, cancelled)
            }
            if completedCount == store.items.count { return L10n.text("转换完成") }
            return L10n.format("已添加 %d 个视频", store.items.count)
        }
        let phase = store.items.first { if case .running = $0.state { return true }; return false }?.phase?.title ?? L10n.text("正在转换")
        let stage = store.overallProgress.map { L10n.format("%@ · %d%%", phase, Int($0 * 100)) } ?? phase
        return [stage, store.activeBatchProgressLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 132, height: 36)
            .background(
                isEnabled
                    ? (configuration.isPressed
                        ? AnyShapeStyle(BrandColor.bluePressed)
                        : AnyShapeStyle(LinearGradient(colors: [BrandColor.blue, BrandColor.blue.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    : AnyShapeStyle(BrandColor.blueDisabled),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.24), lineWidth: 1) }
            .shadow(color: isEnabled ? BrandColor.blue.opacity(configuration.isPressed ? 0.08 : 0.24) : .clear, radius: 7, y: 3)
            .opacity(isEnabled ? 1 : 0.76)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Shared action style for the footer and empty state. It removes AppKit's
/// inconsistent button chrome while keeping clear primary/secondary hierarchy.
private struct AppActionButtonStyle: ButtonStyle {
    let primary: Bool
    let minWidth: CGFloat
    let height: CGFloat
    var horizontalPadding: CGFloat = 14
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.medium)
            .foregroundStyle(primary ? Color.white : (isEnabled ? BrandColor.textPrimary : BrandColor.textSecondary))
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: minWidth, minHeight: height)
            .background(background(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(primary ? Color.white.opacity(0.23) : BrandColor.selectStroke, lineWidth: 1)
            }
            .shadow(color: primary && isEnabled ? BrandColor.blue.opacity(configuration.isPressed ? 0.08 : 0.22) : .black.opacity(configuration.isPressed ? 0 : 0.035), radius: primary ? 7 : 2, y: primary ? 3 : 1)
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func background(isPressed: Bool) -> AnyShapeStyle {
        if primary {
            if isPressed { return AnyShapeStyle(BrandColor.bluePressed) }
            return AnyShapeStyle(LinearGradient(colors: [BrandColor.blue, BrandColor.blue.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(isPressed ? BrandColor.selectHover : BrandColor.surface)
    }
}

private struct ConfigurationOption<Value: Hashable> {
    let value: Value
    let title: String
    let section: String?
    let isAvailable: Bool

    init(value: Value, title: String, section: String? = nil, isAvailable: Bool = true) {
        self.value = value
        self.title = title
        self.section = section
        self.isAvailable = isAvailable
    }
}

/// Native segmented controls truncate English labels at narrow widths. This
/// equal-width alternative keeps the panel stable and permits a readable
/// second line without widening the configuration column.
private struct QualitySegmentedControl: View {
    @Binding var selection: ConversionQuality
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ConversionQuality.allCases) { quality in
                Button {
                    selection = quality
                } label: {
                    Text(quality.title)
                        .font(AppFont.captionMedium)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .foregroundStyle(selection == quality ? BrandColor.textPrimary : BrandColor.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(selection == quality ? BrandColor.surface : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(selection == quality ? BrandColor.selectStroke : .clear, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(3)
        .background(BrandColor.selectSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(BrandColor.selectStroke, lineWidth: 1) }
        .opacity(isEnabled ? 1 : 0.55)
    }
}

/// A single self-drawn trigger keeps every menu visually consistent while
/// retaining native menu, keyboard, and accessibility behavior.
private struct MP4FlowMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [ConfigurationOption<Value>]
    let isEnabled: Bool
    let menuWidth: CGFloat
    @State private var isHovering = false
    @State private var isPresented = false

    private var selectedTitle: String { options.first(where: { $0.value == selection })?.title ?? "—" }

    var body: some View {
        Button { isPresented = true } label: {
            MP4FlowMenuTrigger(title: selectedTitle, isEnabled: isEnabled, isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.element.value) { index, option in
                    if shouldShowSection(for: option, at: index) {
                        Text(option.section ?? "")
                            .font(AppFont.caption)
                            .foregroundStyle(BrandColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.top, index == 0 ? 2 : 8)
                            .padding(.bottom, 2)
                    }
                    MP4FlowMenuRow(title: option.title, isSelected: option.value == selection, isEnabled: option.isAvailable) {
                        selection = option.value
                        isPresented = false
                    }
                }
            }
            .padding(6)
            .frame(width: menuWidth)
            .background(BrandColor.surface)
        }
        .accessibilityLabel(L10n.text("配置选项"))
        .accessibilityValue(selectedTitle)
    }

    private func shouldShowSection(for option: ConfigurationOption<Value>, at index: Int) -> Bool {
        guard option.section != nil else { return false }
        return index == 0 || options[index - 1].section != option.section
    }
}

private struct OutputLocationMenuPicker: View {
    @Binding var outputDirectory: URL?
    let isEnabled: Bool
    let chooseDirectory: () -> Void
    let menuWidth: CGFloat
    @State private var isHovering = false
    @State private var isPresented = false

    private var title: String { outputDirectory?.lastPathComponent ?? L10n.text("原视频所在文件夹") }

    var body: some View {
        Button { isPresented = true } label: {
            MP4FlowMenuTrigger(title: title, isEnabled: isEnabled, isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                MP4FlowMenuRow(title: L10n.text("原视频所在文件夹"), isSelected: outputDirectory == nil) {
                    outputDirectory = nil
                    isPresented = false
                }
                if let directory = outputDirectory {
                    Text(L10n.format("当前：%@", directory.lastPathComponent))
                        .font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                }
                Divider().padding(.vertical, 4)
                MP4FlowMenuRow(title: L10n.text("选择其他文件夹"), isSelected: false) {
                    isPresented = false
                    chooseDirectory()
                }
            }
            .padding(6)
            .frame(width: menuWidth)
            .background(BrandColor.surface)
        }
        .accessibilityLabel(L10n.text("输出位置"))
        .accessibilityValue(title)
    }
}

private struct MP4FlowMenuRow: View {
    let title: String
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(isSelected ? "✓" : " ")
                    .font(AppFont.medium).foregroundStyle(BrandColor.blue)
                    .frame(width: 12)
                Text(L10n.text(title)).font(AppFont.medium).foregroundStyle(BrandColor.textPrimary)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(isSelected ? BrandColor.selectHover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
        .frame(maxWidth: .infinity)
    }
}

private struct MP4FlowMenuTrigger: View {
    let title: String
    let isEnabled: Bool
    let isHovering: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(AppFont.medium)
                .foregroundStyle(isEnabled ? BrandColor.textPrimary : BrandColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Mark(kind: .chevron, color: isEnabled ? BrandColor.icon : BrandColor.textSecondary)
                .frame(width: 16, height: 16)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32)
        .background(isHovering && isEnabled ? BrandColor.selectHover : BrandColor.selectSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isHovering && isEnabled ? BrandColor.selectHoverStroke : BrandColor.selectStroke, lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct QueueRow: View {
    let item: ConversionItem
    let reveal: () -> Void
    let remove: () -> Void
    let canRemove: Bool
    let edit: () -> Void
    let canEdit: Bool
    let crop: () -> Void
    let rotate: (VideoRotation?) -> Void
    let mergeModeTitle: String
    let isCancelling: Bool
    let isMergeVerifying: Bool

    var body: some View {
        HStack(spacing: 10) {
            SourceThumbnail(extensionName: item.source.pathExtension, thumbnail: item.presentation?.thumbnail)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.source.lastPathComponent).font(AppFont.rowTitle).lineLimit(1)
                Text(item.presentation == nil ? L10n.text("正在读取视频信息") : (item.presentation?.summary ?? L10n.text("准备输出 MP4")))
                    .font(AppFont.caption).foregroundStyle(BrandColor.textSecondary).lineLimit(1)
            }
            .frame(minWidth: 180, maxWidth: 360, alignment: .leading)
            Text(item.source.pathExtension.uppercased()).font(AppFont.tag).foregroundStyle(BrandColor.textSecondary)
                .padding(.horizontal, 9).padding(.vertical, 4).background(BrandColor.tag, in: Capsule())
                .frame(width: 58, alignment: .leading)
            Spacer(minLength: 12)
            stateView
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            HStack(spacing: 7) {
                QueueActionButton(mark: .scissors, title: "剪辑", isDisabled: !canEdit, action: edit)
                QueueActionButton(mark: .crop, title: "裁切画面", isDisabled: !canEdit, action: crop)
                QueueRotationMenu(current: item.rotation, isDisabled: !canEdit, select: rotate)
                QueueActionButton(mark: .folder, title: "打开文件夹", action: reveal)
                QueueActionButton(mark: .trash, title: "从队列移除", isDisabled: !canRemove, action: remove)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(rowBackground)
    }

    @ViewBuilder private var stateView: some View {
        switch item.state {
        case .complete(let output):
            HStack(spacing: 9) {
                StatusMark(state: item.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("已完成")).font(AppFont.rowTitle).foregroundStyle(BrandColor.success)
                    Text(output.lastPathComponent).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary).lineLimit(1)
                    mediaNotice
                }
            }
        case .running(let progress):
            HStack(spacing: 9) {
                StatusMark(state: item.state)
                VStack(alignment: .leading, spacing: 5) {
                    Text(runningTitle(progress))
                        .font(AppFont.rowTitle)
                        .foregroundStyle(BrandColor.blue)
                    if isCancelling || item.phase == .verifying { ProgressView().frame(width: 150, alignment: .leading) }
                    else if let progress { ProgressView(value: progress).tint(BrandColor.blue).frame(width: 150) }
                    else { ProgressView().frame(width: 150, alignment: .leading) }
                    if !isCancelling { mediaNotice }
                }
            }
        case .merging(let progress):
            HStack(spacing: 9) {
                StatusMark(state: item.state)
                VStack(alignment: .leading, spacing: 5) {
                    Text(isCancelling ? L10n.text("正在取消…") : (isMergeVerifying ? L10n.text("正在验证输出") : (progress == nil ? L10n.text("等待合并") : L10n.format("正在%@ · %d%%", mergeModeTitle, Int((progress ?? 0) * 100)))))
                        .font(AppFont.rowTitle).foregroundStyle(BrandColor.blue)
                    if isCancelling || isMergeVerifying { ProgressView().frame(width: 150, alignment: .leading) }
                    else if let progress { ProgressView(value: progress).tint(BrandColor.blue).frame(width: 150) }
                }
            }
        case .waiting:
            if item.trimRange != nil || item.rotation != nil || item.crop != nil {
                HStack(spacing: 9) {
                    StatusMark(state: item.state)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pendingTitle).font(AppFont.rowTitle).foregroundStyle(BrandColor.blue)
                        Text(pendingDetail).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
                    }
                }
            } else {
                HStack(spacing: 9) { StatusMark(state: item.state); Text(L10n.text("等待中")).font(AppFont.rowTitle).foregroundStyle(BrandColor.textSecondary) }
            }
        case .failed(let message):
            let failure = item.failure.map { FailurePresentation(failure: $0) } ?? FailurePresentation(message: message)
            HStack(alignment: .top, spacing: 9) {
                StatusMark(state: item.state)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(failure.reason)
                        .font(AppFont.captionMedium)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .help(failure.reason)
                    Text(failure.solution)
                        .font(AppFont.caption)
                        .foregroundStyle(BrandColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(failure.solution)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        case .cancelled:
            HStack(spacing: 9) { StatusMark(state: item.state); Text(L10n.text("已取消")).font(AppFont.rowTitle).foregroundStyle(BrandColor.textSecondary) }
        }
    }

    @ViewBuilder private var mediaNotice: some View {
        if let notice = item.mediaHandling {
            if !notice.summary.isEmpty {
                Text(notice.summary)
                    .font(AppFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(notice.warnings, id: \.self) { warning in
                Text(warning)
                    .font(AppFont.caption)
                    .foregroundStyle(BrandColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rowBackground: Color {
        if case .running = item.state { return BrandColor.blue.opacity(0.075) }
        if case .merging = item.state { return BrandColor.blue.opacity(0.075) }
        return .clear
    }

    private func runningTitle(_ progress: Double?) -> String {
        if isCancelling { return L10n.text("正在取消…") }
        let phase = item.phase?.title ?? L10n.text("正在转换")
        if item.phase == .verifying { return phase }
        if let progress { return L10n.format("%@ · %d%%", phase, Int(progress * 100)) }
        return phase
    }

    private func timeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d:%02d", value / 3_600, (value / 60) % 60, value % 60)
    }

    private var pendingTitle: String {
        let operations = [
            (item.trimRange != nil, L10n.text("剪辑")),
            (item.crop != nil, L10n.text("裁切")),
            (item.rotation != nil, L10n.text("旋转"))
        ]
            .compactMap { $0.0 ? $0.1 : nil }
        return operations.isEmpty ? L10n.text("等待中") : L10n.format("待%@", operations.joined(separator: "、"))
    }

    private var pendingDetail: String {
        var parts: [String] = []
        if let trim = item.trimRange { parts.append("\(timeText(trim.start)) – \(timeText(trim.end))") }
        if let crop = item.crop { parts.append(L10n.format("裁切为 %@", crop.summary)) }
        if let rotation = item.rotation { parts.append(rotation.title) }
        return parts.joined(separator: " · ")
    }
}

/// Queue failures are intentionally concise: an actionable explanation is more
/// useful than exposing a long underlying framework error in a narrow row.
private struct FailurePresentation {
    let reason: String
    let solution: String

    init(message: String) {
        let isSmartEnhance = message.contains("智能增强") || message.contains("スマート高画質拡大") || message.localizedCaseInsensitiveContains("smart enhance")
        if isSmartEnhance {
            if message.contains("裁切") || message.contains("旋转") || message.contains("クロップ") || message.contains("回転") || message.localizedCaseInsensitiveContains("crop") || message.localizedCaseInsensitiveContains("rotation") {
                reason = L10n.text("智能增强不支持裁切或旋转")
                solution = L10n.text("请先使用普通转换，再剪辑或裁切。")
            } else if message.contains("超时") || message.contains("未响应") || message.contains("タイムアウト") || message.contains("応答しません") || message.localizedCaseInsensitiveContains("timed out") || message.localizedCaseInsensitiveContains("did not respond") {
                reason = L10n.text("智能增强处理超时")
                solution = L10n.text("请降低目标分辨率后重试。")
            } else if message.contains("macOS 27") {
                reason = L10n.text("需要 macOS 27 或更高版本")
                solution = L10n.text("请改用「智能转换」。")
            } else {
                reason = L10n.text("此视频暂不支持智能增强")
                solution = L10n.text("请使用「智能转换」先转换为新文件，然后添加新文件重试。")
            }
        } else if message.contains("未检测到视频流") || message.contains("映像ストリームが見つかりません") || message.localizedCaseInsensitiveContains("no video stream") {
            reason = L10n.text("未检测到可用视频流")
            solution = L10n.text("请确认文件可播放，或重新导出后再试。")
        } else {
            reason = L10n.text("转换未完成")
            solution = L10n.text("请重试；仍失败请使用「最稳妥转换」。")
        }
    }

    init(failure: ConversionFailure) {
        reason = failure.reason
        solution = failure.solution
    }
}

private struct SourceThumbnail: View {
    let extensionName: String
    let thumbnail: NSImage?
    var body: some View {
        ZStack {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [BrandColor.blue.opacity(0.42), BrandColor.blue.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Mark(kind: .film, color: .white.opacity(0.92)).frame(width: 24, height: 24)
            }
        }
        .frame(width: 52, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityLabel(L10n.format("%@ 视频", extensionName))
    }
}

private struct QueueActionButton: View {
    let mark: MarkKind
    let title: String
    var isDisabled = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Mark(kind: mark, color: isDisabled ? BrandColor.icon.opacity(0.35) : BrandColor.icon)
                .frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .background(isHovering && !isDisabled ? BrandColor.selectHover : BrandColor.canvas, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isHovering && !isDisabled ? BrandColor.selectHoverStroke : BrandColor.stroke, lineWidth: 1) }
                .shadow(color: isHovering && !isDisabled ? BrandColor.blue.opacity(0.11) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .help(L10n.text(title))
        .accessibilityLabel(L10n.text(title))
    }
}

private struct QueueRotationMenu: View {
    let current: VideoRotation?
    let isDisabled: Bool
    let select: (VideoRotation?) -> Void
    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Mark(kind: .rotate, color: isDisabled ? BrandColor.icon.opacity(0.35) : (current == nil ? BrandColor.icon : BrandColor.blue))
                .frame(width: 16, height: 16)
                .frame(width: 30, height: 30)
                .background(current == nil && !isHovering ? BrandColor.canvas : BrandColor.selectHover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(current == nil && !isHovering ? BrandColor.stroke : BrandColor.selectHoverStroke, lineWidth: 1) }
                .shadow(color: (current != nil || isHovering) && !isDisabled ? BrandColor.blue.opacity(0.11) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovering = $0 }
        .help(L10n.text("旋转视频"))
        .accessibilityLabel(L10n.text("旋转视频"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(VideoRotation.allCases, id: \.self) { rotation in
                    rotationOption(rotation)
                }
                if current != nil {
                    Divider().padding(.vertical, 3)
                    Button(L10n.text("取消旋转")) {
                        select(nil)
                        isPresented = false
                    }
                    .buttonStyle(RotationMenuRowStyle())
                }
            }
            .padding(6)
            .frame(width: 172)
        }
    }

    private func rotationOption(_ rotation: VideoRotation) -> some View {
        Button {
            select(rotation)
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(rotation.title)
                Spacer(minLength: 0)
                if current == rotation { Text("✓").foregroundStyle(BrandColor.blue) }
            }
        }
        .buttonStyle(RotationMenuRowStyle())
    }
}

private struct RotationMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.medium)
            .foregroundStyle(BrandColor.textPrimary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(configuration.isPressed ? BrandColor.selectHover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Compact editor actions keep Cancel secondary and Confirm prominent without
/// inheriting the oversized spacing of the platform's default bordered styles.
private struct EditorActionButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.medium)
            .foregroundStyle(primary ? Color.white : BrandColor.textPrimary)
            .padding(.horizontal, primary ? 13 : 11)
            .frame(minHeight: 30)
            .background(background(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(primary ? Color.clear : BrandColor.selectStroke.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: primary ? BrandColor.blue.opacity(0.18) : Color.black.opacity(0.08), radius: 1.5, y: 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
    }

    private func background(isPressed: Bool) -> Color {
        if primary { return isPressed ? BrandColor.bluePressed : BrandColor.blue }
        return isPressed ? BrandColor.selectSurface : BrandColor.surface
    }
}

private struct EditorLoadFailure: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Text(message).font(AppFont.rowTitle).foregroundStyle(.red)
            Text(L10n.text("请确认文件可播放；也可先用「智能转换」转为 MP4，再重新添加。"))
                .font(AppFont.body)
                .foregroundStyle(BrandColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct TrimEditor: View {
    let source: URL
    let initialRange: ClipRange?
    let confirm: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var duration = 0.0
    @State private var frameDuration = 1.0 / 30.0
    @State private var start = 0.0
    @State private var end = 0.0
    @State private var startText = "00:00:00.000"
    @State private var endText = "00:00:00.000"
    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var isApplyingFrameStep = false
    @State private var inspectionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source.lastPathComponent).font(AppFont.section).foregroundStyle(BrandColor.textPrimary).lineLimit(1)

            if duration > 0 {
                // Scheme A keeps the image canvas free of controls. Playback, range,
                // and trim fields sit in their own predictable layers below it.
                PlayerPreview(player: player, showsControls: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                CropPlaybackControls(player: player, duration: duration)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.text("保留范围")).font(AppFont.section)
                        Spacer()
                        Text(L10n.format("原始时长 %@", timeText(duration))).font(AppFont.captionMedium).foregroundStyle(BrandColor.textSecondary)
                    }
                    TrimRangeSlider(duration: duration, minimumLength: minimumClipDuration, start: $start, end: $end) { seek(to: $0) }
                        .frame(height: 50)
                    HStack(spacing: 10) {
                        trimTimeField(title: "起始", text: $startText, canStepBack: canStepStartBack, canStepForward: canStepStartForward, stepBack: stepStartBack, stepForward: stepStartForward) { live in applyStart(live: live) }
                        trimTimeField(title: "结束", text: $endText, canStepBack: canStepEndBack, canStepForward: canStepEndForward, stepBack: stepEndBack, stepForward: stepEndForward) { live in applyEnd(live: live) }
                        keptDurationField.frame(width: 160)
                    }
                }
                .padding(12)
                .background(BrandColor.selectHover, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(BrandColor.selectHoverStroke.opacity(0.42), lineWidth: 1) }
            } else if let loadError {
                EditorLoadFailure(message: loadError)
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                HStack(spacing: 10) { ProgressView(); Text(L10n.text("正在加载视频预览")).foregroundStyle(BrandColor.textSecondary) }
                    .frame(maxWidth: .infinity, minHeight: 260)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(L10n.text("取消")) { dismiss() }
                    .buttonStyle(EditorActionButtonStyle(primary: false))
                Button(L10n.text("确认剪辑")) {
                    confirm(start, end)
                    dismiss()
                }
                    .buttonStyle(EditorActionButtonStyle(primary: true))
                .disabled(duration <= 0 || end - start < minimumClipDuration)
            }
        }
        .padding(20)
        // Keep the loading and ready states the same height. A changing sheet
        // height makes macOS animate from an incorrect vertical origin.
        .frame(width: 760, height: 540, alignment: .top)
        .onAppear { loadDuration() }
        .onDisappear { inspectionTask?.cancel(); player?.pause() }
        .onChange(of: start) { value in startText = timeText(value) }
        .onChange(of: end) { value in endText = timeText(value) }
    }

    private func trimTimeField(title: String, text: Binding<String>, canStepBack: Bool, canStepForward: Bool, stepBack: @escaping () -> Void, stepForward: @escaping () -> Void, submit: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(L10n.text(title)).font(AppFont.captionMedium).foregroundStyle(BrandColor.textPrimary)
            frameStepButton(title: "−5", label: "后退 5 帧", isEnabled: canStepBack, action: stepBack)
            TextField("00:00:00.000", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(BrandColor.textPrimary)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(BrandColor.selectStroke, lineWidth: 1) }
                .onChange(of: text.wrappedValue) { _ in
                    if !isApplyingFrameStep { submit(true) }
                }
                .onSubmit { submit(false) }
            frameStepButton(title: "+5", label: "前进 5 帧", isEnabled: canStepForward, action: stepForward)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(BrandColor.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BrandColor.selectStroke.opacity(0.8), lineWidth: 1) }
    }

    private func frameStepButton(title: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? BrandColor.blue : BrandColor.textSecondary.opacity(0.38))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background(isEnabled ? BrandColor.surface : BrandColor.selectSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(BrandColor.selectStroke, lineWidth: 1) }
        .help(L10n.text(label))
        .accessibilityLabel(L10n.text(label))
        .disabled(!isEnabled)
    }

    private var keptDurationField: some View {
        HStack(spacing: 8) {
            Text(L10n.text("保留")).font(AppFont.captionMedium)
            Spacer(minLength: 0)
            Text(timeText(end - start))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(BrandColor.blue)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(BrandColor.selectHover.opacity(0.74), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(BrandColor.selectHoverStroke, lineWidth: 1) }
    }

    private func loadDuration() {
        inspectionTask?.cancel()
        inspectionTask = Task {
            player = AVPlayer(url: source)
            let media = await EditorMediaProbe.inspect(source: source)
            guard !Task.isCancelled else { return }
            guard let media else {
                loadError = L10n.text("无法加载剪辑预览")
                return
            }
            let seconds = media.duration
            duration = seconds
            frameDuration = media.frameDuration
            start = min(max(0, initialRange?.start ?? 0), max(0, seconds - minimumClipDuration))
            end = max(min(seconds, initialRange?.end ?? seconds), min(seconds, start + minimumClipDuration))
            startText = timeText(start)
            endText = timeText(end)
            seek(to: start)
        }
    }

    private func seek(to seconds: Double) {
        guard let player else { return }
        player.pause()
        player.currentItem?.cancelPendingSeeks()
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private var minimumClipDuration: Double { min(frameDuration, max(0.001, duration)) }
    private let frameStepCount = 5

    private var canStepStartBack: Bool { canStep(start, frameOffset: -frameStepCount, lower: 0, upper: max(0, end - minimumClipDuration)) }
    private var canStepStartForward: Bool { canStep(start, frameOffset: frameStepCount, lower: 0, upper: max(0, end - minimumClipDuration)) }
    private var canStepEndBack: Bool { canStep(end, frameOffset: -frameStepCount, lower: min(duration, start + minimumClipDuration), upper: duration) }
    private var canStepEndForward: Bool { canStep(end, frameOffset: frameStepCount, lower: min(duration, start + minimumClipDuration), upper: duration) }

    private func stepStartBack() { applyFrameStep(toStart: true, frameOffset: -frameStepCount) }
    private func stepStartForward() { applyFrameStep(toStart: true, frameOffset: frameStepCount) }
    private func stepEndBack() { applyFrameStep(toStart: false, frameOffset: -frameStepCount) }
    private func stepEndForward() { applyFrameStep(toStart: false, frameOffset: frameStepCount) }

    private func applyFrameStep(toStart: Bool, frameOffset: Int) {
        let value = toStart ? start : end
        let lower = toStart ? 0 : min(duration, start + minimumClipDuration)
        let upper = toStart ? max(0, end - minimumClipDuration) : duration
        let stepped = steppedFrameTime(from: value, frameOffset: frameOffset, lower: lower, upper: upper)
        guard abs(stepped - value) > frameDuration / 1_000 else { return }

        isApplyingFrameStep = true
        if toStart {
            start = stepped
            startText = timeText(stepped)
        } else {
            end = stepped
            endText = timeText(stepped)
        }
        seek(to: stepped)
        DispatchQueue.main.async { isApplyingFrameStep = false }
    }

    private func canStep(_ value: Double, frameOffset: Int, lower: Double, upper: Double) -> Bool {
        abs(steppedFrameTime(from: value, frameOffset: frameOffset, lower: lower, upper: upper) - value) > frameDuration / 1_000
    }

    private func steppedFrameTime(from value: Double, frameOffset: Int, lower: Double, upper: Double) -> Double {
        guard upper >= lower else { return value }
        let epsilon = frameDuration / 10_000
        let frameIndex: Int
        if frameOffset < 0 {
            frameIndex = Int(ceil(value / frameDuration - epsilon)) + frameOffset
        } else {
            frameIndex = Int(floor(value / frameDuration + epsilon)) + frameOffset
        }
        return min(upper, max(lower, Double(frameIndex) * frameDuration))
    }

    private func applyStart(live: Bool) {
        guard let value = live ? parseLiveTime(startText) : parseTime(startText) else {
            if !live { startText = timeText(start) }
            return
        }
        start = min(max(0, value), max(0, end - minimumClipDuration))
        seek(to: start)
    }
    private func applyEnd(live: Bool) {
        guard let value = live ? parseLiveTime(endText) : parseTime(endText) else {
            if !live { endText = timeText(end) }
            return
        }
        end = max(min(duration, value), min(duration, start + minimumClipDuration))
        seek(to: end)
    }
    private func timeText(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", milliseconds / 3_600_000, (milliseconds / 60_000) % 60, (milliseconds / 1000) % 60, milliseconds % 1000)
    }
    private func parseTime(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = Double(trimmed), seconds >= 0 { return seconds }
        let parts = trimmed.split(separator: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]), hours >= 0, minutes >= 0, seconds >= 0 else { return nil }
        return hours * 3_600 + minutes * 60 + seconds
    }

    /// Live updates only accept the displayed HH:MM:SS.mmm form. This avoids
    /// changing the trim point while a user is still entering a partial value.
    private func parseLiveTime(_ value: String) -> Double? {
        let pattern = #"^\d{2}:\d{2}:\d{2}\.\d{3}$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return parseTime(value)
    }
}

private enum CropAspect: String, CaseIterable, Identifiable {
    case original = "原始", landscape = "16:9", portrait = "9:16", standard = "4:3", verticalStandard = "3:4", square = "1:1"
    var id: String { rawValue }
    var ratio: Double? {
        switch self {
        case .original: nil
        case .landscape: 16.0 / 9.0
        case .portrait: 9.0 / 16.0
        case .standard: 4.0 / 3.0
        case .verticalStandard: 3.0 / 4.0
        case .square: 1
        }
    }
}

private struct CropEditor: View {
    let source: URL
    let initialCrop: CropRect?
    let confirm: (CropRect?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var mediaDuration = 0.0
    @State private var sourceWidth = 0
    @State private var sourceHeight = 0
    @State private var crop: CropRect?
    @State private var xText = "0"
    @State private var yText = "0"
    @State private var widthText = "0"
    @State private var heightText = "0"
    @State private var loadError: String?
    @State private var inspectionTask: Task<Void, Never>?

    var body: some View {
        // Scheme A keeps every editing control in one vertical flow: preview,
        // transport, then a compact parameter card.  The canvas stays clear so
        // the crop frame remains the focus of the editor.
        VStack(alignment: .leading, spacing: 10) {
            Text(source.lastPathComponent).font(AppFont.section).foregroundStyle(BrandColor.textPrimary).lineLimit(1)

            if sourceWidth > 0, sourceHeight > 0 {
                ZStack {
                    PlayerPreview(player: player, showsControls: false)
                    if let crop {
                        CropGuide(crop: crop, sourceWidth: sourceWidth, sourceHeight: sourceHeight) { updatedCrop in
                            applyGuideCrop(updatedCrop)
                        }
                    }

                    Text("\(sourceWidth) × \(sourceHeight)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 270)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                CropPlaybackControls(player: player, duration: sourceDuration)

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("裁切参数"))
                        .font(AppFont.captionMedium)
                        .foregroundStyle(BrandColor.textPrimary)
                    HStack(alignment: .center, spacing: 10) {
                        Text(L10n.text("宽高比"))
                            .font(AppFont.captionMedium)
                            .foregroundStyle(BrandColor.textSecondary)
                        ForEach(CropAspect.allCases) { aspect in
                            Button(L10n.text(aspect.rawValue)) { applyAspect(aspect) }
                                .buttonStyle(CropAspectButtonStyle(isActive: isAspectActive(aspect)))
                        }
                    }
                    HStack(spacing: 10) {
                        cropField("X", text: $xText)
                        cropField("Y", text: $yText)
                        cropField("W", text: $widthText)
                        cropField("H", text: $heightText)
                    }
                    HStack(spacing: 8) {
                        Text(L10n.format("视频尺寸：%d × %d", sourceWidth, sourceHeight))
                        Text(L10n.format("时长：%@", cropDurationText(sourceDuration)))
                        Spacer(minLength: 12)
                        Button(L10n.text("取消")) { dismiss() }
                            .buttonStyle(EditorActionButtonStyle(primary: false))
                        Button(L10n.text("确认裁切")) {
                            confirm(crop.flatMap { isFull($0) ? nil : $0 })
                            dismiss()
                        }
                        .buttonStyle(EditorActionButtonStyle(primary: true))
                        .disabled(crop == nil)
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(BrandColor.textSecondary)
                }
                .padding(12)
                .background(BrandColor.selectSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(BrandColor.selectStroke, lineWidth: 1) }
            } else if let loadError {
                EditorLoadFailure(message: loadError)
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                HStack(spacing: 10) { ProgressView(); Text(L10n.text("正在加载裁切预览")).foregroundStyle(BrandColor.textSecondary) }
                    .frame(maxWidth: .infinity, minHeight: 280)
            }
            if sourceWidth <= 0 || sourceHeight <= 0 {
                HStack {
                    Spacer()
                    Button(L10n.text("取消")) { dismiss() }
                        .buttonStyle(EditorActionButtonStyle(primary: false))
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        // Match the initial loading state to the ready editor so the sheet never
        // jumps upward while metadata and the first frame are being prepared.
        .frame(width: 760, height: 570, alignment: .top)
        .onAppear { loadMedia() }
        .onDisappear { inspectionTask?.cancel(); player?.pause() }
    }

    private func cropField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title)).font(AppFont.captionMedium).foregroundStyle(BrandColor.textSecondary)
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(BrandColor.textPrimary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(BrandColor.selectStroke, lineWidth: 1) }
                .onChange(of: text.wrappedValue) { _ in applyFields() }
                .onSubmit { applyFields() }
        }
        .frame(maxWidth: .infinity)
    }

    private func loadMedia() {
        inspectionTask?.cancel()
        inspectionTask = Task {
            let previewPlayer = AVPlayer(url: source)
            previewPlayer.actionAtItemEnd = .pause
            player = previewPlayer
            let media = await EditorMediaProbe.inspect(source: source)
            guard !Task.isCancelled else { return }
            guard let media else {
                loadError = L10n.text("无法加载裁切预览")
                return
            }
            sourceWidth = media.width
            sourceHeight = media.height
            mediaDuration = media.duration
            crop = initialCrop.map(normalized) ?? fullRect
            syncFields()
            // AVPlayerView can otherwise remain black until the user presses
            // play on some files. Seek once after the view has a valid item so
            // the first decodable frame is presented immediately.
            let previewTime = CMTime(seconds: min(max(media.duration * 0.01, 0.04), 0.2), preferredTimescale: 600)
            previewPlayer.seek(to: previewTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                previewPlayer.pause()
            }
        }
    }

    private func applyAspect(_ aspect: CropAspect) {
        guard let ratio = aspect.ratio else { crop = fullRect; syncFields(); return }
        let sourceRatio = Double(sourceWidth) / Double(sourceHeight)
        let width: Int
        let height: Int
        if sourceRatio > ratio {
            height = sourceHeight
            width = evenDown(Int((Double(height) * ratio).rounded(.down)))
        } else {
            width = sourceWidth
            height = evenDown(Int((Double(width) / ratio).rounded(.down)))
        }
        crop = CropRect(x: evenDown((sourceWidth - width) / 2), y: evenDown((sourceHeight - height) / 2), width: width, height: height)
        syncFields()
    }

    private func applyFields() {
        guard let x = Int(xText), let y = Int(yText), let width = Int(widthText), let height = Int(heightText), sourceWidth > 0, sourceHeight > 0 else { return }
        let boundedX = min(max(0, evenDown(x)), max(0, sourceWidth - 2))
        let boundedY = min(max(0, evenDown(y)), max(0, sourceHeight - 2))
        let boundedWidth = min(max(2, evenDown(width)), sourceWidth - boundedX)
        let boundedHeight = min(max(2, evenDown(height)), sourceHeight - boundedY)
        guard boundedWidth > 0, boundedHeight > 0 else { return }
        crop = CropRect(x: boundedX, y: boundedY, width: evenDown(boundedWidth), height: evenDown(boundedHeight))
    }

    private func applyGuideCrop(_ updated: CropRect) {
        crop = normalized(updated)
        syncFields()
    }

    private var fullRect: CropRect { CropRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight) }
    private var sourceDuration: Double { mediaDuration }
    private func isFull(_ rect: CropRect) -> Bool { rect == fullRect }
    private func normalized(_ rect: CropRect) -> CropRect {
        let x = min(max(0, evenDown(rect.x)), max(0, sourceWidth - 2))
        let y = min(max(0, evenDown(rect.y)), max(0, sourceHeight - 2))
        return CropRect(x: x, y: y, width: min(max(2, evenDown(rect.width)), sourceWidth - x), height: min(max(2, evenDown(rect.height)), sourceHeight - y))
    }
    private func evenDown(_ value: Int) -> Int { max(2, value - value % 2) }
    private func syncFields() {
        guard let crop else { return }
        xText = "\(crop.x)"; yText = "\(crop.y)"; widthText = "\(crop.width)"; heightText = "\(crop.height)"
    }
    private func isAspectActive(_ aspect: CropAspect) -> Bool {
        guard let crop else { return aspect == .original }
        guard let ratio = aspect.ratio else { return isFull(crop) }
        return abs(Double(crop.width) / Double(crop.height) - ratio) < 0.01
    }

    private func cropDurationText(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct CropGuide: View {
    let crop: CropRect
    let sourceWidth: Int
    let sourceHeight: Int
    let onChange: (CropRect) -> Void
    @State private var moveOrigin: CropRect?
    @State private var resizeOrigin: CropRect?

    /// Eight handles make the frame feel like a native editing canvas while
    /// retaining the four-corner resize behaviour people expect.
    private enum Handle: CaseIterable {
        case topLeading, top, topTrailing, trailing, bottomTrailing, bottom, bottomLeading, leading
    }

    var body: some View {
        GeometryReader { proxy in
            let videoRect = fittedVideoRect(in: proxy.size)
            let frame = guideFrame(in: videoRect)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(BrandColor.blue, lineWidth: 2)
                    .background(Color.clear.contentShape(Rectangle()))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .gesture(moveGesture(in: videoRect))

                ForEach(Handle.allCases, id: \.self) { handle in
                    resizeHandle(handle, in: frame)
                        .gesture(resizeGesture(handle, in: videoRect))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("裁切区域，可拖动移动或调整四角"))
    }

    private func fittedVideoRect(in size: CGSize) -> CGRect {
        let videoRatio = CGFloat(sourceWidth) / CGFloat(sourceHeight)
        let containerRatio = size.width / size.height
        if containerRatio > videoRatio {
            let height = size.height
            let width = height * videoRatio
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: height)
        }
        let width = size.width
        let height = width / videoRatio
        return CGRect(x: 0, y: (size.height - height) / 2, width: width, height: height)
    }

    private func guideFrame(in videoRect: CGRect) -> CGRect {
        CGRect(
            x: videoRect.minX + CGFloat(crop.x) / CGFloat(sourceWidth) * videoRect.width,
            y: videoRect.minY + CGFloat(crop.y) / CGFloat(sourceHeight) * videoRect.height,
            width: CGFloat(crop.width) / CGFloat(sourceWidth) * videoRect.width,
            height: CGFloat(crop.height) / CGFloat(sourceHeight) * videoRect.height
        )
    }

    private func resizeHandle(_ handle: Handle, in frame: CGRect) -> some View {
        let point: CGPoint = switch handle {
        case .topLeading: CGPoint(x: frame.minX, y: frame.minY)
        case .top: CGPoint(x: frame.midX, y: frame.minY)
        case .topTrailing: CGPoint(x: frame.maxX, y: frame.minY)
        case .trailing: CGPoint(x: frame.maxX, y: frame.midY)
        case .bottomLeading: CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomTrailing: CGPoint(x: frame.maxX, y: frame.maxY)
        case .bottom: CGPoint(x: frame.midX, y: frame.maxY)
        case .leading: CGPoint(x: frame.minX, y: frame.midY)
        }
        return Circle()
            .fill(BrandColor.surface)
            .frame(width: 12, height: 12)
            .overlay { Circle().stroke(BrandColor.blue, lineWidth: 2) }
            .position(point)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .accessibilityLabel(L10n.text("调整裁切区域"))
    }

    private func moveGesture(in videoRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if moveOrigin == nil { moveOrigin = crop }
                guard let origin = moveOrigin else { return }
                let dx = Int((value.translation.width / videoRect.width * CGFloat(sourceWidth)).rounded())
                let dy = Int((value.translation.height / videoRect.height * CGFloat(sourceHeight)).rounded())
                onChange(constrained(CropRect(x: origin.x + dx, y: origin.y + dy, width: origin.width, height: origin.height)))
            }
            .onEnded { _ in moveOrigin = nil }
    }

    private func resizeGesture(_ handle: Handle, in videoRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if resizeOrigin == nil { resizeOrigin = crop }
                guard let origin = resizeOrigin else { return }
                let dx = Int((value.translation.width / videoRect.width * CGFloat(sourceWidth)).rounded())
                let dy = Int((value.translation.height / videoRect.height * CGFloat(sourceHeight)).rounded())
                onChange(resized(origin, handle: handle, dx: dx, dy: dy))
            }
            .onEnded { _ in resizeOrigin = nil }
    }

    private func resized(_ origin: CropRect, handle: Handle, dx: Int, dy: Int) -> CropRect {
        let right = origin.x + origin.width
        let bottom = origin.y + origin.height
        let minSide = 32
        switch handle {
        case .topLeading:
            let x = min(max(0, origin.x + dx), right - minSide)
            let y = min(max(0, origin.y + dy), bottom - minSide)
            return constrained(CropRect(x: x, y: y, width: right - x, height: bottom - y))
        case .top:
            let y = min(max(0, origin.y + dy), bottom - minSide)
            return constrained(CropRect(x: origin.x, y: y, width: origin.width, height: bottom - y))
        case .topTrailing:
            let y = min(max(0, origin.y + dy), bottom - minSide)
            let rightEdge = max(origin.x + minSide, min(sourceWidth, right + dx))
            return constrained(CropRect(x: origin.x, y: y, width: rightEdge - origin.x, height: bottom - y))
        case .trailing:
            let rightEdge = max(origin.x + minSide, min(sourceWidth, right + dx))
            return constrained(CropRect(x: origin.x, y: origin.y, width: rightEdge - origin.x, height: origin.height))
        case .bottomLeading:
            let x = min(max(0, origin.x + dx), right - minSide)
            let bottomEdge = max(origin.y + minSide, min(sourceHeight, bottom + dy))
            return constrained(CropRect(x: x, y: origin.y, width: right - x, height: bottomEdge - origin.y))
        case .bottomTrailing:
            let rightEdge = max(origin.x + minSide, min(sourceWidth, right + dx))
            let bottomEdge = max(origin.y + minSide, min(sourceHeight, bottom + dy))
            return constrained(CropRect(x: origin.x, y: origin.y, width: rightEdge - origin.x, height: bottomEdge - origin.y))
        case .bottom:
            let bottomEdge = max(origin.y + minSide, min(sourceHeight, bottom + dy))
            return constrained(CropRect(x: origin.x, y: origin.y, width: origin.width, height: bottomEdge - origin.y))
        case .leading:
            let x = min(max(0, origin.x + dx), right - minSide)
            return constrained(CropRect(x: x, y: origin.y, width: right - x, height: origin.height))
        }
    }

    private func constrained(_ value: CropRect) -> CropRect {
        let minimum = 32
        let x = max(0, min(sourceWidth - minimum, even(value.x)))
        let y = max(0, min(sourceHeight - minimum, even(value.y)))
        let width = max(minimum, min(sourceWidth - x, even(value.width)))
        let height = max(minimum, min(sourceHeight - y, even(value.height)))
        return CropRect(x: x, y: y, width: width, height: height)
    }

    private func even(_ value: Int) -> Int { value / 2 * 2 }
}

private struct CropAspectButtonStyle: ButtonStyle {
    let isActive: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.captionMedium)
            .foregroundStyle(isActive ? .white : BrandColor.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isActive ? BrandColor.blue : BrandColor.selectSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(isActive ? BrandColor.blue : BrandColor.selectStroke, lineWidth: 1) }
    }
}

struct EditorMediaInfo: Sendable {
    let duration: Double
    let width: Int
    let height: Int
    let frameRate: Double

    var frameDuration: Double { 1 / frameRate }
}

/// Editors must never wait on AVFoundation's lazy duration loading.  FFprobe is
/// already the conversion engine's source of truth and returns the dimensions
/// and duration in one bounded process call.
enum EditorMediaProbe {
    private struct Response: Decodable {
        let streams: [Stream]
        let format: Format?
    }
    private struct Stream: Decodable {
        let codecType: String?
        let width: Int?
        let height: Int?
        let frameRate: String?
        enum CodingKeys: String, CodingKey {
            case codecType = "codec_type"
            case width, height
            case frameRate = "r_frame_rate"
        }
    }
    private struct Format: Decodable {
        let duration: String?
    }

    static func inspect(source: URL, using probeOverride: URL? = nil) async -> EditorMediaInfo? {
        let candidates = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/opt/local/bin/ffprobe", "/usr/bin/ffprobe"]
        guard let binary = probeOverride ?? candidates
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }

        // Editors share the same bounded, cancellable pipe owner as conversion.
        // Closing a loading sheet cancels inspection rather than leaving a
        // detached probe alive, and stderr cannot fill an undrained pipe.
        let result = await FFmpegProcessRunner(
            executable: binary,
            arguments: ["-v", "error", "-show_entries", "stream=codec_type,width,height,r_frame_rate:format=duration", "-of", "json", source.path],
            configuration: FFmpegProcessRunner.Configuration(inactivityTimeout: 5, terminationGrace: 0.5, maximumOutputBytes: 1_000_000)
        ).run()
        guard !Task.isCancelled, result.succeeded,
              let response = try? JSONDecoder().decode(Response.self, from: result.standardOutput),
              let video = response.streams.first(where: { $0.codecType == "video" }),
              let width = video.width, let height = video.height,
              width > 0, height > 0,
              let duration = Double(response.format?.duration ?? ""), duration.isFinite, duration > 0 else { return nil }
        return EditorMediaInfo(duration: duration, width: width, height: height, frameRate: parseFrameRate(video.frameRate) ?? 30)
    }

    private static func parseFrameRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        let rate: Double?
        if parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 {
            rate = numerator / denominator
        } else {
            rate = Double(value)
        }
        guard let rate, rate.isFinite, (1...240).contains(rate) else { return nil }
        return rate
    }
}

/// A lightweight AppKit-backed player preview.  Unlike SwiftUI's `VideoPlayer`,
/// this view has a stable lifecycle when it is presented in an editor sheet.
private struct PlayerPreview: NSViewRepresentable {
    let player: AVPlayer?
    var showsControls = true

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = showsControls ? .floating : .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
        view.controlsStyle = showsControls ? .floating : .none
    }
}

/// Cropping keeps transport controls outside the video canvas. This gives the
/// crop rectangle the whole preview to work in without blocking play, seeking,
/// volume, or skip actions.
private struct CropPlaybackControls: View {
    let player: AVPlayer?
    let duration: Double
    @State private var currentTime = 0.0
    @State private var isPlaying = false
    @State private var volume = Float(1)
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 12) {
            transportButton(icon: .playerSkipBack, title: "后退 5 秒") { move(by: -5) }
            transportButton(icon: isPlaying ? .playerPause : .playerPlay, title: isPlaying ? "暂停" : "播放") { togglePlayback() }
            transportButton(icon: .playerSkipForward, title: "前进 5 秒") { move(by: 5) }

            Text(timeText(currentTime))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(BrandColor.textSecondary)
                .frame(width: 48, alignment: .trailing)
            Slider(value: Binding(get: { currentTime }, set: { seek(to: $0) }), in: 0...max(0.1, duration))
                .tint(BrandColor.blue)
                .accessibilityLabel(L10n.text("播放进度"))
                .help(L10n.text("播放进度"))
            Text(timeText(duration))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(BrandColor.textSecondary)
                .frame(width: 48, alignment: .leading)

            TablerIcon(name: .volume, color: BrandColor.icon)
                .frame(width: 15, height: 15)
            Slider(value: Binding(get: { Double(volume) }, set: { value in
                volume = Float(value)
                player?.volume = volume
            }), in: 0...1)
                .tint(BrandColor.blue)
                .frame(width: 68)
                .accessibilityLabel(L10n.text("音量"))
                .help(L10n.text("音量"))
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(BrandColor.selectStroke, lineWidth: 1) }
        .onAppear { installTimeObserver() }
        .onDisappear { removeTimeObserver() }
    }

    private func transportButton(icon: TablerIconName, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TablerIcon(name: icon, color: BrandColor.textPrimary)
                .frame(width: 16, height: 16)
                .frame(width: 20, height: 24)
        }
        .buttonStyle(.plain)
        .help(L10n.text(title))
        .accessibilityLabel(L10n.text(title))
    }

    private func installTimeObserver() {
        guard let player, timeObserver == nil else { return }
        volume = player.volume
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600), queue: .main) { time in
            let seconds = time.seconds
            if seconds.isFinite { currentTime = min(max(0, seconds), duration) }
            isPlaying = player.timeControlStatus == .playing
        }
    }

    private func removeTimeObserver() {
        guard let player, let timeObserver else { return }
        player.removeTimeObserver(timeObserver)
        self.timeObserver = nil
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= max(0.1, duration - 0.05) { seek(to: 0) }
            player.play()
            isPlaying = true
        }
    }

    private func move(by seconds: Double) { seek(to: currentTime + seconds) }

    private func seek(to seconds: Double) {
        let value = min(max(0, seconds), duration)
        currentTime = value
        player?.seek(to: CMTime(seconds: value, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func timeText(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct TrimRangeSlider: View {
    let duration: Double
    let minimumLength: Double
    @Binding var start: Double
    @Binding var end: Double
    let onSeek: (Double) -> Void
    @State private var startDragOrigin: Double?
    @State private var endDragOrigin: Double?

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = 4
            let width = max(1, geometry.size.width - horizontalInset * 2)
            let lower = CGFloat(start / duration) * width + horizontalInset
            let upper = CGFloat(end / duration) * width + horizontalInset
            ZStack(alignment: .leading) {
                VStack(spacing: 4) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(BrandColor.selectStroke.opacity(0.55)).frame(height: 7)
                        Capsule().fill(BrandColor.blue).frame(width: max(0, upper - lower), height: 7).offset(x: lower)
                    }
                    HStack(spacing: 0) {
                        ForEach(0...6, id: \.self) { index in
                            VStack(spacing: 2) {
                                Rectangle().fill(BrandColor.selectStroke).frame(width: 1, height: 5)
                                Text(shortTimeText(Double(index) / 6 * duration))
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(BrandColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == 6 ? .trailing : .center))
                        }
                    }
                }
                handle(at: lower).gesture(drag(in: geometry.size, edge: .start))
                handle(at: upper).gesture(drag(in: geometry.size, edge: .end))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("剪辑范围"))
    }

    private func handle(at position: CGFloat) -> some View {
        Circle().fill(BrandColor.surface).frame(width: 18, height: 18)
            .overlay { Circle().stroke(BrandColor.blue, lineWidth: 1.5) }
            .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
            .offset(x: position - 13, y: -10)
    }

    private enum Edge { case start, end }

    /// DragGesture locations are local to the 28 pt handle, not to the full
    /// timeline. Use the drag translation plus the captured range endpoint so
    /// the visual handle and the bound form value always describe one time.
    private func drag(in size: CGSize, edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let travel = max(1, size.width - 8)
                let delta = Double(value.translation.width / travel) * duration
                switch edge {
                case .start:
                    if startDragOrigin == nil { startDragOrigin = start }
                    start = min(max(0, (startDragOrigin ?? start) + delta), end - minimumLength)
                    onSeek(start)
                case .end:
                    if endDragOrigin == nil { endDragOrigin = end }
                    end = max(min(duration, (endDragOrigin ?? end) + delta), start + minimumLength)
                    onSeek(end)
                }
            }
            .onEnded { _ in
                startDragOrigin = nil
                endDragOrigin = nil
            }
    }

    private func shortTimeText(_ value: Double) -> String {
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
