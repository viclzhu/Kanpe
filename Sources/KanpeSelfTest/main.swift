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

// MARK: Installing bundled packs never clobbers user edits
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("kanpe-selftest-\(UUID().uuidString)")
    let bundled = root.appendingPathComponent("bundled"), user = root.appendingPathComponent("user")
    try! fm.createDirectory(at: bundled, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let store = SitePackStore(directory: user)
    func write(_ text: String, _ dir: URL, _ name: String) { try! Data(text.utf8).write(to: dir.appendingPathComponent(name)) }
    func read(_ name: String) -> String { String(decoding: try! Data(contentsOf: user.appendingPathComponent(name)), as: UTF8.self) }

    write("v1", bundled, "a.json"); write("v1", bundled, "b.json")
    try! store.installDefaults(from: bundled)
    check(read("a.json"), "v1", "fresh install copies")

    write("user edit", user, "b.json")          // user edits b
    write("v2", bundled, "a.json"); write("v2", bundled, "b.json")  // app update ships v2
    try! store.installDefaults(from: bundled)
    check(read("a.json"), "v2", "unedited pack is updated")
    check(read("b.json"), "user edit", "edited pack is kept")

    write("legacy", user, "c.json"); write("v1", bundled, "c.json")  // pre-existing file, no manifest entry
    try! store.installDefaults(from: bundled)
    check(read("c.json"), "legacy", "unknown pre-existing file is kept")
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

// MARK: Store editing operations
do {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("kanpe-edit-\(UUID().uuidString)")
    let bundled = root.appendingPathComponent("bundled"), user = root.appendingPathComponent("user")
    try! fm.createDirectory(at: bundled, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try! SitePackStore.encode(demo).write(to: bundled.appendingPathComponent("demo.json"))
    let store = SitePackStore(directory: user)
    try! store.installDefaults(from: bundled)

    let first = store.load()
    check(first.errors.count, 0, "install manifest is not read as a pack: \(first.errors)")
    check(first.packs, [demo], "installed pack loads")

    // Edit and save: counts as a user edit, so app updates leave it alone.
    let url = first.loaded[0].fileURL
    var edited = EditableSite(demo, fileURL: url)
    edited.name = "Demo (mine)"
    try! store.save(edited.pack, to: url)
    try! store.installDefaults(from: bundled)
    check(store.load().packs.first?.name, "Demo (mine)", "saved edit survives reinstall")

    // Revert brings back the built-in.
    check(store.bundledPackURL(for: url, in: bundled) != nil, true, "detected as built-in")
    try! store.revertToBundled(url, from: bundled)
    check(store.load().packs.first?.name, "Demo", "revert restores built-in")

    // Delete sticks across launches; restore brings it back.
    try! store.delete(url)
    try! store.installDefaults(from: bundled)
    check(store.load().packs.count, 0, "deleted built-in stays deleted")
    check(store.missingBundledPacks(in: bundled).count, 1, "deleted built-in is restorable")
    check(try! store.restoreMissingBundledPacks(from: bundled), 1, "restore count")
    check(store.load().packs.first?.name, "Demo", "restored")

    // New file names are slugged and unique.
    check(store.newFileURL(forName: "My Site!").lastPathComponent, "my-site.json", "slug")
    check(store.newFileURL(forName: "Demo").lastPathComponent, "demo-2.json", "unique name")
    check(store.newFileURL(forName: "!!!").lastPathComponent, "site.json", "fallback name")
}

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
