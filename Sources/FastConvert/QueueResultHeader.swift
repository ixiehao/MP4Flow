import SwiftUI

/// Keep completion facts and their detail action together. Extra column space
/// belongs after this group, never between the result and its explanation.
struct QueueResultHeader: View {
    let outputFileSize: Int64?
    let notice: MediaHandlingNotice?
    @Binding var showsDetails: Bool

    var body: some View {
        // The adaptive action can contain only an image, which has no text
        // baseline. Center that action; align the two textual facts separately.
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L10n.text("已完成")).font(AppFont.rowTitle).foregroundStyle(BrandColor.success)
                if let bytes = outputFileSize {
                    Text(L10n.format("输出 %@", L10n.byteCount(bytes)))
                        .font(AppFont.caption.monospacedDigit()).foregroundStyle(BrandColor.textSecondary)
                }
            }
            .fixedSize().layoutPriority(1)
            if let notice, !notice.information.isEmpty {
                QueueMediaDetailsButton(notice: notice, isPresented: $showsDetails)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }
}

/// A single button and presenter avoid duplicate popovers while its label
/// adapts to long translations or a narrow queue column.
struct QueueMediaDetailsButton: View {
    let notice: MediaHandlingNotice
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented.toggle() } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    informationIcon
                    Text(L10n.text("处理详情")).font(AppFont.caption)
                }.fixedSize()
                informationIcon
            }
            .foregroundStyle(BrandColor.textSecondary)
            .frame(minWidth: 20, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text("处理详情"))
        .accessibilityLabel(L10n.text("处理详情"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.text("处理详情")).font(AppFont.section)
                Text(notice.detail).font(AppFont.body)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack {
                    Spacer()
                    Button(L10n.text("知道了")) { isPresented = false }
                        .buttonStyle(.plain).foregroundStyle(BrandColor.blue)
                }
            }
            .padding(16).frame(width: 340)
        }
    }

    private var informationIcon: some View {
        TablerIcon(name: .infoCircle, color: BrandColor.textSecondary).frame(width: 12, height: 12)
    }
}
