import AppKit
import SwiftUI
import KanpeCore

// Debug modes (need the launching terminal to have Accessibility access):
//   Kanpe --dump <bundle-id>                 print what the panel would show for a running app
//   Kanpe --render <bundle-id> <out.png> [url]   render the panel to a PNG (optional URL overrides the tab)
let args = CommandLine.arguments
if let flag = args.firstIndex(of: "--render"), args.count > flag + 2 {
    let bundleID = args[flag + 1]
    guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        print("Not running: \(bundleID)")
        exit(1)
    }
    let pid = target.processIdentifier
    let url = args.count > flag + 3 ? URL(string: args[flag + 3]) : BrowserURLReader.urlViaAccessibility(pid: pid, bundleID: bundleID)
    let packs = SitePackStore(directory: SitePackStore.defaultDirectory).load().packs
    let matched = url.map { SiteMatcher.packs(for: $0, in: packs) } ?? []
    let content = PanelContent(appName: target.localizedName ?? bundleID, bundleID: bundleID,
                               host: url.flatMap(SiteMatcher.normalizedHost), matchedSites: matched.map(\.name),
                               groups: matched.flatMap { $0.displayGroups() } + MenuReader.groups(pid: pid))
    _ = NSApplication.shared
    let columns = ColumnLayout.columns(content.groups, rows: { $0.shortcuts.count }, maxColumns: 5, targetRowsPerColumn: 42)
    let view = PanelView(content: content, icon: target.icon, columns: columns)
        .background(Color(nsColor: .windowBackgroundColor))
    let hosting = NSHostingView(rootView: view)
    hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
    let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[flag + 2]))
    print("Wrote \(args[flag + 2]) (\(Int(hosting.bounds.width))×\(Int(hosting.bounds.height)))")
    exit(0)
}
if let flag = args.firstIndex(of: "--dump"), args.count > flag + 1 {
    let bundleID = args[flag + 1]
    guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        print("Not running: \(bundleID)")
        exit(1)
    }
    print("Accessibility trusted: \(AX.isTrusted)")
    let pid = target.processIdentifier
    var url = BrowserURLReader.urlViaAccessibility(pid: pid, bundleID: bundleID)
    print("Tab host via Accessibility: \(url.flatMap(SiteMatcher.normalizedHost) ?? "none")")
    if url == nil, BrowserURLReader.isBrowser(bundleID) {
        url = BrowserURLReader.urlViaAppleScript(bundleID: bundleID)
        print("Tab host via AppleScript: \(url.flatMap(SiteMatcher.normalizedHost) ?? "none")")
    }
    var groups = MenuReader.groups(pid: pid)
    if let url {
        let packs = SitePackStore(directory: SitePackStore.defaultDirectory).load().packs
        groups = SiteMatcher.packs(for: url, in: packs).flatMap { $0.displayGroups() } + groups
    }
    for group in groups {
        print("\n[\(group.source.rawValue)] \(group.title)")
        for s in group.shortcuts {
            let keys = s.alternatives.map { $0.joined(separator: " then ") }.joined(separator: " or ")
            print("  \(keys.padding(toLength: 14, withPad: " ", startingAt: 0)) \(s.title)")
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
app.run()
