import Foundation
import KanpeCore

var failures = 0
func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: Int = #line) {
    if actual != expected {
        failures += 1
        print("FAIL [line \(line)] \(label): expected \(expected), got \(actual)")
    }
}

// MARK: Key notation
check(KeyNotation.parse("g i"), ["G", "I"], "sequence")
check(KeyNotation.parse("cmd+k"), ["⌘K"], "cmd chord")
check(KeyNotation.parse("shift+cmd+p"), ["⇧⌘P"], "modifier order")
check(KeyNotation.parse("cmd+shift+p"), ["⇧⌘P"], "modifier order normalised")
check(KeyNotation.parse("ctrl+opt+enter"), ["⌃⌥↩"], "named key")
check(KeyNotation.parse("?"), ["?"], "symbol")
check(KeyNotation.parse("+"), ["+"], "bare plus")
check(KeyNotation.parse("cmd++"), ["⌘+"], "cmd plus")
check(KeyNotation.parse("cmd+plus"), ["⌘+"], "plus by name")
check(KeyNotation.parse("shift+/"), ["⇧/"], "shift slash")
check(KeyNotation.parse("f5"), ["F5"], "function key")
check(KeyNotation.parse("space"), ["Space"], "space")
check(KeyNotation.parse("left"), ["←"], "arrow")
check(KeyNotation.parseAlternatives("left or right"), [["←"], ["→"]], "alternatives")
check(KeyNotation.parseAlternatives("g i or cmd+k"), [["G", "I"], ["⌘K"]], "sequence alternative")
check(KeyNotation.parseAlternatives("/"), [["/"]], "slash is a key, not a separator")

// MARK: Menu formatting
check(MenuShortcutFormat.modifierGlyphs(0), "⌘", "cmd only")
check(MenuShortcutFormat.modifierGlyphs(1), "⇧⌘", "shift cmd")
check(MenuShortcutFormat.modifierGlyphs(2 | 4), "⌃⌥⌘", "ctrl opt cmd")
check(MenuShortcutFormat.modifierGlyphs(8 | 4), "⌃", "ctrl, no cmd")
check(MenuShortcutFormat.keyGlyph(forChar: "\u{F700}"), "↑", "up arrow char")
check(MenuShortcutFormat.keyGlyph(forChar: "\u{F704}"), "F1", "F1 char")
check(MenuShortcutFormat.keyGlyph(forChar: "n"), "N", "letter")
check(MenuShortcutFormat.keyGlyph(forVirtualKey: 0x35), "⎋", "escape vkey")
check(MenuShortcutFormat.chord(modifiers: 8, key: "F"), "fn F", "globe/fn shortcut")
check(MenuShortcutFormat.chord(modifiers: 8, key: "⌫"), "⌫", "bare special key stays bare")
check(MenuShortcutFormat.chord(modifiers: 1, key: "T"), "⇧⌘T", "normal chord")

// MARK: Site matching
let gh = URL(string: "https://github.com/anze/keyclucask/issues")!
check(SiteMatcher.matches(pattern: "github.com", url: gh), true, "host")
check(SiteMatcher.matches(pattern: "github.com", url: URL(string: "https://www.github.com/")!), true, "www stripped")
check(SiteMatcher.matches(pattern: "github.com", url: URL(string: "https://gist.github.com/x")!), true, "subdomain")
check(SiteMatcher.matches(pattern: "github.com", url: URL(string: "https://notgithub.com/")!), false, "not a suffix trick")
check(SiteMatcher.matches(pattern: "github.com", url: URL(string: "https://github.com.evil.io/")!), false, "not a prefix trick")
check(SiteMatcher.matches(pattern: "https://GitHub.com", url: gh), true, "scheme + case")
check(SiteMatcher.matches(pattern: "*.google.com", url: URL(string: "https://mail.google.com/mail/u/0")!), true, "wildcard")
check(SiteMatcher.matches(pattern: "google.com/maps", url: URL(string: "https://www.google.com/maps/place/x")!), true, "path prefix")
check(SiteMatcher.matches(pattern: "google.com/maps", url: URL(string: "https://www.google.com/mapsearch")!), false, "path boundary")
check(SiteMatcher.matches(pattern: "google.com/maps", url: URL(string: "https://www.google.com/search")!), false, "path mismatch")
check(SiteMatcher.matches(pattern: "github.com", url: URL(string: "about:blank")!), false, "no host")
check(SiteMatcher.normalizedHost(gh), "github.com", "normalized host")
check(SiteMatcher.matches(pattern: "app:com.t3tools.t3code", bundleID: "com.t3tools.T3Code"), true, "app pattern, any case")
check(SiteMatcher.matches(pattern: "app:com.t3tools.t3code", bundleID: "com.t3tools.t3code.helper"), false, "app pattern is exact")
check(SiteMatcher.matches(pattern: "github.com", bundleID: "github.com"), false, "host pattern never matches an app")
check(SiteMatcher.matches(pattern: "app:com.github", url: URL(string: "https://com.github/")!), false, "app pattern never matches a URL")
check(SiteMatcher.matches(pattern: "app:", bundleID: ""), false, "empty app pattern")

// MARK: Layout
func g(_ title: String, _ rows: Int, _ source: ShortcutGroup.Source = .app) -> ShortcutGroup {
    ShortcutGroup(title: title, shortcuts: (0..<rows).map { Shortcut(title: "\(title)\($0)", chord: "X") }, source: source)
}
func rowsInOrder(_ cols: [[ShortcutGroup]]) -> [String] { cols.flatMap { $0.flatMap { $0.shortcuts.map(\.title) } } }
let sample = [g("A", 10), g("B", 10), g("C", 10), g("D", 10)]
let flowed2 = ColumnLayout.flow(sample, columns: 2)
check(flowed2.count, 2, "two columns")
check(flowed2.map(ColumnLayout.height), [24, 24], "balanced heights")
check(rowsInOrder(flowed2), rowsInOrder([sample]), "every row kept, in order")

// A single long group is split across columns, marked as continued, with no tiny pieces.
let long = ColumnLayout.flow([g("Edit", 40)], columns: 3)
check(long.count, 3, "long group spread over 3 columns")
check(long.flatMap { $0.map(\.part) }, [0, 1, 2], "continuation parts numbered")
check(long.allSatisfy { $0.allSatisfy { $0.shortcuts.count >= ColumnLayout.minChunk } }, true, "no piece below minChunk")
check(rowsInOrder(long), rowsInOrder([[g("Edit", 40)]]), "split keeps row order")
check(Set(long.flatMap { $0.map(\.id) }).count, 3, "continuation pieces have unique ids")

// Short groups move whole instead of splitting.
let shortGroups = ColumnLayout.flow([g("A", 8), g("B", 8), g("C", 8)], columns: 2)
check(shortGroups.flatMap { $0.map(\.part) }, [0, 0, 0], "short groups are never split")
check(rowsInOrder(shortGroups), rowsInOrder([[g("A", 8), g("B", 8), g("C", 8)]]), "short groups keep order")

// Splits never leave a stranded row.
for rows in 1...30 {
    for n in 1...4 {
        let cols = ColumnLayout.flow([g("P", 5), g("Q", rows), g("R", 4)], columns: n)
        let pieces = cols.flatMap { $0 }
        let tiny = pieces.filter { $0.shortcuts.count < ColumnLayout.minChunk && $0.part > 0 }
        if cols.count > n || !tiny.isEmpty || rowsInOrder(cols) != rowsInOrder([[g("P", 5), g("Q", rows), g("R", 4)]]) {
            failures += 1
            print("FAIL flow rows=\(rows) n=\(n): \(cols.map { $0.map { "\($0.title)#\($0.part):\($0.shortcuts.count)" } })")
        }
    }
}

// Choosing a shape: 26 rows of site shortcuts should not be one tall column on a wide screen.
let screenMetrics = ColumnLayout.Metrics(columnWidth: 270, columnSpacing: 18, rowHeight: 20.5, chromeHeight: 90,
                                         chromeWidth: 36, headerWidth: 600, maxWidth: 1700, maxHeight: 950)
let github = [g("Site-wide", 5, .site), g("Repository", 8, .site), g("Code", 5, .site), g("Issues", 8, .site)]
let chosen = ColumnLayout.best(github, metrics: screenMetrics, targetAspect: 1700.0 / 950.0)
check(chosen.count >= 2, true, "small sheet uses several columns (got \(chosen.count))")

// A few page-specific groups: a gap-free row of cards beats a better-shaped panel with a hole.
let pageMetrics = ColumnLayout.Metrics(columnWidth: 270, columnSpacing: 18, rowHeight: 20.5, chromeHeight: 78,
                                       chromeWidth: 36, headerWidth: 700, maxWidth: 1420, maxHeight: 830)
let pageGroups = [g("Repository", 4, .site), g("Issues & PRs", 3, .site), g("Site-wide", 3, .site)]
check(ColumnLayout.best(pageGroups, metrics: pageMetrics, targetAspect: 1420.0 / 830.0).count, 3,
      "small page sheet: one group per column")
// Big sheets still follow the screen's shape rather than becoming one long strip.
let menuSheet = (0..<12).map { g("Menu \($0)", 8) }
let menuCols = ColumnLayout.best(menuSheet, metrics: pageMetrics, targetAspect: 1420.0 / 830.0)
check((2...4).contains(menuCols.count), true, "big sheet uses a screen-shaped column count (got \(menuCols.count))")
check(pageMetrics.columnWidth(for: 1), 270 * ColumnLayout.Metrics.maxStretch, "one column widens up to maxStretch")
check(pageMetrics.columnWidth(for: 4), 270, "columns never narrower than the base width")
// A big sheet must fit the height limit by using more columns.
let big = (0..<12).map { g("M\($0)", 14) }
let bigCols = ColumnLayout.best(big, metrics: screenMetrics, targetAspect: 1700.0 / 950.0)
let bigHeight = Double(bigCols.map(ColumnLayout.height).max()!) * 20.5 + 90
check(bigHeight <= 950, true, "big sheet fits height (\(bigHeight))")
check(ColumnLayout.best([], metrics: screenMetrics, targetAspect: 1.6).count, 0, "empty")

// MARK: Trigger gestures
func run(_ mode: TriggerMode, _ events: [TriggerStateMachine.Event]) -> [TriggerStateMachine.Effect] {
    var m = TriggerStateMachine(mode: mode, holdDelay: 0.6)
    return events.flatMap { m.handle($0) }
}
typealias E = TriggerStateMachine.Event

// Hold ⌘
check(run(.hold, [.commandDown(0), .timerFired]), [.begin, .scheduleShow(after: 0.6), .show], "hold shows")
check(run(.hold, [.commandDown(0), .timerFired, .commandUp(2)]), [.begin, .scheduleShow(after: 0.6), .show, .hide], "release hides")
check(run(.hold, [.commandDown(0), .otherInput, .timerFired]), [.begin, .scheduleShow(after: 0.6), .cancelScheduledShow], "⌘C cancels")
check(run(.hold, [.commandDown(0), .commandUp(0.2), .timerFired]), [.begin, .scheduleShow(after: 0.6), .cancelScheduledShow], "early release cancels")
check(run(.hold, [.commandDown(0), .timerFired, .otherInput]), [.begin, .scheduleShow(after: 0.6), .show, .hide], "key while shown hides")

// Press ⌘ twice and hold
let armed: [TriggerStateMachine.Effect] = [.begin, .scheduleShow(after: 0.15)]
check(run(.doubleTapHold, [.commandDown(0), .commandUp(0.1), .commandDown(0.25), .timerFired]), armed + [.show], "double tap + hold shows")
check(run(.doubleTapHold, [.commandDown(0), .timerFired]), [], "single hold does nothing")
check(run(.doubleTapHold, [.commandDown(0), .commandUp(0.1), .commandDown(0.25), .commandUp(0.3), .timerFired]),
      armed + [.cancelScheduledShow], "double tap without hold does nothing")
check(run(.doubleTapHold, [.commandDown(0), .commandUp(0.5), .commandDown(0.6), .timerFired]), [], "first press too long")
check(run(.doubleTapHold, [.commandDown(0), .commandUp(0.1), .commandDown(1.0), .timerFired]), [], "gap too long")
check(run(.doubleTapHold, [.commandDown(0), .commandUp(0.1), .commandDown(1.0), .commandUp(1.1), .commandDown(1.3), .timerFired]),
      armed + [.show], "slow press restarts as a new first tap")
check(run(.doubleTapHold, [.commandDown(0), .otherInput, .commandDown(0.2), .timerFired]), [], "⌘C then ⌘ is not a double tap")
check(run(.doubleTapHold, [.commandDown(0), .commandUp(0.1), .otherInput, .commandDown(0.2), .timerFired]), [], "key between taps cancels")
check(run(.doubleTapHold, [.commandDown(0), .commandUp(0.1), .commandDown(0.25), .timerFired, .commandUp(3)]), armed + [.show, .hide], "release hides")

// MARK: Detail levels
let leveledJSON = """
{ "name": "Demo", "match": ["demo.test"], "groups": [
  { "title": "A", "shortcuts": [
    { "title": "a-core", "keys": "a" },
    { "title": "a-ext", "keys": "b", "level": "extended" },
    { "title": "a-all", "keys": "c", "level": "complete" } ] },
  { "title": "B", "level": "complete", "shortcuts": [
    { "title": "b-inherits", "keys": "d" },
    { "title": "b-override", "keys": "e", "level": "core" } ] },
  { "title": "C", "level": "extended", "shortcuts": [ { "title": "c-ext", "keys": "f" } ] } ] }
"""
let demo = try! JSONDecoder().decode(SitePack.self, from: Data(leveledJSON.utf8))
func titles(_ level: DetailLevel) -> [String] { demo.displayGroups(level: level).flatMap { $0.shortcuts.map(\.title) } }
check(titles(.core), ["a-core", "b-override"], "core shows untagged + core overrides")
check(titles(.extended), ["a-core", "a-ext", "b-override", "c-ext"], "extended includes core")
check(titles(.complete), ["a-core", "a-ext", "a-all", "b-inherits", "b-override", "c-ext"], "complete shows all")
check(demo.displayGroups(level: .core).map(\.title), ["Demo · A", "Demo · B"], "empty groups dropped")
check(demo.availableLevels, DetailLevel.allCases, "leveled pack offers levels")
check([demo.count(at: .core), demo.count(at: .extended), demo.count(at: .complete)], [2, 4, 6], "counts per level")
let flat = try! JSONDecoder().decode(SitePack.self, from: Data(#"{"name":"F","match":["f.test"],"groups":[{"title":"G","shortcuts":[{"title":"x","keys":"x"}]}]}"#.utf8))
check(flat.availableLevels, [], "untagged pack has no level choice")
check(flat.displayGroups(level: .core).flatMap(\.shortcuts).count, 1, "untagged pack shows everything at Core")
check(DetailLevel.core < DetailLevel.extended && DetailLevel.extended < DetailLevel.complete, true, "level order")

// MARK: Overrides: the user's changes to a built-in pack, merged with updates to it
do {
    func pack(_ json: String) -> SitePack { try! JSONDecoder().decode(SitePack.self, from: Data(json.utf8)) }
    let base = pack("""
    { "name": "Hub", "updated": "2026-11-01", "match": ["hub.test"],
      "pages": [ { "id": "repo", "name": "Repo", "paths": ["/*/*/**"] },
                 { "id": "issues", "name": "Issues", "paths": ["/*/*/issues"] } ],
      "groups": [
        { "id": "site", "title": "Site", "shortcuts": [
            { "id": "site.search", "title": "Search", "keys": "/" },
            { "id": "site.palette", "title": "Palette", "keys": "cmd+k" },
            { "id": "site.help", "title": "Help", "keys": "?" } ] },
        { "id": "repo", "title": "Repo", "level": "extended", "pages": ["Repo"], "shortcuts": [
            { "id": "repo.code", "title": "Code", "keys": "g c" },
            { "id": "repo.issues", "title": "Issues", "keys": "g i" } ] },
        { "id": "issues", "title": "Issues", "pages": ["Issues"], "shortcuts": [
            { "id": "issues.label", "title": "Label", "keys": "l" } ] } ] }
    """)

    check(SiteOverrides.diff(base: base, edited: base).isEmpty, true, "no edits: nothing stored")
    check(SiteOverrides().apply(to: base).pack.withoutIDs, base.withoutIDs, "no overrides: the built-in pack")

    // Edit the way the editor does: through EditableSite.
    var site = EditableSite(base, fileURL: nil)
    site.updated = "2026-11-19"
    site.match.append("www.hub.test")
    site.groups[0].shortcuts[0].keys = "s"                                   // change keys
    site.groups[0].shortcuts.remove(at: 1)                                   // delete Palette
    site.groups[1].shortcuts.insert(.init(title: "Wiki", keys: "g w"), at: 1) // add after Code
    site.groups[1].setLevel(.core, forShortcutAt: 2)                         // Issues: extended → core
    let label = site.groups[2].shortcuts.removeFirst()
    site.groups[0].shortcuts.append(label)                                   // move Label to Site
    site.pages[1].name = "Issue list"                                        // rename a page
    site.groups.insert(site.groups.remove(at: 2), at: 0)                     // Issues group first
    site.groups.append(.init(title: "Mine", shortcuts: [.init(title: "Mine 1", keys: "m")]))
    let edited = site.pack

    let overrides = SiteOverrides.diff(base: base, edited: edited)
    check(overrides.shortcuts?["site.search"], { var c = SiteOverrides.ShortcutChange(); c.keys = "s"; return c }(),
          "only the changed field is stored")
    check(overrides.shortcuts?["site.palette"]?.deleted, true, "deletion stored")
    check(overrides.shortcuts?["repo.issues"]?.level, .core, "level stored")
    check(overrides.shortcuts?["issues.label"]?.group, "site", "move to another group stored")
    check(overrides.shortcuts?["repo.code"], nil, "untouched shortcut not stored")
    check(overrides.groups?["site"], nil, "group whose shortcuts changed isn't itself stored")
    check(overrides.pages?["issues"]?.name, "Issue list", "page rename stored")
    check(overrides.match, ["hub.test", "www.hub.test"], "domains stored")
    check(overrides.groups?.values.filter { $0.after != nil || $0.first == true }.count, 2,
          "reordering stores only the moved group and the added one")

    let applied = overrides.apply(to: base)
    check(applied.pack.withoutIDs, { var e = edited.withoutIDs; e.updated = "2026-11-19"; return e }(),
          "apply(diff) gives back the edited pack")
    check(applied.unapplied, [], "everything applies to the pack it was made from")
    check(applied.pack.groups.first { $0.title == "Issues" }?.pages, ["Issue list"], "group follows renamed page")
    let reloaded = EditableSite(applied.pack, fileURL: nil).pack
    check(SiteOverrides.diff(base: base, edited: reloaded), overrides, "saving again without edits stores the same")

    let json = try! JSONEncoder().encode(overrides)
    check(try! JSONDecoder().decode(SiteOverrides.self, from: json), overrides, "overrides round-trip through JSON")
    var inherit = EditableSite(base, fileURL: nil)
    inherit.groups[1].level = nil
    check(SiteOverrides.diff(base: base, edited: inherit.pack).groups?["repo"]?.level, .inherit, "clearing a level is stored as inherit")
    check(SiteOverrides.diff(base: base, edited: inherit.pack).apply(to: base).pack.groups[1].level, nil, "inherit clears it")

    // A new built-in version arrives: the user's changes are re-applied on top of it.
    var upstream = base
    upstream.updated = "2026-12-01"
    upstream.groups[0].shortcuts[0].title = "Focus search"                   // the user changed its keys, not its title
    upstream.groups[1].shortcuts[0].keys = "g shift+c"                       // untouched by the user
    upstream.groups[0].shortcuts.append(.init(id: "site.dash", title: "Dashboard", keys: "g d"))
    upstream.groups[1].shortcuts.removeAll { $0.id == "repo.issues" }        // the user changed its level
    let merged = overrides.apply(to: upstream)
    let m = merged.pack
    func sc(_ id: String) -> SitePack.Entry? { m.groups.flatMap(\.shortcuts).first { $0.id == id } }
    check(sc("site.search").map { [$0.title, $0.keys] }, ["Focus search", "s"], "built-in title change + user keys change")
    check(sc("repo.code")?.keys, "g shift+c", "built-in change to an untouched shortcut arrives")
    check(sc("site.dash") != nil, true, "built-in addition arrives")
    check(sc("site.palette"), nil, "user deletion stays deleted")
    check(m.groups.first { $0.id == "repo" }?.shortcuts.map(\.title), ["Code", "Wiki"], "user addition kept in place")
    check(m.groups.first { $0.id == "site" }?.shortcuts.map(\.title), ["Focus search", "Help", "Label", "Dashboard"],
          "moved shortcut keeps its place; built-in addition lands at the end")
    check(m.groups.map(\.title), ["Issues", "Site", "Repo", "Mine"], "group order kept")
    check(m.updated, "2026-12-01", "later of the two dates")
    check(merged.unapplied, ["shortcut repo.issues"], "change to a shortcut the built-in pack removed is reported")
}

// MARK: Store: built-in packs, the user's changes, and their own packs
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("kanpe-store-\(UUID().uuidString)")
    let bundled = root.appendingPathComponent("bundled"), user = root.appendingPathComponent("user")
    try! fm.createDirectory(at: bundled, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    var demoWithIDs = demo
    for g in demoWithIDs.groups.indices {
        demoWithIDs.groups[g].id = "g\(g)"
        for s in demoWithIDs.groups[g].shortcuts.indices { demoWithIDs.groups[g].shortcuts[s].id = "g\(g).s\(s)" }
    }
    try! SitePackStore.encode(demoWithIDs).write(to: bundled.appendingPathComponent("demo.json"))
    let store = SitePackStore(directory: user, bundledDirectory: bundled)
    func only() -> SitePackStore.LoadedPack? { let l = store.load(); return l.loaded.count == 1 ? l.loaded[0] : nil }

    let first = store.load()
    check(first.errors.count, 0, "loads: \(first.errors)")
    check(first.loaded.map(\.isBuiltIn), [true], "built-in pack read from the app")
    check(first.loaded.first?.isCustomized, false, "not customized")
    let url = first.loaded[0].fileURL
    check(store.isBuiltIn(url), true, "url identifies a built-in pack")

    var edited = EditableSite(first.loaded[0].pack, fileURL: url)
    edited.name = "Demo (mine)"
    try! store.save(edited.pack, to: url)
    check(fm.fileExists(atPath: user.appendingPathComponent("demo.edits.json").path), true, "changes saved as edits file")
    check(fm.fileExists(atPath: user.appendingPathComponent("demo.json").path), false, "no full copy written")
    check(only()?.pack.name, "Demo (mine)", "changes applied on load")
    check(only()?.isCustomized, true, "customized")

    edited.name = "Demo"
    try! store.save(edited.pack, to: url)
    check(fm.fileExists(atPath: user.appendingPathComponent("demo.edits.json").path), false, "undoing every change removes the file")

    edited.name = "Demo (mine)"
    try! store.save(edited.pack, to: url)
    try! store.delete(url)
    check(store.load().loaded.count, 0, "deleted built-in is hidden")
    check(store.deletedBuiltIns().count, 1, "and restorable")
    check(try! store.restoreDeletedBuiltIns(), 1, "restore count")
    check(only()?.pack.name, "Demo (mine)", "restored with the user's changes")
    try! store.revertToBuiltIn(url)
    check(only()?.pack.name, "Demo", "revert drops the changes")

    // A user pack with the same file name replaces the built-in one.
    var mine = demo
    mine.name = "My Demo"
    try! store.save(mine, to: user.appendingPathComponent("demo.json"))
    check(only().map { [$0.pack.name, "\($0.isBuiltIn)"] }, ["My Demo", "false"], "user pack replaces built-in of the same name")
    try! fm.removeItem(at: user.appendingPathComponent("demo.json"))

    check(store.newFileURL(forName: "My Site!").lastPathComponent, "my-site.json", "slug")
    check(store.newFileURL(forName: "Demo").lastPathComponent, "demo-2.json", "new pack doesn't take a built-in pack's name")
    check(store.newFileURL(forName: "!!!").lastPathComponent, "site.json", "fallback name")
}

// MARK: Migrating full copies from 0.2.1 and earlier
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("kanpe-migrate-\(UUID().uuidString)")
    let bundled = root.appendingPathComponent("bundled"), user = root.appendingPathComponent("user"),
        legacy = root.appendingPathComponent("legacy")
    for dir in [bundled, user, legacy] { try! fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    defer { try? fm.removeItem(at: root) }
    func data(_ s: String) -> Data { Data(s.utf8) }

    // v1 shipped without ids; the user edited their copy; v2 (with ids) changed other things.
    let v1 = #"{"name":"Demo","match":["d.test"],"groups":[{"title":"G","shortcuts":[{"title":"One","keys":"1"},{"title":"Two","keys":"2"}]}]}"#
    let v2 = #"{"name":"Demo","updated":"2026-12-01","match":["d.test"],"groups":[{"id":"g","title":"G","shortcuts":[{"id":"g.one","title":"One","keys":"1"},{"id":"g.two","title":"Two","keys":"shift+2"},{"id":"g.three","title":"Three","keys":"3"}]}]}"#
    let userCopy = #"{"name":"Demo","match":["d.test"],"groups":[{"title":"G","shortcuts":[{"title":"One","keys":"cmd+1"},{"title":"Two","keys":"2"},{"title":"Mine","keys":"m"}]}]}"#
    let other = #"{"name":"Other","match":["o.test"],"groups":[{"id":"g","title":"G","shortcuts":[{"id":"g.x","title":"X","keys":"x"}]}]}"#
    // v0 is even older. The manifest names it, but the user's copy was later updated to v1 by
    // hand (without the manifest): the closest version, v1, should be used as the starting point.
    let v0 = #"{"name":"Demo","match":["d.test"],"groups":[{"title":"G","shortcuts":[{"title":"One","keys":"1"}]}]}"#
    try! data(v0).write(to: legacy.appendingPathComponent("demo-v0.json"))
    try! data(v1).write(to: legacy.appendingPathComponent("demo-v1.json"))
    try! data(v2).write(to: bundled.appendingPathComponent("demo.json"))
    try! data(other).write(to: bundled.appendingPathComponent("other.json"))
    try! data(other).write(to: bundled.appendingPathComponent("gone.json"))
    try! data(userCopy).write(to: user.appendingPathComponent("demo.json"))
    try! data(other).write(to: user.appendingPathComponent("other.json")) // unedited copy
    let manifest = ["demo.json": SitePackStore.digest(data(v0)), "other.json": SitePackStore.digest(data(other)),
                    "gone.json": SitePackStore.digest(data(other))]          // gone.json: the user deleted it
    try! JSONEncoder().encode(manifest).write(to: user.appendingPathComponent(".installed.json"))

    let store = SitePackStore(directory: user, bundledDirectory: bundled)
    check(try! store.migrateLegacyCopies(legacyDirectory: legacy), ["demo.json"], "edited copy converted")
    let result = store.load()
    check(result.errors.count, 0, "loads after migration: \(result.errors)")
    let demoPack = result.loaded.first { $0.pack.name == "Demo" }
    check(demoPack?.pack.groups[0].shortcuts.map { "\($0.title)=\($0.keys)" }, ["One=cmd+1", "Two=shift+2", "Mine=m", "Three=3"],
          "user's edits kept, built-in changes since v1 arrive")
    check(demoPack?.isBuiltIn, true, "now a built-in pack with changes")
    check(result.loaded.map(\.pack.name).sorted(), ["Demo", "Other"], "unedited copy replaced by built-in; deleted stays deleted")
    check(fm.fileExists(atPath: user.appendingPathComponent("Backups/demo.json").path), true, "edited copy backed up")
    check(fm.fileExists(atPath: user.appendingPathComponent("other.json").path), false, "unedited copy removed")
    check(fm.fileExists(atPath: user.appendingPathComponent(".installed.json").path), false, "manifest removed")
    check(try! store.migrateLegacyCopies(legacyDirectory: legacy), [], "runs once")
}

// MARK: Editing model
do {
    var site = EditableSite(demo, fileURL: nil)
    check(site.pack, demo, "editable round-trips to the same pack")

    // Per-shortcut level: stored only when it differs from the group's level.
    site.groups[1].setLevel(.complete, forShortcutAt: 1)  // group B is complete → override cleared
    check(site.groups[1].shortcuts[1].level, nil, "level equal to group's is not stored")
    site.groups[0].setLevel(.extended, forShortcutAt: 0)
    check(site.groups[0].shortcuts[0].level, .extended, "different level is stored")
    site.groups[0].setAllLevels(.complete)
    check(site.groups[0].level, .complete, "set-all stores on group")
    check(site.groups[0].shortcuts.allSatisfy { $0.level == nil }, true, "set-all clears overrides")

    // Blank rows are dropped on save; half-filled rows are kept and flagged.
    var blank = EditableSite.blank()
    check(blank.pack.groups[0].shortcuts.count, 0, "untouched blank row is not saved")
    check(blank.issues.count, 1, "blank site flags missing domain only: \(blank.issues)")
    blank.groups[0].shortcuts[0].title = "Do thing"
    check(blank.pack.groups[0].shortcuts.count, 1, "row with a title is saved")
    check(blank.issues.contains { $0.contains("no keys") }, true, "missing keys flagged")

    var d = EditableSite.blank()
    d.addDomains("https://GitHub.com/, gist.github.com  github.com")
    check(d.match, ["github.com", "gist.github.com"], "domains normalised and de-duplicated")
    check(d.addDomains("  "), false, "empty domain input ignored")
}

// MARK: Key recording
typealias M = KeyRecording.Modifiers
check(KeyRecording.notation(keyCode: 35, characters: "p", modifiers: [.shift, .command]), "shift+cmd+p", "letter with modifiers")
check(KeyRecording.notation(keyCode: 35, characters: "P", modifiers: [.shift]), "shift+p", "shifted letter lowercased")
check(KeyRecording.notation(keyCode: 44, characters: "?", modifiers: [.shift]), "?", "shift folded into symbol")
check(KeyRecording.notation(keyCode: 44, characters: "/", modifiers: [.command]), "cmd+/", "cmd slash")
check(KeyRecording.notation(keyCode: 36, characters: "\r", modifiers: [.command]), "cmd+enter", "named key")
check(KeyRecording.notation(keyCode: 123, characters: "\u{F702}", modifiers: []), "left", "arrow")
check(KeyRecording.notation(keyCode: 24, characters: "+", modifiers: [.command]), "cmd+plus", "plus key")
check(KeyRecording.notation(keyCode: 18, characters: "1", modifiers: [.shift]), "shift+1", "shift kept for digits")
check(KeyRecording.notation(keyCode: 999, characters: nil, modifiers: []), nil, "unknown key ignored")
check(KeyNotation.parse(KeyRecording.notation(keyCode: 35, characters: "p", modifiers: [.shift, .command])!), ["⇧⌘P"], "recorded notation renders")

// MARK: Bundled packs parse and render
let sitesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Sites")
let loaded = SitePackStore(directory: sitesDir).load()
check(loaded.errors.count, 0, "bundled packs decode: \(loaded.errors)")
check(loaded.packs.isEmpty, false, "bundled packs present")
for pack in loaded.packs {
    for group in pack.displayGroups() {
        for s in group.shortcuts where s.alternatives.isEmpty || s.alternatives.joined().contains(where: \.isEmpty) {
            failures += 1
            print("FAIL \(pack.name): empty chord in '\(s.title)'")
        }
    }
}
check(SiteMatcher.packs(for: gh, in: loaded.packs).map(\.name), ["GitHub"], "GitHub pack matches github.com")
check(SiteMatcher.packs(for: URL(string: "https://www.figma.com/design/abc/Untitled")!, in: loaded.packs).map(\.name), ["Figma"], "Figma pack matches figma.com")
check(SiteMatcher.packs(for: URL(string: "https://calendar.google.com/calendar/u/0/r/week")!, in: loaded.packs).map(\.name), ["Google Calendar"], "Google Calendar pack matches calendar.google.com")
check(SiteMatcher.packs(forApp: "com.t3tools.t3code", url: nil, in: loaded.packs).map(\.name), ["T3 Code"], "T3 Code pack matches its app")
check(SiteMatcher.packs(forApp: "com.google.Chrome", url: gh, in: loaded.packs).map(\.name), ["GitHub"], "browser still matches by URL")
if let cal = loaded.packs.first(where: { $0.name == "Google Calendar" }) {
    for path in ["/calendar/u/0/r/eventedit", "/calendar/u/1/r/eventedit/abc123", "/calendar/r/eventedit"] {
        check((cal.pages ?? []).contains { p in p.paths.contains { PathPattern.matches($0, path: path) } }, true, "Calendar event details page matches \(path)")
    }
    check((cal.pages ?? []).contains { p in p.paths.contains { PathPattern.matches($0, path: "/calendar/u/0/r/week") } }, false, "Calendar grid is not the event details page")
}
for pack in loaded.packs {
    let counts = DetailLevel.allCases.map(pack.count(at:))
    check(!pack.availableLevels.isEmpty && counts[0] < counts[1] && counts[1] < counts[2], true,
          "\(pack.name) levels grow strictly: \(counts)")
    print("  \(pack.name): Core \(counts[0]) · Extended \(counts[1]) · Complete \(counts[2])")
}

// MARK: Pages (URL path patterns)
check(PathPattern.matches("/*/*", path: "/apple/swift"), true, "two segments")
check(PathPattern.matches("/*/*", path: "/apple/swift/"), true, "trailing slash ignored")
check(PathPattern.matches("/*/*", path: "/apple"), false, "too few segments")
check(PathPattern.matches("/*/*", path: "/apple/swift/issues"), false, "too many segments")
check(PathPattern.matches("/*/*/issues/**", path: "/a/b/issues"), true, "** matches zero segments")
check(PathPattern.matches("/*/*/issues/**", path: "/a/b/issues/12/edit"), true, "** matches several")
check(PathPattern.matches("/*/*/pull*", path: "/a/b/pulls"), true, "glob in a segment")
check(PathPattern.matches("/*/*/pull*", path: "/a/b/issues"), false, "glob mismatch")
check(PathPattern.matches("/a/**/z", path: "/a/b/c/z"), true, "** in the middle")
check(PathPattern.matches("/Issues", path: "/issues"), true, "case-insensitive")
check(PathPattern.matches("/", path: "/"), true, "root")
check(PathPattern.matches("/{issues,pulls}", path: "/pulls"), true, "alternatives")
check(PathPattern.matches("/{issues,pulls}", path: "/wiki"), false, "alternatives mismatch")
check(PathPattern.matches("/x{a,b}*", path: "/xbz"), true, "alternatives inside a glob")
let repoPage = SitePack.Page(name: "Repo", paths: ["/*/*/**", "!/settings/**"])
check(repoPage.matches(path: "/apple/swift/tree/main"), true, "page matches")
check(repoPage.matches(path: "/settings/profile"), false, "! excludes")

let pagedJSON = """
{ "name": "P", "match": ["p.test"],
  "pages": [ { "name": "Repo", "paths": ["/*/*/**"] }, { "name": "Issues", "paths": ["/*/*/issues/**"] } ],
  "groups": [
    { "title": "Everywhere", "shortcuts": [ { "title": "e", "keys": "e" } ] },
    { "title": "Repo", "pages": ["Repo"], "shortcuts": [ { "title": "r", "keys": "r" } ] },
    { "title": "Issues", "pages": ["Issues"], "shortcuts": [ { "title": "i", "keys": "i" } ] } ] }
"""
let paged = try! JSONDecoder().decode(SitePack.self, from: Data(pagedJSON.utf8))
let issuesURL = URL(string: "https://p.test/a/b/issues/3")!
check(paged.pages(for: issuesURL), ["Repo", "Issues"], "pages for URL, in pack order")
check(paged.pages(for: URL(string: "https://p.test/")!), [], "no page on the home page")
check(paged.hasPageSpecificGroups, true, "has page groups")
check(paged.displayGroups(pages: ["Repo", "Issues"]).map(\.title), ["P · Repo", "P · Issues", "P · Everywhere"],
      "page groups first, then site-wide")
check(paged.displayGroups(pages: []).map(\.title), ["P"], "home page: only site-wide (single group uses pack name)")
check(paged.displayGroups(pages: nil).map(\.title), ["P · Everywhere", "P · Repo", "P · Issues"],
      "filter off: everything in file order")
check(flat.hasPageSpecificGroups, false, "pack without pages has nothing to toggle")

// Editing keeps page links through renames, and round-trips.
var pagedEdit = EditableSite(paged, fileURL: nil)
pagedEdit.pages[1].name = "Issue tracker"
check(pagedEdit.pack.groups[2].pages, ["Issue tracker"], "rename follows group link")
pagedEdit.deletePage(pagedEdit.pages[1].id)
check(pagedEdit.pack.groups[2].pages, nil, "deleting a page makes its groups site-wide")
check(EditableSite(paged, fileURL: nil).pack, paged, "page round-trip")
let orphan = try! JSONDecoder().decode(SitePack.self, from: Data(#"{"name":"O","match":["o.test"],"groups":[{"title":"G","pages":["Ghost"],"shortcuts":[{"title":"x","keys":"x"}]}]}"#.utf8))
let orphanEdit = EditableSite(orphan, fileURL: nil)
check(orphanEdit.pages.map(\.name), ["Ghost"], "undefined page kept as empty page")
check(orphanEdit.issues.contains { $0.contains("Ghost") }, true, "empty page flagged")
var page = EditableSite.Page(name: "X")
page.addPaths("https://github.com/apple/swift/issues?q=1, /*/*/pulls/ !settings/**")
check(page.paths, ["/apple/swift/issues", "/*/*/pulls", "!/settings/**"], "paths normalised from URLs")

// Bundled GitHub pages.
if let github = loaded.packs.first(where: { $0.name == "GitHub" }) {
    func on(_ path: String) -> [String] { github.pages(for: URL(string: "https://github.com" + path)!) }
    check(on("/apple/swift"), ["Repository", "Code"], "repo home is Code")
    check(on("/apple/swift/blob/main/README.md"), ["Repository", "Code"], "file view is Code")
    check(on("/apple/swift/issues"), ["Repository", "Issues"], "issue list")
    check(on("/apple/swift/issues/42"), ["Repository", "Issue"], "single issue")
    check(on("/apple/swift/pulls"), ["Repository", "Pull requests"], "PR list")
    check(on("/apple/swift/pull/7/files"), ["Repository", "Pull request"], "PR files")
    check(on("/settings/profile"), [], "settings is not a repo")
    check(on("/notifications"), ["Notifications"], "notifications")
    check(on("/"), [], "home")
}

// MARK: Freshness ("updated" dates)
do {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let now = PackDate.parse("2026-11-19", calendar: utc)!.addingTimeInterval(15 * 3600)
    func age(_ day: String) -> String { PackDate.age(of: PackDate.parse(day, calendar: utc)!, now: now, calendar: utc) }
    check(age("2026-11-19"), "today", "same day")
    check(age("2026-11-18"), "yesterday", "one day")
    check(age("2026-11-09"), "10 days ago", "days")
    check(age("2026-10-29"), "3 weeks ago", "weeks")
    check(age("2026-06-01"), "5 months ago", "months")
    check(age("2025-10-01"), "over a year ago", "a year")
    check(age("2023-01-01"), "over 3 years ago", "years")
    check(PackDate.parse("not a date"), nil, "bad date rejected")
    check(PackDate.string(from: PackDate.parse("2026-01-05", calendar: utc)!, calendar: utc), "2026-01-05", "date round-trip")
    let dated = SitePack(name: "D", updated: "2026-11-01", match: ["d.test"], groups: [])
    check(EditableSite(dated, fileURL: nil).pack.updated, "2026-11-01", "editor keeps updated")
    let encoded = String(decoding: try! SitePackStore.encode(dated), as: UTF8.self)
    check(encoded.contains("\"updated\" : \"2026-11-01\""), true, "updated is saved")
    let modified = Date(timeIntervalSince1970: 1_000_000)
    check(SitePackStore.LoadedPack(fileURL: URL(fileURLWithPath: "/x"), pack: SitePack(name: "N", match: [], groups: []),
                                   modified: modified).updatedDate, modified, "no updated: file date")
    for lp in loaded.loaded {
        check(lp.pack.updated.flatMap { PackDate.parse($0) } != nil, true, "\(lp.pack.name) has a valid updated date")
    }
    // Every page, group and shortcut has an id, unique per kind (the user's changes refer to them).
    for pack in loaded.packs {
        let pageIDs = (pack.pages ?? []).map(\.id), groupIDs = pack.groups.map(\.id)
        let shortcutIDs = pack.groups.flatMap { $0.shortcuts.map(\.id) }
        for (kind, ids) in [("page", pageIDs), ("group", groupIDs), ("shortcut", shortcutIDs)] {
            check(ids.filter { $0 == nil }.count, 0, "\(pack.name): every \(kind) has an id (run scripts/add-pack-ids.py)")
            check(Set(ids).count, ids.count, "\(pack.name): \(kind) ids are unique")
        }
    }
    // Earlier versions (for migrating edited copies) still decode.
    let legacyDir = sitesDir.deletingLastPathComponent().appendingPathComponent("LegacySites")
    let legacyFiles = (try? FileManager.default.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil)) ?? []
    check(legacyFiles.isEmpty, false, "legacy packs present")
    for file in legacyFiles {
        check((try? JSONDecoder().decode(SitePack.self, from: Data(contentsOf: file))) != nil, true, "\(file.lastPathComponent) decodes")
    }
}

// MARK: App menu levels
do {
    func lvl(_ title: String, _ chord: String) -> DetailLevel { MenuLevels.level(of: Shortcut(title: title, chord: chord)) }
    check(lvl("Copy", "⌘C"), .core, "universal chord")
    check(lvl("Kopieren", "⌘C"), .core, "universal chord in another language")
    check(lvl("Reopen Closed Tab", "⇧⌘T"), .core, "core title")
    check(lvl("Find › Find…", "⌘F"), .core, "core title in a submenu, ellipsis ignored")
    check(lvl("Select Next Tab", "⌃⇥"), .core, "core title without ⌘")
    check(lvl("Bookmark All Tabs…", "⇧⌘D"), .extended, "two modifiers")
    check(lvl("Developer › Developer Tools", "⌥⌘I"), .extended, "one submenu deep")
    check(lvl("Close All", "⌥⇧⌘W"), .complete, "three modifiers")
    check(lvl("Center", "⌃C"), .complete, "no ⌘")
    check(lvl("Emoji & Symbols", "fn E"), .complete, "fn key")
    check(lvl("A › B › C", "⌘K"), .complete, "two submenus deep")
    let menus = [ShortcutGroup(title: "File", shortcuts: [Shortcut(title: "New Tab", chord: "⌘T"),
                                                          Shortcut(title: "Close All", chord: "⌥⇧⌘W")], source: .app),
                 ShortcutGroup(title: "Window", shortcuts: [Shortcut(title: "Fill", chord: "⌃F")], source: .app)]
    check(MenuLevels.filter(menus, level: .core).map(\.title), ["File"], "empty groups dropped")
    check(MenuLevels.filter(menus, level: .complete).map { $0.shortcuts.count }, [2, 1], "complete keeps all")
    check(MenuLevels.count(menus, at: .extended), 1, "count at level")
    check(MenuLevels.availableLevels(menus), DetailLevel.allCases, "levels offered")
    check(MenuLevels.availableLevels([menus[1]]), [], "one level: nothing to choose")
}

if failures == 0 {
    print("All checks passed (\(loaded.packs.count) bundled site packs).")
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
