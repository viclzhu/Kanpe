import AppKit
import SwiftUI
import KanpeCore

/// Hosts the shortcut editor. Kanpe is menu-bar only by default, including while editing.
/// With `showsDockIconWhileEditing` on, it becomes a regular app (Dock icon, ⌘Tab) while this
/// window is open.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: EditorModel

    /// UserDefaults key. Off by default: the editor opens without a Dock icon.
    static let dockIconKey = "showDockIconWhileEditing"
    static var showsDockIconWhileEditing: Bool {
        get { UserDefaults.standard.bool(forKey: dockIconKey) }
        set { UserDefaults.standard.set(newValue, forKey: dockIconKey) }
    }

    var isOpen: Bool { window?.isVisible ?? false }

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
        applyActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.flushSaves()
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// Dock icon only while the editor is open, and only if the user asked for it.
    func applyActivationPolicy() {
        let editing = window != nil
        NSApp.setActivationPolicy(editing && Self.showsDockIconWhileEditing ? .regular : .accessory)
        if editing { window?.makeKeyAndOrderFront(nil) } // switching policy can hide the window
    }
}
