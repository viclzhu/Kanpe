// Posts ⌘ tap, then ⌘ press-and-hold for 1 s, then release: a human double-tap-hold.
// Fires Kanpe's default trigger without touching the keyboard. The terminal needs Accessibility.
//   swiftc -o /tmp/tap-trigger .claude/skills/kanpe-dev/scripts/tap-trigger.swift && /tmp/tap-trigger
import CoreGraphics
import Foundation
let src = CGEventSource(stateID: .hidSystemState)
func cmd(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: down)!
    e.type = .flagsChanged
    e.flags = down ? .maskCommand : []
    e.post(tap: .cghidEventTap)
}
cmd(true);  usleep(80_000); cmd(false); usleep(120_000)   // tap
cmd(true);  usleep(1_000_000); cmd(false)                 // press and hold
print("posted ⌘ tap + hold")
