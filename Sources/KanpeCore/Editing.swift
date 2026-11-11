import Foundation

/// Editor-friendly copy of a `SitePack`: every group and shortcut has a stable identity so
/// lists can be edited, reordered and deleted without confusing the UI.
public struct EditableSite: Identifiable, Hashable, Sendable {
    public struct Shortcut: Identifiable, Hashable, Sendable {
        public var id = UUID()
        public var title: String
        public var keys: String
        /// Explicit level. `nil` means "inherit from the group".
        public var level: DetailLevel?

        public init(title: String = "", keys: String = "", level: DetailLevel? = nil) {
            self.title = title
            self.keys = keys
            self.level = level
        }
    }

    /// A named part of the site, matched by URL path patterns (see `PathPattern`).
    public struct Page: Identifiable, Hashable, Sendable {
        public var id = UUID()
        public var name: String
        public var paths: [String]

        public init(name: String = "", paths: [String] = []) {
            self.name = name
            self.paths = paths
        }

        /// Adds patterns typed by the user (comma/space separated). Accepts full URLs or
        /// "github.com/…" by dropping the scheme and host, and adds a missing leading "/".
        @discardableResult
        public mutating func addPaths(_ text: String) -> Bool {
            var added = false
            for raw in text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" }) {
                guard let path = Self.normalize(String(raw)), !paths.contains(path) else { continue }
                paths.append(path)
                added = true
            }
            return added
        }

        static func normalize(_ raw: String) -> String? {
            var p = raw.trimmingCharacters(in: .whitespaces)
            let negated = p.hasPrefix("!")
            if negated { p.removeFirst() }
            for scheme in ["https://", "http://"] where p.lowercased().hasPrefix(scheme) { p.removeFirst(scheme.count) }
            if let q = p.firstIndex(where: { $0 == "?" || $0 == "#" }) { p = String(p[..<q]) }
            // "github.com/owner/repo": a first segment with a dot is a host.
            if !p.hasPrefix("/"), let first = p.split(separator: "/").first, first.contains(".") {
                p = String(p.dropFirst(first.count))
            }
            if !p.hasPrefix("/") { p = "/" + p }
            while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
            if p == "/" && negated { return nil }
            return (negated ? "!" : "") + p
        }
    }

    public struct Group: Identifiable, Hashable, Sendable {
        public var id = UUID()
        public var title: String
        public var level: DetailLevel?
        /// Pages this group is limited to. Empty: every page.
        public var pageIDs: [Page.ID]
        public var shortcuts: [Shortcut]

        public init(title: String, level: DetailLevel? = nil, pageIDs: [Page.ID] = [], shortcuts: [Shortcut] = []) {
            self.title = title
            self.level = level
            self.pageIDs = pageIDs
            self.shortcuts = shortcuts
        }

        public func effectiveLevel(of shortcut: Shortcut) -> DetailLevel {
            shortcut.level ?? level ?? .core
        }

        /// Sets every shortcut in the group to `level` (stored once, on the group).
        public mutating func setAllLevels(_ level: DetailLevel) {
            self.level = level
            for i in shortcuts.indices { shortcuts[i].level = nil }
        }

        /// Sets one shortcut's level, storing it only if it differs from the group's.
        public mutating func setLevel(_ level: DetailLevel, forShortcutAt index: Int) {
            shortcuts[index].level = level == (self.level ?? .core) ? nil : level
        }
    }

    public var id = UUID()
    /// File backing this site. `nil` until first saved.
    public var fileURL: URL?
    public var name: String
    public var match: [String]
    public var pages: [Page]
    public var groups: [Group]

    public init(fileURL: URL? = nil, name: String, match: [String], pages: [Page] = [], groups: [Group]) {
        self.fileURL = fileURL
        self.name = name
        self.match = match
        self.pages = pages
        self.groups = groups
    }

    public init(_ pack: SitePack, fileURL: URL?) {
        var pages = (pack.pages ?? []).map { Page(name: $0.name, paths: $0.paths) }
        // A group may name a page that isn't defined; keep it as an empty page so the link
        // isn't silently lost (the editor flags pages without paths).
        for name in pack.groups.flatMap({ $0.pages ?? [] }) where !pages.contains(where: { $0.name == name }) {
            pages.append(Page(name: name))
        }
        func ids(_ names: [String]?) -> [Page.ID] {
            (names ?? []).compactMap { name in pages.first { $0.name == name }?.id }
        }
        self.init(
            fileURL: fileURL,
            name: pack.name,
            match: pack.match,
            pages: pages,
            groups: pack.groups.map { g in
                Group(title: g.title, level: g.level, pageIDs: ids(g.pages),
                      shortcuts: g.shortcuts.map { Shortcut(title: $0.title, keys: $0.keys, level: $0.level) })
            }
        )
    }

    /// Names of the pages a group is limited to, in page order.
    public func pageNames(of group: Group) -> [String] {
        pages.filter { group.pageIDs.contains($0.id) }.map(\.name)
    }

    /// Removes a page and unlinks it from groups (which then show on every page, unless they
    /// still belong to another page).
    public mutating func deletePage(_ id: Page.ID) {
        pages.removeAll { $0.id == id }
        for i in groups.indices { groups[i].pageIDs.removeAll { $0 == id } }
    }

    /// Names of the pages `url` is on, using the current (unsaved) edits.
    public func pages(for url: URL) -> [String] { pack.pages(for: url) }

    /// A blank site to start from.
    public static func blank(name: String = "New Site") -> EditableSite {
        EditableSite(name: name, match: [], groups: [Group(title: "General", shortcuts: [Shortcut()])])
    }

    /// Converts back for saving. Fully empty rows (no title and no keys) are dropped, so a
    /// freshly added row that was never filled in doesn't end up in the file.
    public var pack: SitePack {
        SitePack(
            name: name.trimmingCharacters(in: .whitespaces),
            match: match,
            pages: pages.map { SitePack.Page(name: $0.name.trimmingCharacters(in: .whitespaces), paths: $0.paths) },
            groups: groups.map { g in
                SitePack.Group(
                    title: g.title,
                    level: g.level,
                    pages: pageNames(of: g).map { $0.trimmingCharacters(in: .whitespaces) },
                    shortcuts: g.shortcuts
                        .filter { !($0.title.trimmingCharacters(in: .whitespaces).isEmpty && $0.keys.trimmingCharacters(in: .whitespaces).isEmpty) }
                        .map { SitePack.Entry(title: $0.title, keys: $0.keys.trimmingCharacters(in: .whitespaces), level: $0.level) }
                )
            }
        )
    }

    /// Adds domains typed by the user (comma/space separated), skipping duplicates.
    /// Returns false if nothing usable was entered.
    @discardableResult
    public mutating func addDomains(_ text: String) -> Bool {
        let new = text
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .map { d -> String in
                var d = d
                for scheme in ["https://", "http://"] where d.hasPrefix(scheme) { d.removeFirst(scheme.count) }
                while d.hasSuffix("/") { d.removeLast() }
                return d
            }
        var added = false
        for domain in new where !domain.isEmpty && !match.contains(domain) {
            match.append(domain)
            added = true
        }
        return added
    }

    /// Problems worth pointing out in the editor (the site still saves).
    public var issues: [String] {
        var out: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Give this site a name.") }
        if match.isEmpty { out.append("Add at least one domain, or this site will never appear.") }
        let missingKeys = groups.flatMap(\.shortcuts).filter {
            !$0.title.trimmingCharacters(in: .whitespaces).isEmpty && $0.keys.trimmingCharacters(in: .whitespaces).isEmpty
        }.count
        for page in pages {
            let name = page.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty {
                out.append("A page has no name.")
            } else if page.paths.allSatisfy({ $0.hasPrefix("!") }) {
                out.append("Page \u{201C}\(name)\u{201D} has no paths, so its groups never show.")
            }
        }
        let names = pages.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        if Set(names).count < names.count { out.append("Two pages have the same name.") }
        if missingKeys > 0 { out.append("\(missingKeys) shortcut\(missingKeys == 1 ? " has" : "s have") no keys yet.") }
        return out
    }
}

/// Converts a recorded key press into pack notation ("shift+cmd+p", "?", "enter").
public enum KeyRecording {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    private static let namedKeyCodes: [UInt16: String] = [
        36: "enter", 76: "enter", 48: "tab", 49: "space", 51: "delete", 117: "fwddelete", 53: "esc",
        123: "left", 124: "right", 125: "down", 126: "up",
        115: "home", 119: "end", 116: "pageup", 121: "pagedown",
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
        98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
    ]

    /// - Parameters:
    ///   - characters: `charactersIgnoringModifiers` from the key event (Shift is still applied,
    ///     so Shift+/ arrives as "?").
    public static func notation(keyCode: UInt16, characters: String?, modifiers: Modifiers) -> String? {
        var mods = modifiers
        let key: String
        if let named = namedKeyCodes[keyCode] {
            key = named
        } else if let chars = characters, chars.count == 1, let c = chars.first {
            if c == "+" {
                key = "plus"
            } else if c.isLetter {
                key = String(c).lowercased()
            } else {
                key = String(c)
                // Shift already produced this symbol ("?" from Shift+/), so don't also list it.
                if mods.contains(.shift) && !c.isNumber { mods.remove(.shift) }
            }
        } else {
            return nil
        }

        var parts: [String] = []
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("opt") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }
}
