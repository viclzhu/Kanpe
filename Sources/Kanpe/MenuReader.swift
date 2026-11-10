import ApplicationServices
import KanpeCore

/// Reads keyboard shortcuts from an app's menu bar via Accessibility.
enum MenuReader {
    private static let attrs = [
        kAXTitleAttribute as String,
        kAXMenuItemCmdCharAttribute as String,
        kAXMenuItemCmdVirtualKeyAttribute as String,
        kAXMenuItemCmdModifiersAttribute as String,
        kAXChildrenAttribute as String,
    ]

    /// Caps how many menu items we visit, so huge History/Bookmarks menus don't stall the panel.
    private static let itemBudgetPerMenu = 400
    private static let maxDepth = 3

    static func groups(pid: pid_t) -> [ShortcutGroup] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard let menuBar = AX.element(app, kAXMenuBarAttribute) else { return [] }

        var groups: [ShortcutGroup] = []
        // Index 0 is the Apple menu; it's the same everywhere, so skip it.
        for item in AX.children(menuBar).dropFirst() {
            let title = AX.string(item, kAXTitleAttribute) ?? ""
            guard !title.isEmpty, let menu = AX.children(item).first else { continue }
            var budget = itemBudgetPerMenu
            var shortcuts: [Shortcut] = []
            collect(menu: menu, path: [], depth: 0, budget: &budget, into: &shortcuts)
            if !shortcuts.isEmpty {
                groups.append(ShortcutGroup(title: title, shortcuts: dedupe(shortcuts), source: .app))
            }
        }
        return groups
    }

    private static func collect(menu: AXUIElement, path: [String], depth: Int, budget: inout Int, into out: inout [Shortcut]) {
        for item in AX.children(menu) {
            budget -= 1
            if budget <= 0 { return }

            let v = AX.values(item, attrs)
            let title = (v[0] as? String) ?? ""
            guard !title.isEmpty else { continue } // separators

            let children = (v[4] as? [AXUIElement]) ?? []
            if let submenu = children.first, depth < maxDepth {
                collect(menu: submenu, path: path + [title], depth: depth + 1, budget: &budget, into: &out)
                continue
            }

            let char = (v[1] as? String) ?? ""
            let key: String?
            if !char.isEmpty {
                key = MenuShortcutFormat.keyGlyph(forChar: char)
            } else if let code = (v[2] as? NSNumber)?.intValue {
                key = MenuShortcutFormat.keyGlyph(forVirtualKey: code)
            } else {
                key = nil
            }
            guard let key else { continue }
            let mods = (v[3] as? NSNumber)?.intValue ?? 0
            let fullTitle = (path + [title]).joined(separator: " › ")
            out.append(Shortcut(title: fullTitle, chord: MenuShortcutFormat.chord(modifiers: mods, key: key)))
        }
    }

    /// Menus often contain alternates (e.g. ⌥-variants) with the same title and keys.
    private static func dedupe(_ shortcuts: [Shortcut]) -> [Shortcut] {
        var seen = Set<Shortcut>()
        return shortcuts.filter { seen.insert($0).inserted }
    }
}
