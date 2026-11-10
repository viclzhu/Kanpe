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

if failures == 0 {
    print("All checks passed (\(loaded.packs.count) bundled site packs).")
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
