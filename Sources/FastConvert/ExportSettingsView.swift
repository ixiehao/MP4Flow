import SwiftUI

struct ExportSettingsView: View {
    @ObservedObject var store: ConverterStore
    let item: ConversionItem
    @Environment(\.dismiss) private var dismiss
    @State private var options: ExportOptions
    @State private var limitSize: Bool
    @State private var sizeText: String
    private enum InspectionState {
        case loading
        case ready(VideoInfo, canBurn: Bool)
        case failed(String)
    }
    @State private var inspection = InspectionState.loading
    @State private var inspectionRevision = UUID()
    private var info: VideoInfo? { if case .ready(let info, _) = inspection { info } else { nil } }
    private var burnAvailable: Bool { if case .ready(_, let available) = inspection { available } else { false } }
    private var loadError: String? { if case .failed(let error) = inspection { error } else { nil } }
    @FocusState private var sizeIsFocused: Bool

    init(store: ConverterStore, item: ConversionItem) {
        self.store = store; self.item = item
        _options = State(initialValue: item.exportOptions)
        _limitSize = State(initialValue: item.exportOptions.targetSizeMB != nil)
        let suggestedSize = ExportOptions.suggestedTargetMegabytes(sourceBytes: item.presentation?.fileSize)
        _sizeText = State(initialValue: item.exportOptions.targetSizeMB.map { String(format: "%g", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? String(suggestedSize))
    }

    private var value: ExportOptions {
        var value = options
        let number = sizeText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        value.targetSizeMB = limitSize ? (number.allSatisfy { "0123456789.".contains($0) } ? Double(number) ?? .nan : .nan) : nil
        return value.normalized
    }
    private var validation: String? {
        guard let info else { return loadError ?? L10n.text("正在读取视频信息") }
        do {
            _ = try ExportPlan(options: value, info: info, trim: item.trimRange, preset: store.preset, canBurnSubtitles: burnAvailable)
            return nil
        } catch { return error.localizedDescription }
    }

    var body: some View {
        // Keep the sheet's outer geometry independent of loading and optional
        // rows. This avoids AppKit shifting the sheet on its first layout pass.
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let info {
                        VStack(spacing: 0) {
                            sizeSection(info)
                            formDivider
                            audioSection(info)
                            formDivider
                            subtitleSection(info)
                        }
                        .background(BrandColor.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BrandColor.stroke) }
                        if let validation { validationNotice(validation) }
                        if value.subtitles == .burn && !burnAvailable {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("brew install ffmpeg-full").font(AppFont.caption.monospaced()).textSelection(.enabled)
                                Text(L10n.text("安装后重新打开导出设置。")).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
                                Link(L10n.text("字幕烧录安装说明"), destination: URL(string: "https://formulae.brew.sh/formula/ffmpeg-full")!)
                                    .font(AppFont.caption).foregroundStyle(BrandColor.blue)
                            }.padding(.horizontal, 12)
                        }
                        if store.preset == .smartEnhanceUpscale && !value.supportsNativeEnhancement(info: info) {
                            Button(L10n.text("使用智能转换")) { store.preset = .smartMP4 }
                                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 100, height: 34))
                        }
                    } else if let loadError {
                        VStack(alignment: .leading, spacing: 14) {
                            validationNotice(loadError)
                            Button(L10n.text("重新检查")) { inspectionRevision = UUID() }
                                .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 90, height: 34))
                        }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text("正在读取视频信息")).font(AppFont.body).foregroundStyle(BrandColor.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 320)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 2)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .frame(width: 640, height: 536)
        .background(BrandColor.surface)
        .task(id: inspectionRevision) { await load() }
        .onChange(of: options.audio) { mode in
            if mode == .selected && options.audioStreamIndex == nil { options.audioStreamIndex = info?.audioTracks.first?.index }
        }
        .onChange(of: options.subtitles) { mode in
            if mode != .none && options.subtitleStreamIndex == nil { options.subtitleStreamIndex = info?.subtitleTracks.first?.index }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TablerIcon(name: .settings, color: BrandColor.blue)
                .frame(width: 21, height: 21)
                .frame(width: 42, height: 42)
                .background(BrandColor.selectHover, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("导出设置")).font(AppFont.headline).foregroundStyle(BrandColor.textPrimary)
                Text(item.source.lastPathComponent).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
                    .lineLimit(1).truncationMode(.middle).help(item.source.lastPathComponent)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(BrandColor.stroke).frame(height: 1)
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(L10n.text("取消")) { dismiss() }
                    .buttonStyle(AppActionButtonStyle(primary: false, minWidth: 84, height: 36))
                    .keyboardShortcut(.cancelAction)
                Button(L10n.text("应用设置")) {
                    store.setExportOptions(value, for: item)
                    store.saveQueueNow()
                    dismiss()
                }
                .buttonStyle(AppActionButtonStyle(primary: true, minWidth: 102, height: 36))
                .keyboardShortcut(.defaultAction)
                .disabled(validation != nil || store.isBusy)
            }
            .padding(.horizontal, 22).padding(.vertical, 16)
        }
        .background(BrandColor.surface)
    }

    private var formDivider: some View {
        Rectangle().fill(BrandColor.stroke).frame(height: 1).padding(.horizontal, 16)
    }

    private func sizeSection(_ info: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                sectionLabel("目标体积", icon: .database)
                Spacer(minLength: 12)
                if limitSize { sizeInput }
                Toggle(L10n.text("按目标体积压缩"), isOn: $limitSize)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).tint(BrandColor.blue)
                    .accessibilityLabel(L10n.text("按目标体积压缩"))
            }
            Text(L10n.text(limitSize ? "体积优先，画质可能下降。增大目标或关闭限制可保留更多细节。" : "限制体积会重新编码，画质可能下降。"))
                .font(AppFont.caption).foregroundStyle(BrandColor.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var sizeInput: some View {
        HStack(spacing: 8) {
            Text(L10n.text("约")).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
            TextField("100", text: $sizeText)
                .textFieldStyle(.plain).font(AppFont.medium.monospacedDigit()).multilineTextAlignment(.trailing)
                .frame(width: 65).focused($sizeIsFocused)
                .accessibilityLabel(L10n.text("目标体积（MB）"))
            Text("MB").font(AppFont.captionMedium).foregroundStyle(BrandColor.textSecondary)
        }
        .padding(.horizontal, 11).frame(height: 36)
        .background(BrandColor.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(sizeIsFocused ? BrandColor.blue : BrandColor.selectStroke, lineWidth: sizeIsFocused ? 1.5 : 1) }
    }

    private func audioSection(_ info: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                sectionLabel("音轨", icon: .volume)
                Spacer(minLength: 0)
                ExportChoiceMenu(title: options.audio.title, accessibilityTitle: L10n.text("输出音轨")) { close in
                    ForEach(AudioSelection.allCases, id: \.self) { mode in
                        ExportChoiceRow(title: mode.title, isSelected: mode == options.audio) {
                            options.audio = mode; close()
                        }
                    }
                }
                .frame(width: 300)
            }
            if options.audio == .selected { trackPicker(info.audioTracks, selection: $options.audioStreamIndex) }
            if info.audioTracks.isEmpty { emptyHint("未检测到音轨") }
        }
        .padding(16)
    }

    private func subtitleSection(_ info: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                sectionLabel("字幕", icon: .language)
                Spacer(minLength: 0)
                ExportChoiceMenu(title: options.subtitles.title, accessibilityTitle: L10n.text("字幕处理")) { close in
                    ForEach(SubtitleTreatment.allCases, id: \.self) { mode in
                        ExportChoiceRow(title: mode.title, isSelected: mode == options.subtitles, isEnabled: mode == .none || !info.subtitleTracks.isEmpty) {
                            options.subtitles = mode; close()
                        }
                    }
                }
                .frame(width: 300)
            }
            if options.subtitles != .none { trackPicker(info.subtitleTracks, selection: $options.subtitleStreamIndex) }
            if info.subtitleTracks.isEmpty {
                emptyHint("未检测到字幕")
            } else if options.subtitles != .none {
                Text(L10n.text(options.subtitles == .burn ? "烧录后字幕无法关闭；需要支持 libass 的 FFmpeg。" : "保留文字字幕时样式可能简化；未选中的字幕不输出。"))
                    .font(AppFont.caption).foregroundStyle(BrandColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
    }

    private func sectionLabel(_ title: String, icon: TablerIconName) -> some View {
        HStack(spacing: 9) {
            TablerIcon(name: icon, color: BrandColor.blue).frame(width: 17, height: 17)
            Text(L10n.text(title)).font(AppFont.medium).foregroundStyle(BrandColor.textPrimary).lineLimit(1)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(L10n.text(text)).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
    }

    private func trackPicker(_ tracks: [MediaTrack], selection: Binding<Int?>) -> some View {
        let selectedTitle = tracks.first(where: { $0.index == selection.wrappedValue })?.label
            ?? L10n.text(selection.wrappedValue == nil ? "请选择" : "所选项目已不可用")
        return HStack(spacing: 16) {
            Text(L10n.text("轨道")).font(AppFont.caption).foregroundStyle(BrandColor.textSecondary)
                .padding(.leading, 26)
            Spacer(minLength: 0)
            ExportChoiceMenu(title: selectedTitle, accessibilityTitle: L10n.text("轨道")) { close in
                ExportChoiceRow(title: L10n.text("请选择"), isSelected: selection.wrappedValue == nil) {
                    selection.wrappedValue = nil; close()
                }
                ForEach(tracks) { track in
                    ExportChoiceRow(title: track.label, isSelected: track.index == selection.wrappedValue) {
                        selection.wrappedValue = track.index; close()
                    }
                }
            }
            .frame(width: 300)
        }
    }

    private func validationNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            TablerIcon(name: .alertCircle, color: BrandColor.warning).frame(width: 16, height: 16)
            Text(message).font(AppFont.caption).foregroundStyle(BrandColor.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColor.warningBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func load() async {
        inspection = .loading
        do {
            async let media = store.exportInfo(for: item.source)
            async let capability = store.subtitleBurningAvailable()
            let (result, available) = try await (media, capability)
            guard !Task.isCancelled else { return }
            inspection = .ready(result, canBurn: available)
        } catch {
            if !Task.isCancelled { inspection = .failed(error.localizedDescription) }
        }
    }
}

/// Matches the main window's selector geometry rather than exposing the compact
/// AppKit popup bezel inside an otherwise custom SwiftUI form.
private struct ExportChoiceMenu<Content: View>: View {
    let title: String
    let accessibilityTitle: String
    @ViewBuilder let content: (@escaping () -> Void) -> Content
    @State private var isPresented = false
    @State private var isHovering = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 8) {
                Text(title).font(AppFont.medium).foregroundStyle(BrandColor.textPrimary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                TablerIcon(name: .chevronDown, color: BrandColor.icon).frame(width: 15, height: 15)
            }
            .padding(.leading, 12).padding(.trailing, 9)
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(isHovering || isPresented ? BrandColor.selectHover : BrandColor.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isHovering || isPresented ? BrandColor.selectHoverStroke : BrandColor.selectStroke) }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 2) { content { isPresented = false } }
                .padding(6).frame(width: 330).background(BrandColor.surface)
        }
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(title)
        .help(title)
    }
}

private struct ExportChoiceRow: View {
    let title: String
    let isSelected: Bool
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                TablerIcon(name: .check, color: BrandColor.blue).frame(width: 15, height: 15).opacity(isSelected ? 1 : 0)
                Text(title).font(AppFont.medium).foregroundStyle(BrandColor.textPrimary).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 34)
            .background(isSelected ? BrandColor.selectHover : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!isEnabled).opacity(isEnabled ? 1 : 0.4)
        .help(title)
    }
}
