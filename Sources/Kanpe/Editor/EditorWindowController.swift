import AppKit
import SwiftUI
import KanpeCore

/// Hosts the shortcut editor. Kanpe is a menu-bar app, so while this window is open it
/// temporarily becomes a regular app (Dock icon, ⌘Tab) to behave like a normal window.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: EditorModel

    init(store: SitePackStore, bundledDirectory: URL?, onChange: @escaping () -> Void) {
        model = EditorModel(store: store, bundledDirectory: bundledDirectory)
        super.init()
        model.onChange = onChange
    }

    func show(selectingSiteNamed name: String? = nil) {
        if window == nil {
            model.reload()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 940, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "Edit Shortcuts"
            window.contentViewController = NSHostingController(rootView: EditorRootView(model: model))
            window.setContentSize(NSSize(width: 940, height: 640))
            window.contentMinSize = NSSize(width: 780, height: 460)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("KanpeEditor")
            if !window.setFrameUsingName("KanpeEditor") { window.center() }
            self.window = window
        }
        if let name, let site = model.sites.first(where: { $0.name == name }) {
            model.selection = site.id
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.flushSaves()
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
