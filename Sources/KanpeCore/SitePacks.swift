import Foundation

/// How much of a site's cheat sheet to show. Each level includes the ones before it.
public enum DetailLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case core, extended, complete

    public var title: String {
        switch self {
        case .core: return "Core"
        case .extended: return "Extended"
        case .complete: return "Complete"
        }
    }

    /// What a site shows before the user picks a level: the short list.
    public static let `default`: DetailLevel = .core

    public static func < (a: DetailLevel, b: DetailLevel) -> Bool {
        allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
    }
}

/// A site pack as stored on disk (`*.json` in the Sites folder).
///
///     {
///       "name": "GitHub",
///       "match": ["github.com", "gist.github.com"],
///       "groups": [
///         { "title": "Navigation", "level": "extended",
///           "shortcuts": [ { "title": "Go to Issues", "keys": "g i", "level": "core" } ] }
///       ]
///     }
///
/// `match` entries are hosts (subdomains match too: "github.com" matches "www.github.com"),
/// optionally followed by a path prefix: "google.com/maps". An entry `app:<bundle id>`
/// ("app:com.t3tools.t3code") matches an app instead, for apps whose shortcuts aren't in their
/// menus (Electron apps, mostly). Pages only apply to URLs, so an app pack shows all its groups.
///
/// `level` ("core" | "extended" | "complete") is the lowest detail level at which a shortcut
/// appears. It can be set on a group (applies to all its shortcuts) and overridden per shortcut.
/// Untagged shortcuts are "core", so packs without levels always show everything.
///
/// `pages` (optional) name parts of the site by URL path, and a group's `pages` limits it to
/// those parts. Groups without `pages` show everywhere on the site:
///
///     "pages": [ { "name": "Issues", "paths": ["/*/*/issues", "/*/*/issues/**"] } ],
///     "groups": [ { "title": "Issues", "pages": ["Issues"], "shortcuts": [ … ] } ]
///
/// See `PathPattern` for the path syntax.
///
/// `updated` (optional, "YYYY-MM-DD") is when the shortcuts were last checked or changed. The
/// editor sets it to today on every edit. The panel shows it on hover, so stale packs are easy to spot.
public struct SitePack: Codable, Hashable, Sendable {
    /// A named part of a site, identified by URL path patterns.
    public struct Page: Codable, Hashable, Sendable {
        /// Stable identity for overrides (see `SiteOverrides`). Required in bundled packs.
        public var id: String?
        public var name: String
        public var paths: [String]

        public init(id: String? = nil, name: String, paths: [String]) {
            self.id = id
            self.name = name
            self.paths = paths
        }

        /// True if any positive pattern matches and no "!" pattern does.
        public func matches(path: String) -> Bool {
            var included = false
            for raw in paths {
                let p = raw.trimmingCharacters(in: .whitespaces)
                if p.hasPrefix("!") {
                    if PathPattern.matches(String(p.dropFirst()), path: path) { return false }
                } else if !included, PathPattern.matches(p, path: path) {
                    included = true
                }
            }
            return included
        }
    }

    public struct Entry: Codable, Hashable, Sendable {
        public var id: String?
        public var title: String
        public var keys: String
        public var level: DetailLevel?

        public init(id: String? = nil, title: String, keys: String, level: DetailLevel? = nil) {
            self.id = id
            self.title = title
            self.keys = keys
            self.level = level
        }
    }

    public struct Group: Codable, Hashable, Sendable {
        public var id: String?
        public var title: String
        public var level: DetailLevel?
        /// Names of the pages this group belongs to. `nil` or empty: every page of the site.
        public var pages: [String]?
        public var shortcuts: [Entry]

        public init(id: String? = nil, title: String, level: DetailLevel? = nil, pages: [String]? = nil,
                    shortcuts: [Entry]) {
            self.id = id
            self.title = title
            self.level = level
            self.pages = pages?.isEmpty == true ? nil : pages
            self.shortcuts = shortcuts
        }

        var isPageSpecific: Bool { !(pages ?? []).isEmpty }

        func level(of entry: Entry) -> DetailLevel {
            entry.level ?? level ?? .core
        }
    }

    public var name: String
    /// Day the shortcuts were last updated, "YYYY-MM-DD" (see `PackDate`).
    public var updated: String?
    public var match: [String]
    public var pages: [Page]?
    public var groups: [Group]

    public init(name: String, updated: String? = nil, match: [String], pages: [Page]? = nil, groups: [Group]) {
        self.name = name
        self.updated = updated
        self.match = match
        self.pages = pages?.isEmpty == true ? nil : pages
        self.groups = groups
    }

    /// Whether any group is limited to particular pages (so page filtering changes anything).
    public var hasPageSpecificGroups: Bool { groups.contains(where: \.isPageSpecific) }

    /// Names of the pages `url` is on, in pack order.
    public func pages(for url: URL) -> [String] {
        let path = url.path.isEmpty ? "/" : url.path
        return (pages ?? []).filter { $0.matches(path: path) }.map(\.name)
    }

    /// Levels that actually change what's shown. Empty when the pack isn't tagged with
    /// levels (or uses only one), in which case there's nothing to choose between.
    public var availableLevels: [DetailLevel] {
        let used = Set(groups.flatMap { g in g.shortcuts.map(g.level(of:)) })
        return used.count > 1 ? DetailLevel.allCases : []
    }

    /// Number of shortcuts shown at `level`.
    public func count(at level: DetailLevel) -> Int {
        groups.reduce(0) { sum, g in sum + g.shortcuts.filter { g.level(of: $0) <= level }.count }
    }

    /// Converts to display groups, keeping only shortcuts at or below `level` and dropping
    /// groups that end up empty. With `prefixed`, group titles start with the pack name, which
    /// tells sites apart when more than one matches the tab. A lone group is titled with the
    /// pack name either way.
    ///
    /// With `pages` (the pages the current URL is on), page-specific groups show only on their
    /// pages, and come first since they're the most relevant. With `nil`, every group shows.
    public func displayGroups(level: DetailLevel = .complete, pages current: [String]? = nil,
                              prefixed: Bool = true) -> [ShortcutGroup] {
        var ordered = groups
        if let current {
            let here = Set(current)
            ordered = groups.filter { $0.isPageSpecific && !here.isDisjoint(with: $0.pages ?? []) }
                + groups.filter { !$0.isPageSpecific }
        }
        let visible: [(Group, [Entry])] = ordered.compactMap { group in
            let entries = group.shortcuts.filter { group.level(of: $0) <= level }
            return entries.isEmpty ? nil : (group, entries)
        }
        return visible.map { group, entries in
            ShortcutGroup(
                title: visible.count == 1 ? name : prefixed ? "\(name) · \(group.title)" : group.title,
                shortcuts: entries.map { Shortcut(title: $0.title, alternatives: KeyNotation.parseAlternatives($0.keys)) },
                source: .site
            )
        }
    }
}

public enum SiteMatcher {
    /// Lowercased host without a leading "www.".
    public static func normalizedHost(_ url: URL) -> String? {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Prefix of `match` entries that name an app by bundle id.
    public static let appPrefix = "app:"

    /// The bundle id in an `app:` entry, or nil for a host entry.
    public static func appBundleID(inPattern rawPattern: String) -> String? {
        let pattern = rawPattern.trimmingCharacters(in: .whitespaces)
        guard pattern.lowercased().hasPrefix(appPrefix) else { return nil }
        let id = pattern.dropFirst(appPrefix.count).trimmingCharacters(in: .whitespaces)
        return id.isEmpty ? nil : id
    }

    public static func matches(pattern: String, bundleID: String) -> Bool {
        appBundleID(inPattern: pattern)?.caseInsensitiveCompare(bundleID) == .orderedSame
    }

    public static func matches(pattern rawPattern: String, url: URL) -> Bool {
        guard let host = normalizedHost(url), appBundleID(inPattern: rawPattern) == nil else { return false }
        var pattern = rawPattern.lowercased().trimmingCharacters(in: .whitespaces)
        for scheme in ["https://", "http://"] where pattern.hasPrefix(scheme) {
            pattern.removeFirst(scheme.count)
        }

        let patternHost: Substring
        let patternPath: Substring?
        if let slash = pattern.firstIndex(of: "/") {
            patternHost = pattern[..<slash]
            patternPath = pattern[slash...]
        } else {
            patternHost = pattern[...]
            patternPath = nil
        }
        var hostPattern = String(patternHost)
        if hostPattern.hasPrefix("www.") { hostPattern.removeFirst(4) }
        if hostPattern.hasPrefix("*.") { hostPattern.removeFirst(2) }
        guard !hostPattern.isEmpty else { return false }

        let hostMatches = host == hostPattern || host.hasSuffix("." + hostPattern)
        guard hostMatches else { return false }

        if let patternPath, patternPath != "/" {
            let path = url.path.lowercased()
            let prefix = patternPath.hasSuffix("/") ? String(patternPath.dropLast()) : String(patternPath)
            return path == prefix || path.hasPrefix(prefix + "/")
        }
        return true
    }

    public static func packs(for url: URL, in packs: [SitePack]) -> [SitePack] {
        packs.filter { pack in pack.match.contains { matches(pattern: $0, url: url) } }
    }

    /// Packs for the front app: those naming it with `app:`, then those matching its tab's URL.
    public static func packs(forApp bundleID: String?, url: URL?, in packs: [SitePack]) -> [SitePack] {
        packs.filter { pack in
            pack.match.contains { pattern in
                (bundleID.map { matches(pattern: pattern, bundleID: $0) } ?? false)
                    || (url.map { matches(pattern: pattern, url: $0) } ?? false)
            }
        }
    }
}

/// URL path patterns for site pages. Matching is by path segment and ignores case and a
/// trailing slash; the query and fragment are ignored.
///
/// - `*` matches exactly one segment: `/*/*` is "/owner/repo".
/// - `**` matches any number of segments, including none: `/*/*/issues/**` is the issue list
///   and every page under it.
/// - Within a segment, `*` is a wildcard: `/*/*/pull*` matches "pull" and "pulls".
/// - `{a,b}` matches either: `/{issues,pulls}` matches "/issues" and "/pulls".
/// - In a page's list, a leading `!` excludes: `!/{settings,orgs}/**`.
public enum PathPattern {
    public static func matches(_ pattern: String, path: String) -> Bool {
        let p = segments(pattern)
        let s = segments(path)
        return match(p[...], s[...])
    }

    static func segments(_ path: String) -> [String] {
        path.lowercased().split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func match(_ p: ArraySlice<String>, _ s: ArraySlice<String>) -> Bool {
        guard let first = p.first else { return s.isEmpty }
        if first == "**" {
            // Zero segments, or consume one and stay on "**".
            return match(p.dropFirst(), s) || (!s.isEmpty && match(p, s.dropFirst()))
        }
        guard let segment = s.first, segmentMatches(first, segment) else { return false }
        return match(p.dropFirst(), s.dropFirst())
    }

    /// Glob within one segment: `*` matches any run of characters; `{a,b}` is either.
    private static func segmentMatches(_ pattern: String, _ segment: String) -> Bool {
        if pattern == "*" { return true }
        if let open = pattern.firstIndex(of: "{"), let close = pattern[open...].firstIndex(of: "}") {
            let head = pattern[..<open], tail = pattern[pattern.index(after: close)...]
            return pattern[pattern.index(after: open)..<close].split(separator: ",", omittingEmptySubsequences: false)
                .contains { segmentMatches(String(head) + $0 + tail, segment) }
        }
        guard pattern.contains("*") else { return pattern == segment }
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var rest = segment[...]
        for (i, part) in parts.enumerated() {
            if i == 0 {
                guard rest.hasPrefix(part) else { return false }
                rest = rest.dropFirst(part.count)
            } else if i == parts.count - 1 {
                return part.isEmpty || rest.hasSuffix(part)
            } else if !part.isEmpty {
                guard let r = rest.range(of: part) else { return false }
                rest = rest[r.upperBound...]
            }
        }
        return rest.isEmpty
    }
}

/// Where packs live and how edits are stored.
///
/// - **Built-in packs** are read straight from the app (`bundledDirectory`). The user's changes
///   to one are stored as `<name>.edits.json` in `directory` (see `SiteOverrides`) and applied
///   when packs load, so updates to the built-in pack and the user's changes are merged.
/// - **The user's own packs** are complete `*.json` files in `directory`. One with the same
///   file name as a built-in pack replaces it entirely.
public struct SitePackStore {
    public let directory: URL
    public let bundledDirectory: URL?

    public init(directory: URL, bundledDirectory: URL? = nil) {
        self.directory = directory
        self.bundledDirectory = bundledDirectory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kanpe/Sites", isDirectory: true)
    }

    static let editsSuffix = ".edits.json"

    // MARK: Loading

    public struct LoadedPack {
        /// The user's file for their own packs; the bundled file for built-in packs.
        public var fileURL: URL
        public var pack: SitePack
        /// The file's modification date, used when the pack has no `updated` date.
        public var modified: Date?
        public var isBuiltIn: Bool
        /// Built-in packs: the user has changes stored for it.
        public var isCustomized: Bool
        /// Built-in packs: changes that no longer apply (see `SiteOverrides.Applied`).
        public var unapplied: [String]

        public init(fileURL: URL, pack: SitePack, modified: Date? = nil, isBuiltIn: Bool = false,
                    isCustomized: Bool = false, unapplied: [String] = []) {
            self.fileURL = fileURL
            self.pack = pack
            self.modified = modified
            self.isBuiltIn = isBuiltIn
            self.isCustomized = isCustomized
            self.unapplied = unapplied
        }

        /// When the shortcuts were last updated: the pack's `updated` day, else the file's date.
        public var updatedDate: Date? { pack.updated.flatMap { PackDate.parse($0) } ?? modified }
    }

    public struct LoadResult {
        public var loaded: [LoadedPack]
        public var errors: [(file: String, message: String)]
        public var packs: [SitePack] { loaded.map(\.pack) }
    }

    public func load() -> LoadResult {
        var loaded: [LoadedPack] = []
        var errors: [(String, String)] = []
        let userFiles = Self.packFiles(in: directory)
        for file in userFiles {
            do {
                loaded.append(LoadedPack(fileURL: file, pack: try Self.decode(file), modified: Self.modified(file)))
            } catch {
                errors.append((file.lastPathComponent, String(describing: error)))
            }
        }
        let shadowed = Set(userFiles.map(\.lastPathComponent))
        for file in bundledFiles() where !shadowed.contains(file.lastPathComponent) {
            do {
                let base = try Self.decode(file)
                let overrides = try readOverrides(for: file)
                if overrides?.deleted == true { continue }
                let applied = overrides?.apply(to: base)
                loaded.append(LoadedPack(fileURL: file, pack: applied?.pack ?? base, modified: Self.modified(file),
                                         isBuiltIn: true, isCustomized: overrides.map { !$0.isEmpty } ?? false,
                                         unapplied: applied?.unapplied ?? []))
            } catch {
                errors.append((editsURL(for: file).lastPathComponent, String(describing: error)))
            }
        }
        loaded.sort { $0.fileURL.lastPathComponent < $1.fileURL.lastPathComponent }
        return LoadResult(loaded: loaded, errors: errors)
    }

    /// `*.json` packs in a folder (not hidden files, not edits files).
    static func packFiles(in folder: URL?) -> [URL] {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasSuffix(editsSuffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func bundledFiles() -> [URL] { Self.packFiles(in: bundledDirectory) }

    static func decode(_ url: URL) throws -> SitePack {
        try JSONDecoder().decode(SitePack.self, from: Data(contentsOf: url))
    }

    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    // MARK: Built-in packs and their overrides

    /// True if `url` is a built-in pack (as returned in `LoadedPack.fileURL`).
    public func isBuiltIn(_ url: URL) -> Bool {
        guard let bundledDirectory else { return false }
        return url.deletingLastPathComponent().standardizedFileURL == bundledDirectory.standardizedFileURL
    }

    /// Where the user's changes to a built-in pack are stored.
    public func editsURL(for builtIn: URL) -> URL {
        directory.appendingPathComponent(builtIn.deletingPathExtension().lastPathComponent + Self.editsSuffix)
    }

    public func readOverrides(for builtIn: URL) throws -> SiteOverrides? {
        let url = editsURL(for: builtIn)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SiteOverrides.self, from: Data(contentsOf: url))
    }

    /// Writes the overrides, or removes the file when there's nothing left to store.
    public func writeOverrides(_ overrides: SiteOverrides, for builtIn: URL) throws {
        let url = editsURL(for: builtIn)
        if overrides.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(overrides).write(to: url, options: .atomic)
    }

    // MARK: Editing

    /// Saves a pack. For a built-in pack only the differences from it are written.
    public func save(_ pack: SitePack, to url: URL) throws {
        if isBuiltIn(url) {
            var overrides = SiteOverrides.diff(base: try Self.decode(url), edited: pack)
            overrides.deleted = try readOverrides(for: url)?.deleted
            try writeOverrides(overrides, for: url)
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encode(pack).write(to: url, options: .atomic)
        }
    }

    public static func encode(_ pack: SitePack) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(pack)
    }

    /// Deletes a pack. A built-in pack is only marked deleted (keeping the user's changes), so
    /// `restoreDeletedBuiltIns` can bring it back.
    public func delete(_ url: URL) throws {
        if isBuiltIn(url) {
            var overrides = try readOverrides(for: url) ?? SiteOverrides()
            overrides.deleted = true
            try writeOverrides(overrides, for: url)
        } else {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Drops every change to a built-in pack.
    public func revertToBuiltIn(_ url: URL) throws {
        try writeOverrides(SiteOverrides(), for: url)
    }

    /// Built-in packs the user has deleted.
    public func deletedBuiltIns() -> [URL] {
        bundledFiles().filter { (try? readOverrides(for: $0))??.deleted == true }
    }

    /// Brings back deleted built-in packs, with any changes the user had made. Returns how many.
    @discardableResult
    public func restoreDeletedBuiltIns() throws -> Int {
        let deleted = deletedBuiltIns()
        for url in deleted {
            var overrides = try readOverrides(for: url) ?? SiteOverrides()
            overrides.deleted = nil
            try writeOverrides(overrides, for: url)
        }
        return deleted.count
    }

    /// A file name for a new pack, derived from its name and not clashing with existing files
    /// or built-in packs (which it would replace).
    public func newFileURL(forName name: String) -> URL {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
        let base = slug.isEmpty ? "site" : slug
        let builtIn = Set(bundledFiles().map(\.lastPathComponent))
        func taken(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path) || builtIn.contains(url.lastPathComponent)
        }
        var candidate = directory.appendingPathComponent("\(base).json")
        var n = 2
        while taken(candidate) {
            candidate = directory.appendingPathComponent("\(base)-\(n).json")
            n += 1
        }
        return candidate
    }

    // MARK: Migrating from full copies (Kanpe 0.2.1 and earlier)

    /// Older versions copied built-in packs into `directory` and tracked them in
    /// `.installed.json` (file name → digest of the copy they installed). This turns those
    /// copies into overrides: unedited copies are removed, deleted ones are marked deleted,
    /// and edited ones become the user's changes, worked out against the version they started
    /// from so updates since then still arrive. Edited copies are moved to `Backups/`. Runs
    /// once: the manifest is removed afterwards.
    ///
    /// `legacyDirectory` holds earlier versions of the bundled packs, named `<name>-<digest>.json`.
    /// The starting version is the one closest to the user's copy (fewest changes), preferring
    /// the one the manifest names: a copy may have been updated by hand without the manifest.
    ///
    /// Returns the names of packs whose edits were converted.
    @discardableResult
    public func migrateLegacyCopies(legacyDirectory: URL?) throws -> [String] {
        let fm = FileManager.default
        let manifestURL = directory.appendingPathComponent(".installed.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode([String: String].self, from: manifestData)
        else { return [] }

        let legacyFiles = Self.packFiles(in: legacyDirectory)

        var converted: [String] = []
        for builtIn in bundledFiles() {
            let name = builtIn.lastPathComponent
            guard let installedDigest = manifest[name] else { continue } // never installed: any file is the user's own
            let copy = directory.appendingPathComponent(name)
            guard fm.fileExists(atPath: copy.path) else {
                try delete(builtIn) // the user deleted it
                continue
            }
            let data = try Data(contentsOf: copy)
            let digest = Self.digest(data)
            let bundledDigest = Self.digest(try Data(contentsOf: builtIn))
            if digest == installedDigest || digest == bundledDigest {
                try fm.removeItem(at: copy) // an unedited copy
                continue
            }
            guard let edited = try? JSONDecoder().decode(SitePack.self, from: data) else { continue } // unreadable: leave it
            let current = try Self.decode(builtIn)
            let stem = builtIn.deletingPathExtension().lastPathComponent
            var candidates: [(pack: SitePack, preferred: Bool)] = [(current, false)]
            for file in legacyFiles where file.lastPathComponent.hasPrefix(stem + "-") {
                guard let data = try? Data(contentsOf: file),
                      let pack = try? JSONDecoder().decode(SitePack.self, from: data) else { continue }
                candidates.append((pack, Self.digest(data) == installedDigest))
            }
            let mine = edited.adoptingIDs(from: current)
            let diffs = candidates.map { c in
                (overrides: SiteOverrides.diff(base: c.pack.adoptingIDs(from: current), edited: mine), preferred: c.preferred)
            }
            var overrides = diffs.min { a, b in
                (a.overrides.changeCount, a.preferred ? 0 : 1) < (b.overrides.changeCount, b.preferred ? 0 : 1)
            }!.overrides
            overrides.updated = Self.modified(copy).map { PackDate.string(from: $0) }
            let backups = directory.appendingPathComponent("Backups", isDirectory: true)
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            let backup = backups.appendingPathComponent(name)
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.moveItem(at: copy, to: backup)
            try writeOverrides(overrides, for: builtIn)
            converted.append(name)
        }
        try fm.removeItem(at: manifestURL)
        return converted
    }

    /// Stable content fingerprint (FNV-1a 64), as used by `.installed.json`. Not for security.
    public static func digest(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// The `updated` day of a pack ("YYYY-MM-DD", in the user's time zone) and how to describe it.
public enum PackDate {
    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func parse(_ text: String, calendar: Calendar = .current) -> Date? {
        formatter(calendar).date(from: text.trimmingCharacters(in: .whitespaces))
    }

    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar).string(from: date)
    }

    /// "today", "yesterday", "3 days ago", "2 weeks ago", "5 months ago", "over a year ago".
    public static func age(of date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s") ago" }
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<14: return plural(days, "day")
        case 14..<60: return plural(days / 7, "week")
        case 60..<365: return plural(days / 30, "month")
        default:
            let years = days / 365
            return years == 1 ? "over a year ago" : "over \(years) years ago"
        }
    }
}
