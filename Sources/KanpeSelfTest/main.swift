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
let cols = ColumnLayout.columns([10, 10, 10, 10], rows: { $0 }, maxColumns: 4, targetRowsPerColumn: 24)
check(cols.count, 2, "two columns for 48 rows at 24/col")
check(cols.flatMap { $0 }, [10, 10, 10, 10], "order preserved")
check(ColumnLayout.columns([50], rows: { $0 }, maxColumns: 4, targetRowsPerColumn: 10).count, 1, "never more columns than groups")
check(ColumnLayout.columns([5, 5, 5], rows: { $0 }, maxColumns: 1, targetRowsPerColumn: 5).count, 1, "respects maxColumns")

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

if failures == 0 {
    print("All checks passed (\(loaded.packs.count) bundled site packs).")
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
