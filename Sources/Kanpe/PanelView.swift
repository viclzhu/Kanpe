import SwiftUI
import KanpeCore

struct PanelView: View {
    let content: PanelContent
    let icon: NSImage?
    let columns: [[ShortcutGroup]]
    static let columnWidth: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if content.groups.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.columnWidth * 1.5, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(columns.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(columns[index]) { GroupView(group: $0) }
                        }
                        .frame(width: Self.columnWidth, alignment: .topLeading)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            }
            Text(content.appName).font(.title3.weight(.semibold))
            if let host = content.host {
                Label(host, systemImage: content.matchedSites.isEmpty ? "globe" : "globe.badge.chevron.backward")
                    .font(.callout)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(content.matchedSites.isEmpty ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.2),
                                in: Capsule())
                    .foregroundStyle(content.matchedSites.isEmpty ? .secondary : .primary)
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyMessage: String {
        AX.isTrusted ? "No keyboard shortcuts found in this app's menus." :
            "Kanpe needs Accessibility access. Open the Kanpe menu-bar icon → Grant Accessibility Access."
    }
}

private struct GroupView: View {
    let group: ShortcutGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if group.source == .site {
                    Image(systemName: "globe").font(.caption.weight(.bold))
                }
                Text(group.title.uppercased())
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(group.source == .site ? Color.accentColor : .secondary)
            .padding(.bottom, 2)

            ForEach(group.shortcuts, id: \.self) { shortcut in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(shortcut.title)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    KeysView(alternatives: shortcut.alternatives)
                }
            }
        }
        .padding(group.source == .site ? 8 : 0)
        .background(group.source == .site ? Color.accentColor.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct KeysView: View {
    let alternatives: [[String]]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(alternatives.enumerated()), id: \.offset) { altIndex, sequence in
                if altIndex > 0 { connector("or") }
                ForEach(Array(sequence.enumerated()), id: \.offset) { index, chord in
                    if index > 0 { connector("then") }
                    Text(chord)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .fixedSize()
                }
            }
        }
    }

    private func connector(_ word: String) -> some View {
        Text(word).font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize()
    }
}
