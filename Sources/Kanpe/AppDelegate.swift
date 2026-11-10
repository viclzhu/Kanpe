import AppKit
import KanpeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor: ActivationMonitor
    private let panel = PanelController()
    private let store = SitePackStore(directory: SitePackStore.defaultDirectory)
    private var packs: [SitePack] = []
    private var statusItem: NSStatusItem!
    private var trustTimer: Timer?

    // Prefetch state: gathering starts when ⌘ goes down, so the panel is usually ready by the
    // time the hold delay elapses.
    private var generation = 0
    private var prefetched: (generation: Int, app: NSRunningApplication, menus: [ShortcutGroup], url: URL?)?
    private var wantsShow = false
    /// What's on screen, kept so a level change can re-render without re-reading the app.
    private var shown: (app: NSRunningApplication, menus: [ShortcutGroup], url: URL?)?

    private let defaults = UserDefaults.standard

    override init() {
        defaults.register(defaults: ["holdDelay": 0.6, "triggerMode": TriggerMode.doubleTapHold.rawValue])
        let mode = TriggerMode(rawValue: defaults.string(forKey: "triggerMode") ?? "") ?? .doubleTapHold
        monitor = ActivationMonitor(mode: mode, holdDelay: defaults.double(forKey: "holdDelay"))
        super.init()
    }

    private var useAppleScriptFallback: Bool {
        get { defaults.object(forKey: "useAppleScriptFallback") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "useAppleScriptFallback") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reloadPacks(installDefaults: true)
        setUpStatusItem()

        monitor.onBegin = { [weak self] in self?.prefetch() }
        monitor.onShow = { [weak self] in self?.wantsShow = true; self?.presentIfReady() }
        monitor.onHide = { [weak self] in self?.wantsShow = false; self?.shown = nil; self?.panel.hide() }
        panel.onLevelChange = { [weak self] site, level in
            self?.setLevel(level, forSite: site)
        }

        if AX.isTrusted {
            monitor.start()
        } else {
            AX.requestTrust()
            // Global event monitors only work once trusted, so start them as soon as that happens.
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                guard AX.isTrusted else { return }
                timer.invalidate()
                self?.monitor.start()
                self?.rebuildMenu()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return false
    }

    // MARK: - Gathering

    private func prefetch() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        generation += 1
        let gen = generation
        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let menus = MenuReader.groups(pid: pid)
            var url: URL?
            if let bundleID, BrowserURLReader.isBrowser(bundleID) {
                url = BrowserURLReader.urlViaAccessibility(pid: pid, bundleID: bundleID)
            }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.prefetched = (gen, app, menus, url)
                self.presentIfReady()
            }
        }
    }

    private func presentIfReady() {
        guard wantsShow, monitor.isShowing,
              let data = prefetched, data.generation == generation else { return }
        wantsShow = false

        var url = data.url
        let bundleID = data.app.bundleIdentifier
        if url == nil, useAppleScriptFallback, let bundleID, BrowserURLReader.isBrowser(bundleID) {
            url = BrowserURLReader.urlViaAppleScript(bundleID: bundleID)
        }

        shown = (data.app, data.menus, url)
        render()
    }

    private func render() {
        guard let shown else { return }
        let bundleID = shown.app.bundleIdentifier
        let matched = shown.url.map { SiteMatcher.packs(for: $0, in: packs) } ?? []
        let content = PanelContent(
            appName: shown.app.localizedName ?? bundleID ?? "App",
            bundleID: bundleID,
            host: shown.url.flatMap(SiteMatcher.normalizedHost),
            sites: matched.map { SiteInfo(name: $0.name, level: level(forSite: $0.name), availableLevels: $0.availableLevels) },
            groups: matched.flatMap { $0.displayGroups(level: level(forSite: $0.name)) } + shown.menus
        )
        panel.show(content, icon: shown.app.icon, animated: !panel.isVisible)
    }

    // MARK: - Detail levels (remembered per site)

    private func level(forSite name: String) -> DetailLevel {
        let stored = (defaults.dictionary(forKey: "siteLevels") as? [String: String])?[name]
        return stored.flatMap(DetailLevel.init(rawValue:)) ?? .default
    }

    private func setLevel(_ level: DetailLevel, forSite name: String) {
        var levels = (defaults.dictionary(forKey: "siteLevels") as? [String: String]) ?? [:]
        levels[name] = level.rawValue
        defaults.set(levels, forKey: "siteLevels")
        render()
        rebuildMenu()
    }

    // MARK: - Site packs

    private func reloadPacks(installDefaults: Bool = false) {
        if installDefaults {
            try? store.installDefaults(from: Bundle.main.resourceURL?.appendingPathComponent("Sites"))
        }
        let result = store.load()
        packs = result.packs
        if !result.errors.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Some site shortcut files could not be read"
            alert.informativeText = result.errors.map { "\($0.file): \($0.message)" }.joined(separator: "\n\n")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command.square", accessibilityDescription: "Kanpe")
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false // so isEnabled = false on info rows and Hold Delay sticks
        let hint = NSMenuItem(title: "\(monitor.mode.title) to show shortcuts", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        if !AX.isTrusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(grantAccess)))
            menu.addItem(.separator())
        }

        let sites = NSMenuItem(title: "Site Shortcuts (\(packs.count) sites)", action: nil, keyEquivalent: "")
        sites.isEnabled = false
        menu.addItem(sites)
        let leveled = packs.filter { !$0.availableLevels.isEmpty }
        if !leveled.isEmpty {
            let detail = NSMenuItem(title: "Detail Level", action: nil, keyEquivalent: "")
            let detailMenu = NSMenu()
            detailMenu.autoenablesItems = false
            for pack in leveled {
                let siteItem = NSMenuItem(title: "\(pack.name) — \(level(forSite: pack.name).title)", action: nil, keyEquivalent: "")
                let levelsMenu = NSMenu()
                for lvl in DetailLevel.allCases {
                    let i = item("\(lvl.title) (\(pack.count(at: lvl)))", #selector(setLevelFromMenu(_:)))
                    i.representedObject = [pack.name, lvl.rawValue]
                    i.state = level(forSite: pack.name) == lvl ? .on : .off
                    levelsMenu.addItem(i)
                }
                siteItem.submenu = levelsMenu
                detailMenu.addItem(siteItem)
            }
            detail.submenu = detailMenu
            menu.addItem(detail)
        }
        menu.addItem(item("Open Site Shortcuts Folder", #selector(openSitesFolder)))
        menu.addItem(item("Reload Site Shortcuts", #selector(reloadSites), key: "r"))

        let fallback = item("Read Tab URL via AppleScript if Needed", #selector(toggleAppleScript))
        fallback.state = useAppleScriptFallback ? .on : .off
        fallback.toolTip = "Used when a browser doesn't expose its URL through Accessibility. macOS asks once per browser."
        menu.addItem(fallback)

        let trigger = NSMenuItem(title: "Trigger", action: nil, keyEquivalent: "")
        let triggerMenu = NSMenu()
        for mode in TriggerMode.allCases {
            let i = item(mode.title, #selector(setTrigger(_:)))
            i.representedObject = mode.rawValue
            i.state = monitor.mode == mode ? .on : .off
            triggerMenu.addItem(i)
        }
        trigger.submenu = triggerMenu
        menu.addItem(trigger)

        let delay = NSMenuItem(title: "Hold Delay", action: nil, keyEquivalent: "")
        // Only meaningful for "Hold ⌘"; the double-tap gesture uses a short fixed hold.
        delay.isEnabled = monitor.mode == .hold
        let delayMenu = NSMenu()
        for seconds in [0.3, 0.45, 0.6, 0.8, 1.0] {
            let i = item(String(format: "%.2g s", seconds), #selector(setDelay(_:)))
            i.representedObject = seconds
            i.state = abs(monitor.holdDelay - seconds) < 0.01 ? .on : .off
            delayMenu.addItem(i)
        }
        delay.submenu = delayMenu
        menu.addItem(delay)

        menu.addItem(.separator())
        menu.addItem(item("Quit Kanpe", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func grantAccess() {
        AX.requestTrust()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openSitesFolder() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.directory)
    }

    @objc private func reloadSites() {
        reloadPacks()
        rebuildMenu()
    }

    @objc private func toggleAppleScript() {
        useAppleScriptFallback.toggle()
        rebuildMenu()
    }

    @objc private func setLevelFromMenu(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let lvl = DetailLevel(rawValue: pair[1]) else { return }
        setLevel(lvl, forSite: pair[0])
    }

    @objc private func setTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = TriggerMode(rawValue: raw) else { return }
        monitor.mode = mode
        defaults.set(raw, forKey: "triggerMode")
        rebuildMenu()
    }

    @objc private func setDelay(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        monitor.holdDelay = seconds
        defaults.set(seconds, forKey: "holdDelay")
        rebuildMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
