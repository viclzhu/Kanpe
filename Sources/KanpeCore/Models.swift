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
    public var id: String { "\(source.rawValue)|\(title)|\(part)" }
    public enum Source: String, Sendable { case site, app }

    public var title: String
    public var shortcuts: [Shortcut]
    public var source: Source
    /// 0 for a whole group or its first piece; 1, 2… when a long group continues in another column.
    public var part: Int

    public init(title: String, shortcuts: [Shortcut], source: Source, part: Int = 0) {
        self.title = title
        self.shortcuts = shortcuts
        self.source = source
        self.part = part
    }
}

/// Everything the panel shows for one activation.
public struct PanelContent: Sendable {
    public var appName: String
    public var bundleID: String?
    /// Host of the active browser tab, if the frontmost app is a browser and the URL could be read.
    public var host: String?
    /// Site packs that matched `host`, with the detail level each is shown at.
    public var sites: [SiteInfo]
    public var groups: [ShortcutGroup]
    /// Whether the app's own menu shortcuts are included in `groups`, and how many there are.
    /// `nil` when the app has none (nothing to toggle).
    public var appMenus: AppMenus?

    public struct AppMenus: Sendable {
        public var visible: Bool
        public var count: Int
        public init(visible: Bool, count: Int) {
            self.visible = visible
            self.count = count
        }
    }

    public init(appName: String, bundleID: String?, host: String?, sites: [SiteInfo], groups: [ShortcutGroup],
                appMenus: AppMenus? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.host = host
        self.sites = sites
        self.groups = groups
        self.appMenus = appMenus
    }
}

public struct SiteInfo: Hashable, Sendable {
    public var name: String
    public var level: DetailLevel
    /// Empty if the pack has no levels to choose between.
    public var availableLevels: [DetailLevel]
    /// Pages of the site the current URL is on (e.g. ["Repository", "Code"]).
    public var pages: [String]
    /// Whether only the current page's shortcuts are shown. `nil` when the pack has no
    /// page-specific groups (nothing to toggle).
    public var pageFiltering: Bool?

    public init(name: String, level: DetailLevel, availableLevels: [DetailLevel],
                pages: [String] = [], pageFiltering: Bool? = nil) {
        self.name = name
        self.level = level
        self.availableLevels = availableLevels
        self.pages = pages
        self.pageFiltering = pageFiltering
    }
}
