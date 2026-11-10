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
    let url = args.count > flag + 3 && !args[flag + 3].hasPrefix("--") ? URL(string: args[flag + 3]) : BrowserURLReader.urlViaAccessibility(pid: pid, bundleID: bundleID)
    // Optional: --level core|extended|complete (default: Core)
    let level = args.firstIndex(of: "--level").flatMap { args.count > $0 + 1 ? DetailLevel(rawValue: args[$0 + 1]) : nil } ?? .default
    let packs = SitePackStore(directory: SitePackStore.defaultDirectory).load().packs
    let matched = url.map { SiteMatcher.packs(for: $0, in: packs) } ?? []
    let content = PanelContent(appName: target.localizedName ?? bundleID, bundleID: bundleID,
                               host: url.flatMap(SiteMatcher.normalizedHost),
                               sites: matched.map { SiteInfo(name: $0.name, level: level, availableLevels: $0.availableLevels) },
                               groups: matched.flatMap { $0.displayGroups(level: level) } + MenuReader.groups(pid: pid))
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
// Kanpe --render-editor <out.png> [site name]   render the shortcut editor (read-only; nothing is saved)
if let flag = args.firstIndex(of: "--render-editor"), args.count > flag + 1 {
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        let model = EditorModel(store: SitePackStore(directory: SitePackStore.defaultDirectory), bundledDirectory: nil)
        if args.count > flag + 2, let site = model.sites.first(where: { $0.name == args[flag + 2] }) {
            model.selection = site.id
        }
        let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 940, height: 640),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Edit Shortcuts"
        window.contentViewController = NSHostingController(rootView: EditorRootView(model: model))
        window.setContentSize(NSSize(width: 940, height: 640))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0)) // let SwiftUI lay out
        // Window-server capture (needs Screen Recording permission for the launching terminal);
        // offscreen view caching can't draw SwiftUI lists/sidebars.
        guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution]) else {
            print("Window capture failed (Screen Recording permission?)")
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[flag + 1]))
        print("Wrote \(args[flag + 1])")
        exit(0)
    }
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

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
    app.run()
}
