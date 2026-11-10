import SwiftUI
import KanpeCore

// MARK: - Root

struct EditorRootView: View {
    @ObservedObject var model: EditorModel
    @State private var filter = ""
    @State private var pendingDelete: EditableSite.ID?

    private var visibleSites: [EditableSite] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.sites }
        return model.sites.filter { site in
            site.name.lowercased().contains(q) || site.match.contains { $0.contains(q) }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete { model.delete(id) }
                pendingDelete = nil
            }
        } message: {
            Text(deleteMessage)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $model.selection) {
            ForEach(visibleSites) { site in
                SiteRow(site: site, isBuiltIn: model.isBuiltIn(site))
                    .tag(site.id)
                    .contextMenu { siteActions(site.id) }
            }
        }
        .searchable(text: $filter, placement: .sidebar, prompt: "Filter")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if !model.unreadableFiles.isEmpty {
                    Label("Couldn't read: \(model.unreadableFiles.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(spacing: 2) {
                    Button { model.addSite() } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                        .help("Add a site")
                    Button { pendingDelete = model.selection } label: { Image(systemName: "minus").frame(width: 24, height: 20) }
                        .help("Delete the selected site")
                        .disabled(model.selection == nil)
                    Spacer()
                    Menu {
                        Button("Restore Built-in Sites") { model.restoreBuiltIns() }
                            .disabled(!model.hasDeletedBuiltIns)
                        Button("Open Sites Folder") { NSWorkspace.shared.open(model.store.directory) }
                        Button("Reload from Disk") { model.reload() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .background(.bar)
        }
    }

    @ViewBuilder
    private func siteActions(_ id: EditableSite.ID) -> some View {
        Button("Duplicate") { model.duplicate(id) }
        if let site = model.binding(for: id), model.isBuiltIn(site) {
            Button("Revert to Built-in") { model.revertToBuiltIn(id) }
        }
        if let url = model.binding(for: id)?.fileURL {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Divider()
        Button("Delete…", role: .destructive) { pendingDelete = id }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = model.selection, model.binding(for: id) != nil {
            SiteEditor(
                site: Binding(get: { model.binding(for: id) ?? .blank() }, set: { model.update($0) }),
                saveError: model.saveError,
                actions: { siteActions(id) }
            )
            .id(id) // fresh view state (focus, recorders) per site
        } else {
            VStack(spacing: 12) {
                Image(systemName: "globe").font(.system(size: 40)).foregroundStyle(.tertiary)
                Text(model.sites.isEmpty ? "No sites yet" : "Select a site").font(.title3)
                Text("Sites hold the shortcuts Kanpe shows when that website is open in your browser.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Button("Add Site") { model.addSite() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var deleteTitle: String {
        let name = pendingDelete.flatMap(model.binding(for:))?.name ?? "this site"
        return "Delete \u{201C}\(name)\u{201D}?"
    }

    private var deleteMessage: String {
        guard let site = pendingDelete.flatMap(model.binding(for:)) else { return "" }
        return model.isBuiltIn(site)
            ? "This is a built-in site. You can bring it back later with Restore Built-in Sites (••• below the list)."
            : "Its shortcuts will be removed. This can't be undone."
    }
}

private struct SiteRow: View {
    let site: EditableSite
    let isBuiltIn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(String(site.name.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Self.color(for: site.name).gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(site.name.isEmpty ? "Untitled" : site.name)
                    .lineLimit(1)
                Text(site.match.isEmpty ? "No domains" : site.match.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(site.match.isEmpty ? .orange : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    /// Stable color per site name.
    static func color(for name: String) -> Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[sum % palette.count]
    }
}

// MARK: - Site editor

private struct SiteEditor<Actions: View>: View {
    @Binding var site: EditableSite
    let saveError: String?
    @ViewBuilder let actions: () -> Actions
    @FocusState private var focus: UUID?

    var body: some View {
        List {
            Section {
                header
            }

            ForEach($site.groups) { $group in
                Section {
                    ForEach($group.shortcuts) { $shortcut in
                        ShortcutRow(
                            shortcut: $shortcut,
                            level: group.effectiveLevel(of: shortcut),
                            focus: $focus,
                            onLevel: { level in
                                if let i = group.shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                                    group.setLevel(level, forShortcutAt: i)
                                }
                            },
                            onDelete: { group.shortcuts.removeAll { $0.id == shortcut.id } }
                        )
                    }
                    .onMove { group.shortcuts.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        let new = EditableSite.Shortcut()
                        group.shortcuts.append(new)
                        focus = new.id
                    } label: {
                        Label("Add Shortcut", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 2)
                } header: {
                    GroupHeader(group: $group, siteGroups: $site.groups)
                }
            }

            Section {
                Button {
                    let group = EditableSite.Group(title: "New Group", shortcuts: [EditableSite.Shortcut()])
                    site.groups.append(group)
                    focus = group.shortcuts.first?.id
                } label: {
                    Label("Add Group", systemImage: "rectangle.stack.badge.plus")
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                TextField("Site name", text: $site.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Menu { actions() } label: { Image(systemName: "ellipsis.circle").font(.system(size: 15)) }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("More")
            }

            DomainsEditor(site: $site)

            LevelSummary(pack: site.pack)

            ForEach(site.issues + (saveError.map { [$0] } ?? []), id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Pieces

private struct DomainsEditor: View {
    @Binding var site: EditableSite
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shows on").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(site.match, id: \.self) { domain in
                    HStack(spacing: 4) {
                        Image(systemName: "globe").font(.caption2).foregroundStyle(.secondary)
                        Text(domain).font(.callout)
                        Button {
                            site.match.removeAll { $0 == domain }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove \(domain)")
                    }
                    .padding(.leading, 8).padding(.trailing, 5).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                TextField(site.match.isEmpty ? "Add a domain, e.g. github.com" : "Add domain", text: $draft)
                    .textFieldStyle(.plain)
                    .frame(width: site.match.isEmpty ? 220 : 120)
                    .padding(.vertical, 3)
                    .onSubmit(commit)
            }
            Text("Subdomains are included. Add a path to narrow it, e.g. google.com/maps.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onDisappear(perform: commit)
    }

    private func commit() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        site.addDomains(draft)
        draft = ""
    }
}

private struct LevelSummary: View {
    let pack: SitePack

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DetailLevel.allCases, id: \.self) { level in
                HStack(spacing: 4) {
                    Circle().fill(level.color).frame(width: 7, height: 7)
                    Text(level.title).foregroundStyle(.secondary)
                    Text("\(pack.count(at: level))").monospacedDigit()
                }
                .font(.caption)
                .help("\(pack.count(at: level)) shortcuts shown at \(level.title)")
                if level != .complete { Text("·").foregroundStyle(.tertiary) }
            }
        }
    }
}

private struct GroupHeader: View {
    @Binding var group: EditableSite.Group
    @Binding var siteGroups: [EditableSite.Group]

    private var index: Int? { siteGroups.firstIndex { $0.id == group.id } }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Group name", text: $group.title)
                .textFieldStyle(.plain)
                .font(.headline)
            Spacer()
            Text("\(group.shortcuts.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Menu {
                Section("Set level for all shortcuts") {
                    ForEach(DetailLevel.allCases, id: \.self) { level in
                        Button(level.title) { group.setAllLevels(level) }
                    }
                }
                Divider()
                Button("Move Up") { move(by: -1) }.disabled(index == 0)
                Button("Move Down") { move(by: 1) }.disabled(index == siteGroups.count - 1)
                Divider()
                Button("Delete Group", role: .destructive) { siteGroups.removeAll { $0.id == group.id } }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.top, 10)
    }

    private func move(by offset: Int) {
        guard let i = index, siteGroups.indices.contains(i + offset) else { return }
        siteGroups.swapAt(i, i + offset)
    }
}

private struct ShortcutRow: View {
    @Binding var shortcut: EditableSite.Shortcut
    let level: DetailLevel
    var focus: FocusState<UUID?>.Binding
    let onLevel: (DetailLevel) -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("What it does", text: $shortcut.title)
                .textFieldStyle(.plain)
                .focused(focus, equals: shortcut.id)
            KeyField(keys: $shortcut.keys)
            LevelPill(level: level, onSelect: onLevel)
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(hovering ? Color.red : Color.secondary.opacity(0.35))
            }
            .buttonStyle(.borderless)
            .help("Delete shortcut")
        }
        .padding(.vertical, 3)
        .onHover { hovering = $0 }
        .contextMenu {
            ForEach(DetailLevel.allCases, id: \.self) { l in Button("Show at \(l.title)") { onLevel(l) } }
            Divider()
            Button("Delete Shortcut", role: .destructive, action: onDelete)
        }
    }
}

private struct LevelPill: View {
    let level: DetailLevel
    let onSelect: (DetailLevel) -> Void

    var body: some View {
        Menu {
            ForEach(DetailLevel.allCases, id: \.self) { l in
                Button {
                    onSelect(l)
                } label: {
                    if l == level { Label("\(l.title) — \(l.hint)", systemImage: "checkmark") } else { Text("\(l.title) — \(l.hint)") }
                }
            }
        } label: {
            Text(level.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(level.color)
                .frame(width: 72)
                .padding(.vertical, 3)
                .background(level.color.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        // .button + .plain keeps the custom label's colors (borderless strips them).
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(width: 72)
        .help("Shown at \(level.title) and above")
    }
}

extension DetailLevel {
    var color: Color {
        switch self {
        case .core: return .green
        case .extended: return .blue
        case .complete: return .purple
        }
    }
}

/// Wraps children onto new lines, like text.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, point) in zip(subviews, result.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}
