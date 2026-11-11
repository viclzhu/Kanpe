import Foundation

/// Sorts an app's menu shortcuts into Core / Extended / Complete. Menus carry no notion of
/// importance, so this goes by what the shortcut is and how it's typed:
///
/// - **Core:** the essentials most people use every day: a short list of well-known commands
///   (New Tab, Reopen Closed Tab, Back…) plus the universal ⌘C/⌘V/⌘Z-style chords, which
///   catches them in any app and any language.
/// - **Extended:** other ⌘ shortcuts with at most one extra modifier (⇧⌘ or ⌥⌘), at most one
///   submenu deep.
/// - **Complete:** everything else: three-modifier chords, shortcuts without ⌘ (window tiling
///   on ⌃, fn/dictation keys) and items nested two or more submenus deep.
public enum MenuLevels {
    /// What an app's menus show before the user picks a level. Menus are long and generic, so
    /// the default trims them without hiding the everyday ⇧⌘ / ⌥⌘ shortcuts.
    public static let `default`: DetailLevel = .extended

    /// Chords that mean the same thing in nearly every Mac app.
    static let coreChords: Set<String> = [
        "⌘N", "⌘S", "⌘W", "⌘Q", "⌘,",
        "⌘Z", "⇧⌘Z", "⌘X", "⌘C", "⌘V", "⌘A", "⌘F",
    ]

    /// Menu item titles (last path component, lowercased, without "…") that are essentials
    /// even when their chord isn't universal. Mostly browsers, since that's where Kanpe is used most.
    static let coreTitles: Set<String> = [
        // Tabs & windows
        "new tab", "new window", "new private window", "new incognito window", "new inprivate window",
        "reopen closed tab", "reopen last closed tab", "close tab", "close window",
        "select next tab", "select previous tab", "show next tab", "show previous tab",
        // Navigation
        "open location", "back", "forward", "reload this page", "reload page", "reload",
        "find", "bookmark this tab", "bookmark this page", "add bookmark",
        // App
        "settings", "preferences", "save", "new", "undo", "redo", "cut", "copy", "paste", "select all",
    ]

    public static func level(of shortcut: Shortcut) -> DetailLevel {
        let path = shortcut.title.components(separatedBy: " › ")
        let name = normalized(path.last ?? shortcut.title)
        let chords = shortcut.alternatives.flatMap { $0 }
        if chords.contains(where: coreChords.contains) || coreTitles.contains(name) {
            return .core
        }
        let simple = chords.contains { chord in
            let mods = modifiers(of: chord)
            return mods.contains("⌘") && mods.count <= 2
        }
        return simple && path.count <= 2 ? .extended : .complete
    }

    /// The groups with only shortcuts at or below `level`; groups left empty are dropped.
    public static func filter(_ groups: [ShortcutGroup], level: DetailLevel) -> [ShortcutGroup] {
        groups.compactMap { group in
            var g = group
            g.shortcuts = group.shortcuts.filter { Self.level(of: $0) <= level }
            return g.shortcuts.isEmpty ? nil : g
        }
    }

    /// Number of shortcuts shown at `level`.
    public static func count(_ groups: [ShortcutGroup], at level: DetailLevel) -> Int {
        groups.reduce(0) { $0 + $1.shortcuts.filter { Self.level(of: $0) <= level }.count }
    }

    /// All levels when they'd show different things, otherwise none (nothing to choose).
    public static func availableLevels(_ groups: [ShortcutGroup]) -> [DetailLevel] {
        let used = Set(groups.flatMap { $0.shortcuts.map(level(of:)) })
        return used.count > 1 ? DetailLevel.allCases : []
    }

    /// The modifier glyphs at the start of a display chord ("⌥⇧⌘V" → ["⌥", "⇧", "⌘"]).
    static func modifiers(of chord: String) -> [Character] {
        Array(chord.prefix { "⌃⌥⇧⌘".contains($0) })
    }

    private static func normalized(_ title: String) -> String {
        var t = title.lowercased().trimmingCharacters(in: .whitespaces)
        while t.hasSuffix("…") || t.hasSuffix(".") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
