import Foundation

/// A user's changes to a built-in pack, stored as `<pack>.edits.json` next to their own packs.
///
/// Only what differs from the built-in pack is stored, keyed by the `id` of each page, group
/// and shortcut, so a new version of the built-in pack can be merged with the user's changes:
/// everything the user didn't touch follows the built-in pack, and every change they made is
/// re-applied on top. The editor never edits this directly: it edits the merged pack, and
/// `diff(base:edited:)` rewrites the whole file on every save.
///
///     {
///       "updated": "2026-11-19",
///       "shortcuts": {
///         "repo.go-to-issues": { "keys": "g shift+i" },
///         "site.command-palette": { "deleted": true },
///         "s:Repository/Go to wiki": { "added": true, "group": "repository", "after": "repo.go-to-issues",
///                                      "title": "Go to wiki", "keys": "g w" }
///       },
///       "groups": { "notifications": { "level": "core" } }
///     }
///
/// Fields are overridden one at a time (changing a shortcut's keys leaves its title following
/// the built-in pack). Lists (`match`, a page's `paths`, a group's `pages`) are replaced whole.
/// Positions are relative: an item that was added or moved says which item it comes `after`
/// (or that it comes `first`), so items the built-in pack adds later land around it.
///
/// When both change the same field, the user's value wins. Changes to items the built-in pack
/// no longer has can't be applied; `apply` reports them and the next save drops them.
public struct SiteOverrides: Codable, Equatable, Sendable {
    /// The user deleted this built-in site.
    public var deleted: Bool?
    /// Last day the user changed this site, "YYYY-MM-DD". The merged pack shows the later of
    /// this and the built-in pack's date.
    public var updated: String?
    public var name: String?
    public var match: [String]?
    public var pages: [String: PageChange]?
    public var groups: [String: GroupChange]?
    public var shortcuts: [String: ShortcutChange]?

    public init(deleted: Bool? = nil, updated: String? = nil, name: String? = nil, match: [String]? = nil,
                pages: [String: PageChange]? = nil, groups: [String: GroupChange]? = nil,
                shortcuts: [String: ShortcutChange]? = nil) {
        self.deleted = deleted
        self.updated = updated
        self.name = name
        self.match = match
        self.pages = pages
        self.groups = groups
        self.shortcuts = shortcuts
    }

    /// A level override. `inherit` clears the level: a shortcut then takes its group's level,
    /// and a group counts as Core.
    public enum LevelSetting: String, Codable, Sendable {
        case core, extended, complete, inherit

        init(_ level: DetailLevel?) { self = level.map { LevelSetting(rawValue: $0.rawValue)! } ?? .inherit }
        var level: DetailLevel? { DetailLevel(rawValue: rawValue) }
    }

    public struct PageChange: Codable, Equatable, Sendable {
        public var added: Bool?
        public var deleted: Bool?
        public var name: String?
        public var paths: [String]?
        public var after: String?
        public var first: Bool?
        public init() {}
    }

    public struct GroupChange: Codable, Equatable, Sendable {
        public var added: Bool?
        public var deleted: Bool?
        public var title: String?
        public var level: LevelSetting?
        /// Page ids.
        public var pages: [String]?
        public var after: String?
        public var first: Bool?
        public init() {}
    }

    public struct ShortcutChange: Codable, Equatable, Sendable {
        public var added: Bool?
        public var deleted: Bool?
        public var title: String?
        public var keys: String?
        public var level: LevelSetting?
        /// Id of the group the shortcut is in, when it was added or moved to another group.
        public var group: String?
        public var after: String?
        public var first: Bool?
        public init() {}
    }

    /// True when there's nothing to store besides the date.
    public var isEmpty: Bool {
        deleted != true && name == nil && match == nil
            && (pages ?? [:]).isEmpty && (groups ?? [:]).isEmpty && (shortcuts ?? [:]).isEmpty
    }

    /// How many things are changed (each page, group or shortcut, the name and the domains).
    public var changeCount: Int {
        (name == nil ? 0 : 1) + (match == nil ? 0 : 1)
            + (pages?.count ?? 0) + (groups?.count ?? 0) + (shortcuts?.count ?? 0)
    }

    /// Ids of the shortcuts the user added or changed (not deleted), for marking rows in the editor.
    public var changedShortcutIDs: Set<String> {
        Set((shortcuts ?? [:]).filter { $0.value.deleted != true }.keys)
    }
}

// MARK: - Keyed form

/// A pack where every page, group and shortcut has a key: its `id`, or for items without one
/// (added by the user, or from an older pack) a key made from its titles.
private struct Keyed {
    struct Page { var key: String; var name: String; var paths: [String] }
    struct Shortcut { var key: String; var title: String; var keys: String; var level: DetailLevel? }
    struct Group { var key: String; var title: String; var level: DetailLevel?; var pageKeys: [String]; var shortcuts: [Shortcut] }

    var name: String
    var updated: String?
    var match: [String]
    var pages: [Page]
    var groups: [Group]

    init(_ pack: SitePack) {
        // Keys are unique per kind (a page and a group may share one).
        var used: [Character: Set<String>] = [:]
        func unique(_ key: String, _ kind: Character) -> String {
            var candidate = key, n = 2
            while used[kind, default: []].contains(candidate) { candidate = "\(key)#\(n)"; n += 1 }
            used[kind, default: []].insert(candidate)
            return candidate
        }
        name = pack.name
        updated = pack.updated
        match = pack.match
        pages = (pack.pages ?? []).map { Page(key: unique($0.id ?? "p:\($0.name)", "p"), name: $0.name, paths: $0.paths) }
        let pageKey = Dictionary(pages.map { ($0.name, $0.key) }, uniquingKeysWith: { a, _ in a })
        groups = pack.groups.map { g in
            Group(key: unique(g.id ?? "g:\(g.title)", "g"), title: g.title, level: g.level,
                  pageKeys: (g.pages ?? []).compactMap { pageKey[$0] },
                  shortcuts: g.shortcuts.map {
                      Shortcut(key: unique($0.id ?? "s:\(g.title)/\($0.title)", "s"), title: $0.title, keys: $0.keys, level: $0.level)
                  })
        }
    }

    var pack: SitePack {
        let pageName = Dictionary(pages.map { ($0.key, $0.name) }, uniquingKeysWith: { a, _ in a })
        return SitePack(
            name: name, updated: updated, match: match,
            pages: pages.map { SitePack.Page(id: $0.key, name: $0.name, paths: $0.paths) },
            groups: groups.map { g in
                SitePack.Group(id: g.key, title: g.title, level: g.level,
                               pages: g.pageKeys.compactMap { pageName[$0] },
                               shortcuts: g.shortcuts.map { SitePack.Entry(id: $0.key, title: $0.title, keys: $0.keys, level: $0.level) })
            })
    }
}

// MARK: - Positions

/// Where an added or moved item goes: after another item, or first.
private enum Position: Equatable {
    case first
    case after(String)

    init?(after: String?, first: Bool?) {
        if first == true { self = .first } else if let after { self = .after(after) } else { return nil }
    }
    var after: String? { if case .after(let key) = self { return key } else { return nil } }
    var first: Bool? { self == .first ? true : nil }
}

/// Positions needed to turn `base` order into `edited` order. Items that keep their order
/// relative to each other (the longest such run) need none; every other item, including ones
/// not in `base`, gets the item before it in `edited`.
private func positions(base: [String], edited: [String]) -> [String: Position] {
    let baseIndex = Dictionary(base.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    let common = edited.filter { baseIndex[$0] != nil }
    // Longest increasing subsequence of base indexes, O(n²) (lists are short).
    let idx = common.map { baseIndex[$0]! }
    var length = [Int](repeating: 1, count: idx.count), previous = [Int](repeating: -1, count: idx.count)
    for i in idx.indices {
        for j in 0..<i where idx[j] < idx[i] && length[j] + 1 > length[i] {
            length[i] = length[j] + 1
            previous[i] = j
        }
    }
    var anchored = Set<String>()
    var i = length.indices.max(by: { length[$0] < length[$1] }) ?? -1
    while i >= 0 { anchored.insert(common[i]); i = previous[i] }

    var out: [String: Position] = [:]
    for (n, key) in edited.enumerated() where !anchored.contains(key) {
        out[key] = n == 0 ? .first : .after(edited[n - 1])
    }
    return out
}

/// Inserts `items` (with their positions) into `list`. Items whose anchor never appears go at the end.
private func insert<T>(_ items: [(key: String, position: Position, value: T)], into list: inout [(key: String, value: T)]) {
    var pending = items.sorted { $0.key < $1.key }
    while !pending.isEmpty {
        let before = pending.count
        pending.removeAll { item in
            switch item.position {
            case .first:
                list.insert((item.key, item.value), at: 0)
                return true
            case .after(let anchor):
                guard let i = list.firstIndex(where: { $0.key == anchor }) else { return false }
                list.insert((item.key, item.value), at: i + 1)
                return true
            }
        }
        if pending.count == before {
            list.append(contentsOf: pending.map { ($0.key, $0.value) })
            return
        }
    }
}

// MARK: - Diff

extension SiteOverrides {
    /// The overrides that turn `base` into `edited`. `updated` is taken from `edited`.
    public static func diff(base basePack: SitePack, edited editedPack: SitePack) -> SiteOverrides {
        let base = Keyed(basePack), edited = Keyed(editedPack)
        var out = SiteOverrides(updated: editedPack.updated)
        if edited.name != base.name { out.name = edited.name }
        if edited.match != base.match { out.match = edited.match }

        // Pages
        var pages: [String: PageChange] = [:]
        let basePages = Dictionary(base.pages.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let editedPageKeys = Set(edited.pages.map(\.key))
        for p in base.pages where !editedPageKeys.contains(p.key) {
            var c = PageChange(); c.deleted = true; pages[p.key] = c
        }
        let pagePositions = positions(base: base.pages.map(\.key), edited: edited.pages.map(\.key))
        for p in edited.pages {
            var c = PageChange()
            if let b = basePages[p.key] {
                if p.name != b.name { c.name = p.name }
                if p.paths != b.paths { c.paths = p.paths }
            } else {
                c.added = true; c.name = p.name; c.paths = p.paths
            }
            if let pos = pagePositions[p.key] { c.after = pos.after; c.first = pos.first }
            if c != PageChange() { pages[p.key] = c }
        }

        // Groups
        var groups: [String: GroupChange] = [:]
        let baseGroups = Dictionary(base.groups.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let editedGroupKeys = Set(edited.groups.map(\.key))
        for g in base.groups where !editedGroupKeys.contains(g.key) {
            var c = GroupChange(); c.deleted = true; groups[g.key] = c
        }
        let groupPositions = positions(base: base.groups.map(\.key), edited: edited.groups.map(\.key))
        for g in edited.groups {
            var c = GroupChange()
            if let b = baseGroups[g.key] {
                if g.title != b.title { c.title = g.title }
                if g.level != b.level { c.level = LevelSetting(g.level) }
                if Set(g.pageKeys) != Set(b.pageKeys) { c.pages = g.pageKeys }
            } else {
                c.added = true; c.title = g.title
                if g.level != nil { c.level = LevelSetting(g.level) }
                if !g.pageKeys.isEmpty { c.pages = g.pageKeys }
            }
            if let pos = groupPositions[g.key] { c.after = pos.after; c.first = pos.first }
            if c != GroupChange() { groups[g.key] = c }
        }

        // Shortcuts
        var shortcuts: [String: ShortcutChange] = [:]
        var baseShortcut: [String: (group: String, value: Keyed.Shortcut)] = [:]
        for g in base.groups { for s in g.shortcuts { baseShortcut[s.key] = (g.key, s) } }
        var editedShortcutKeys = Set<String>()
        for g in edited.groups { for s in g.shortcuts { editedShortcutKeys.insert(s.key) } }
        for (key, b) in baseShortcut where !editedShortcutKeys.contains(key) && editedGroupKeys.contains(b.group) {
            var c = ShortcutChange(); c.deleted = true; shortcuts[key] = c
        }
        for g in edited.groups {
            let baseOrder = baseGroups[g.key]?.shortcuts.map(\.key) ?? []
            let order = positions(base: baseOrder, edited: g.shortcuts.map(\.key))
            for s in g.shortcuts {
                var c = ShortcutChange()
                if let b = baseShortcut[s.key] {
                    if s.title != b.value.title { c.title = s.title }
                    if s.keys != b.value.keys { c.keys = s.keys }
                    if s.level != b.value.level { c.level = LevelSetting(s.level) }
                    if b.group != g.key { c.group = g.key }
                } else {
                    c.added = true; c.group = g.key; c.title = s.title; c.keys = s.keys
                    if s.level != nil { c.level = LevelSetting(s.level) }
                }
                if let pos = order[s.key] { c.after = pos.after; c.first = pos.first }
                if c != ShortcutChange() { shortcuts[s.key] = c }
            }
        }

        out.pages = pages.isEmpty ? nil : pages
        out.groups = groups.isEmpty ? nil : groups
        out.shortcuts = shortcuts.isEmpty ? nil : shortcuts
        return out
    }
}

// MARK: - Apply

extension SiteOverrides {
    public struct Applied {
        public var pack: SitePack
        /// Changes that couldn't be applied because the built-in pack no longer has what they
        /// refer to, e.g. "shortcut repo.old-thing".
        public var unapplied: [String]
    }

    /// The built-in pack with these overrides applied. Every item in the result has an `id`.
    public func apply(to basePack: SitePack) -> Applied {
        var site = Keyed(basePack)
        var unapplied: [String] = []
        if let name { site.name = name }
        if let match { site.match = match }
        if let updated, updated > (site.updated ?? "") { site.updated = updated }

        // Pages
        let pageChanges = pages ?? [:]
        let basePageKeys = Set(site.pages.map(\.key))
        func changed(_ p: Keyed.Page, _ c: PageChange) -> Keyed.Page {
            var p = p
            if let name = c.name { p.name = name }
            if let paths = c.paths { p.paths = paths }
            return p
        }
        var pageList: [(key: String, value: Keyed.Page)] = []
        var positionedPages: [(key: String, position: Position, value: Keyed.Page)] = []
        for p in site.pages {
            guard let c = pageChanges[p.key] else { pageList.append((p.key, p)); continue }
            if c.deleted == true { continue }
            if let position = Position(after: c.after, first: c.first) {
                positionedPages.append((p.key, position, changed(p, c)))
            } else {
                pageList.append((p.key, changed(p, c)))
            }
        }
        for (key, c) in pageChanges where !basePageKeys.contains(key) {
            if c.added == true, c.deleted != true, let position = Position(after: c.after, first: c.first) {
                positionedPages.append((key, position, changed(Keyed.Page(key: key, name: "", paths: []), c)))
            } else {
                unapplied.append("page \(key)")
            }
        }
        insert(positionedPages, into: &pageList)
        site.pages = pageList.map(\.value)
        let livePages = Set(site.pages.map(\.key))

        // Groups (shortcuts are placed below, once every group exists)
        let groupChanges = groups ?? [:]
        let baseGroupKeys = Set(site.groups.map(\.key))
        func changed(_ g: Keyed.Group, _ c: GroupChange) -> Keyed.Group {
            var g = g
            if let title = c.title { g.title = title }
            if let level = c.level { g.level = level.level }
            if let pages = c.pages { g.pageKeys = pages }
            return g
        }
        var groupList: [(key: String, value: Keyed.Group)] = []
        var positionedGroups: [(key: String, position: Position, value: Keyed.Group)] = []
        for g in site.groups {
            guard let c = groupChanges[g.key] else { groupList.append((g.key, g)); continue }
            if c.deleted == true { continue }
            if let position = Position(after: c.after, first: c.first) {
                positionedGroups.append((g.key, position, changed(g, c)))
            } else {
                groupList.append((g.key, changed(g, c)))
            }
        }
        for (key, c) in groupChanges where !baseGroupKeys.contains(key) {
            if c.added == true, c.deleted != true, let position = Position(after: c.after, first: c.first) {
                positionedGroups.append((key, position,
                                         changed(Keyed.Group(key: key, title: "", level: nil, pageKeys: [], shortcuts: []), c)))
            } else {
                unapplied.append("group \(key)")
            }
        }
        insert(positionedGroups, into: &groupList)

        // Shortcuts
        let shortcutChanges = shortcuts ?? [:]
        func changed(_ s: Keyed.Shortcut, _ c: ShortcutChange) -> Keyed.Shortcut {
            var s = s
            if let title = c.title { s.title = title }
            if let keys = c.keys { s.keys = keys }
            if let level = c.level { s.level = level.level }
            return s
        }
        var baseShortcut: [String: Keyed.Shortcut] = [:]
        for g in site.groups { for s in g.shortcuts { baseShortcut[s.key] = s } }
        var positionedShortcuts: [String: [(key: String, position: Position, value: Keyed.Shortcut)]] = [:]
        let liveGroups = Set(groupList.map(\.key))
        for i in groupList.indices {
            var kept: [Keyed.Shortcut] = []
            for s in groupList[i].value.shortcuts {
                guard let c = shortcutChanges[s.key] else { kept.append(s); continue }
                if c.deleted == true { continue }
                if c.group == nil || c.group == groupList[i].key, Position(after: c.after, first: c.first) == nil {
                    kept.append(changed(s, c))
                }
                // Otherwise it's placed below, with the positioned shortcuts.
            }
            groupList[i].value.shortcuts = kept
        }
        for (key, c) in shortcutChanges where c.deleted != true {
            let base = baseShortcut[key]
            guard base != nil || c.added == true else { unapplied.append("shortcut \(key)"); continue }
            let position = Position(after: c.after, first: c.first)
            guard c.group != nil || position != nil else {
                if base == nil { unapplied.append("shortcut \(key)") }
                continue // changed in place, done above
            }
            // The group it's in: the one it moved to, else the one it's in in the built-in pack.
            let target = c.group ?? site.groups.first { $0.shortcuts.contains { $0.key == key } }?.key
            guard let target, liveGroups.contains(target) else { unapplied.append("shortcut \(key)"); continue }
            let value = changed(base ?? Keyed.Shortcut(key: key, title: "", keys: "", level: nil), c)
            // Moved without a position (only possible by hand): an anchor that never matches puts it last.
            positionedShortcuts[target, default: []].append((key, position ?? .after(""), value))
        }
        for (key, c) in shortcutChanges where c.deleted == true && baseShortcut[key] == nil { unapplied.append("shortcut \(key)") }
        for i in groupList.indices {
            guard let items = positionedShortcuts[groupList[i].key] else { continue }
            var list = groupList[i].value.shortcuts.map { (key: $0.key, value: $0) }
            insert(items, into: &list)
            groupList[i].value.shortcuts = list.map(\.value)
        }
        site.groups = groupList.map(\.value)
        for i in site.groups.indices { site.groups[i].pageKeys.removeAll { !livePages.contains($0) } }

        return Applied(pack: site.pack, unapplied: unapplied.sorted())
    }
}

extension SitePack {
    /// The pack without ids, for comparing content or exporting a standalone copy.
    public var withoutIDs: SitePack {
        var copy = self
        copy.pages = pages?.map { var p = $0; p.id = nil; return p }
        copy.groups = groups.map { g in
            var g = g
            g.id = nil
            g.shortcuts = g.shortcuts.map { var s = $0; s.id = nil; return s }
            return g
        }
        return copy
    }

    /// Fills in missing ids from `reference` by matching titles: pages by name, groups by
    /// title, shortcuts by group and title (or by title alone if it's unique in `reference`).
    /// Used to line up packs written before ids existed with the current built-in pack.
    public func adoptingIDs(from reference: SitePack) -> SitePack {
        var copy = self
        let pageIDs = Dictionary((reference.pages ?? []).compactMap { p in p.id.map { (p.name, $0) } }, uniquingKeysWith: { a, _ in a })
        let groupIDs = Dictionary(reference.groups.compactMap { g in g.id.map { (g.title, $0) } }, uniquingKeysWith: { a, _ in a })
        var byGroupAndTitle: [String: String] = [:], byTitle: [String: [String]] = [:]
        for g in reference.groups {
            for s in g.shortcuts {
                guard let id = s.id else { continue }
                byGroupAndTitle["\(g.title)\u{0}\(s.title)"] = id
                byTitle[s.title, default: []].append(id)
            }
        }
        copy.pages = pages?.map { var p = $0; if p.id == nil { p.id = pageIDs[p.name] }; return p }
        copy.groups = groups.map { g in
            var g = g
            if g.id == nil { g.id = groupIDs[g.title] }
            g.shortcuts = g.shortcuts.map { s in
                var s = s
                if s.id == nil {
                    s.id = byGroupAndTitle["\(g.title)\u{0}\(s.title)"] ?? byTitle[s.title].flatMap { $0.count == 1 ? $0[0] : nil }
                }
                return s
            }
            return g
        }
        return copy
    }
}
