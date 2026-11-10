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
/// optionally followed by a path prefix: "google.com/maps".
///
/// `level` ("core" | "extended" | "complete") is the lowest detail level at which a shortcut
/// appears. It can be set on a group (applies to all its shortcuts) and overridden per shortcut.
/// Untagged shortcuts are "core", so packs without levels always show everything.
public struct SitePack: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var title: String
        public var keys: String
        public var level: DetailLevel?
    }

    public struct Group: Codable, Hashable, Sendable {
        public var title: String
        public var level: DetailLevel?
        public var shortcuts: [Entry]

        func level(of entry: Entry) -> DetailLevel {
            entry.level ?? level ?? .core
        }
    }

    public var name: String
    public var match: [String]
    public var groups: [Group]

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
    /// groups that end up empty. Group titles are prefixed with the pack name so they stay
    /// distinguishable from app menu groups.
    public func displayGroups(level: DetailLevel = .complete) -> [ShortcutGroup] {
        let visible: [(Group, [Entry])] = groups.compactMap { group in
            let entries = group.shortcuts.filter { group.level(of: $0) <= level }
            return entries.isEmpty ? nil : (group, entries)
        }
        return visible.map { group, entries in
            ShortcutGroup(
                title: visible.count == 1 ? name : "\(name) · \(group.title)",
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

    public static func matches(pattern rawPattern: String, url: URL) -> Bool {
        guard let host = normalizedHost(url) else { return false }
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
}

public struct SitePackStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kanpe/Sites", isDirectory: true)
    }

    /// Installs bundled packs into the user's folder.
    ///
    /// New packs are copied. A pack that was installed before is replaced by the bundled
    /// version only if the user hasn't edited it (its content still matches what we installed,
    /// tracked in `.installed.json`). Edited packs are never overwritten.
    public func installDefaults(from bundledDirectory: URL?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let bundledDirectory,
              let files = try? fm.contentsOfDirectory(at: bundledDirectory, includingPropertiesForKeys: nil)
        else { return }

        var manifest = readManifest()

        for file in files where file.pathExtension == "json" {
            let name = file.lastPathComponent
            let target = directory.appendingPathComponent(name)
            let bundled = try Data(contentsOf: file)
            let bundledDigest = Self.digest(bundled)

            guard fm.fileExists(atPath: target.path) else {
                // Installed before and now missing: the user deleted it. Don't bring it back.
                if manifest[name] == nil {
                    try bundled.write(to: target, options: .atomic)
                    manifest[name] = bundledDigest
                }
                continue
            }
            if let existing = try? Data(contentsOf: target) {
                let existingDigest = Self.digest(existing)
                if existingDigest == bundledDigest {
                    manifest[name] = bundledDigest // already current
                    continue
                }
                guard manifest[name] == existingDigest else { continue } // user-edited (or unknown): keep
            }
            try bundled.write(to: target, options: .atomic)
            manifest[name] = bundledDigest
        }
        try writeManifest(manifest)
    }

    // MARK: Install manifest (tracks what we installed, to tell user edits apart)

    private var manifestURL: URL { directory.appendingPathComponent(".installed.json") }

    private func readManifest() -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifestURL))) ?? [:]
    }

    private func writeManifest(_ manifest: [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    // MARK: Editing

    /// Writes a pack as formatted JSON.
    public func save(_ pack: SitePack, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encode(pack).write(to: url, options: .atomic)
    }

    public static func encode(_ pack: SitePack) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(pack)
    }

    /// Deletes a pack file. Built-in packs stay deleted (see `installDefaults`).
    public func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    /// A file name for a new pack, derived from its name and not clashing with existing files.
    public func newFileURL(forName name: String) -> URL {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-").joined(separator: "-")
        let base = slug.isEmpty ? "site" : slug
        var candidate = directory.appendingPathComponent("\(base).json")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(n).json")
            n += 1
        }
        return candidate
    }

    /// The bundled pack with this file name, if there is one (i.e. the pack is built in).
    public func bundledPackURL(for fileURL: URL, in bundledDirectory: URL?) -> URL? {
        guard let url = bundledDirectory?.appendingPathComponent(fileURL.lastPathComponent),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Built-in packs the user has deleted.
    public func missingBundledPacks(in bundledDirectory: URL?) -> [URL] {
        guard let bundledDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: bundledDirectory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter {
            $0.pathExtension == "json" &&
                !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.lastPathComponent).path)
        }
    }

    /// Brings back deleted built-in packs. Returns how many were restored.
    @discardableResult
    public func restoreMissingBundledPacks(from bundledDirectory: URL?) throws -> Int {
        let missing = missingBundledPacks(in: bundledDirectory)
        for source in missing {
            try revertToBundled(directory.appendingPathComponent(source.lastPathComponent), from: bundledDirectory)
        }
        return missing.count
    }

    /// Replaces the user's copy with the bundled version (and marks it unedited, so future
    /// app updates apply to it again).
    public func revertToBundled(_ fileURL: URL, from bundledDirectory: URL?) throws {
        guard let source = bundledPackURL(for: fileURL, in: bundledDirectory) else { return }
        let data = try Data(contentsOf: source)
        try data.write(to: fileURL, options: .atomic)
        var manifest = readManifest()
        manifest[fileURL.lastPathComponent] = Self.digest(data)
        try writeManifest(manifest)
    }

    /// Stable content fingerprint (FNV-1a 64). Only used to detect edits, not for security.
    static func digest(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    public struct LoadedPack {
        public var fileURL: URL
        public var pack: SitePack
    }

    public struct LoadResult {
        public var loaded: [LoadedPack]
        public var errors: [(file: String, message: String)]
        public var packs: [SitePack] { loaded.map(\.pack) }
    }

    public func load() -> LoadResult {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [LoadedPack] = []
        var errors: [(String, String)] = []
        let decoder = JSONDecoder()
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
            do {
                let data = try Data(contentsOf: file)
                loaded.append(LoadedPack(fileURL: file, pack: try decoder.decode(SitePack.self, from: data)))
            } catch {
                errors.append((file.lastPathComponent, String(describing: error)))
            }
        }
        return LoadResult(loaded: loaded, errors: errors)
    }
}
