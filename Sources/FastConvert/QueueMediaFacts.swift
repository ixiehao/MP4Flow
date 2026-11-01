import SwiftUI

/// Facts are atomic: adapt the grouping before ever truncating a number or
/// separating a file size from its unit. All languages share these layouts.
struct QueueMediaFacts: View {
    let presentation: VideoPresentation?

    var body: some View {
        Group {
            if let presentation, !presentation.factFields.isEmpty {
                let fields = presentation.factFields
                ViewThatFits(in: .horizontal) {
                    inline(fields)
                    if fields.count == 3 {
                        VStack(alignment: .leading, spacing: 2) {
                            inline(Array(fields.prefix(2)))
                            Text(fields[2]).fixedSize()
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            Text(field).fixedSize()
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(fields.joined(separator: " · "))
            } else {
                Text(L10n.text(presentation == nil ? "正在读取视频信息" : "准备输出 MP4"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(AppFont.caption.monospacedDigit())
        .foregroundStyle(BrandColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ fields: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(fields.enumerated()), id: \.offset) { offset, field in
                if offset > 0 { Text("·") }
                Text(field)
            }
        }
        .fixedSize()
    }
}
