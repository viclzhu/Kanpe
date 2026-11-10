import Foundation

/// A site pack as stored on disk (`*.json` in the Sites folder).
///
///     {
///       "name": "GitHub",
///       "match": ["github.com", "gist.github.com"],
///       "groups": [
///         { "title": "Navigation", "shortcuts": [ { "title": "Go to Issues", "keys": "g i" } ] }
///       ]
///     }
///
/// `match` entries are hosts (subdomains match too: "github.com" matches "www.github.com"),
/// optionally followed by a path prefix: "google.com/maps".
public struct SitePack: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var title: String
        public var keys: String
    }

    public struct Group: Codable, Hashable, Sendable {
        public var title: String
        public var shortcuts: [Entry]
    }

    public var name: String
    public var match: [String]
    public var groups: [Group]

    /// Converts to display groups. Group titles are prefixed with the pack name
    /// so they stay distinguishable from app menu groups.
    public func displayGroups() -> [ShortcutGroup] {
        groups.map { group in
            ShortcutGroup(
                title: groups.count == 1 ? name : "\(name) · \(group.title)",
                shortcuts: group.shortcuts.map { Shortcut(title: $0.title, alternatives: KeyNotation.parseAlternatives($0.keys)) },
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

    /// Copies bundled packs into the user's folder if a file with the same name is not there yet.
    /// Existing (possibly user-edited) files are never overwritten.
    public func installDefaults(from bundledDirectory: URL?) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let bundledDirectory,
              let files = try? fm.contentsOfDirectory(at: bundledDirectory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "json" {
            let target = directory.appendingPathComponent(file.lastPathComponent)
            if !fm.fileExists(atPath: target.path) {
                try fm.copyItem(at: file, to: target)
            }
        }
    }

    public struct LoadResult {
        public var packs: [SitePack]
        public var errors: [(file: String, message: String)]
    }

    public func load() -> LoadResult {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var packs: [SitePack] = []
        var errors: [(String, String)] = []
        let decoder = JSONDecoder()
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                packs.append(try decoder.decode(SitePack.self, from: data))
            } catch {
                errors.append((file.lastPathComponent, String(describing: error)))
            }
        }
        return LoadResult(packs: packs, errors: errors)
    }
}
