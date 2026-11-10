import Foundation

/// One row in the panel: a title and the keys to press.
/// `alternatives` holds one or more equivalent key sequences ("← or →"); each sequence is
/// the chords to press in order ("G then I"). Chords are display-ready, e.g. "⇧⌘K".
public struct Shortcut: Hashable, Sendable {
    public var title: String
    public var alternatives: [[String]]

    public init(title: String, alternatives: [[String]]) {
        self.title = title
        self.alternatives = alternatives
    }

    public init(title: String, chord: String) {
        self.init(title: title, alternatives: [[chord]])
    }
}

public struct ShortcutGroup: Hashable, Sendable, Identifiable {
    public var id: String { "\(source.rawValue)|\(title)" }
    public enum Source: String, Sendable { case site, app }

    public var title: String
    public var shortcuts: [Shortcut]
    public var source: Source

    public init(title: String, shortcuts: [Shortcut], source: Source) {
        self.title = title
        self.shortcuts = shortcuts
        self.source = source
    }
}

/// Everything the panel shows for one activation.
public struct PanelContent: Sendable {
    public var appName: String
    public var bundleID: String?
    /// Host of the active browser tab, if the frontmost app is a browser and the URL could be read.
    public var host: String?
    /// Names of the site packs that matched `host`.
    public var matchedSites: [String]
    public var groups: [ShortcutGroup]

    public init(appName: String, bundleID: String?, host: String?, matchedSites: [String], groups: [ShortcutGroup]) {
        self.appName = appName
        self.bundleID = bundleID
        self.host = host
        self.matchedSites = matchedSites
        self.groups = groups
    }
}
