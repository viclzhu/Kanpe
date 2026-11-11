import AppKit
import SwiftUI
import KanpeCore

/// A borderless panel that floats above everything without taking focus from the
/// frontmost app, so the user's ⌘ shortcuts keep going to that app.
private final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the level picker respond to the first click even though the panel never becomes key.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelController {
    private let panel = FloatingPanel()
    var onLevelChange: (String, DetailLevel) -> Void = { _, _ in }
    /// Site name to open in the editor, or nil for the editor's default selection.
    var onEdit: (String?) -> Void = { _ in }
    var onToggleAppMenus: () -> Void = {}

    var isVisible: Bool { panel.isVisible }

    func show(_ content: PanelContent, icon: NSImage?, animated: Bool = true) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let maxSize = CGSize(width: visible.width * 0.94, height: visible.height * 0.88)

        let rowHeight: CGFloat = 19
        let maxColumns = max(1, Int((maxSize.width - 36) / (PanelView.columnWidth + 18)))
        let targetRows = max(10, Int((maxSize.height - 90) / rowHeight))
        let columns = ColumnLayout.columns(content.groups, rows: { $0.shortcuts.count },
                                           maxColumns: maxColumns, targetRowsPerColumn: targetRows)

        let view = PanelView(content: content, icon: icon, columns: columns,
                             onLevelChange: { [weak self] site, level in self?.onLevelChange(site, level) },
                             onEdit: { [weak self] site in self?.onEdit(site) },
                             onToggleAppMenus: { [weak self] in self?.onToggleAppMenus() })
        let hosting = ClickThroughHostingView(rootView: view)
        var size = hosting.fittingSize

        if size.height > maxSize.height {
            // Too tall even with all columns used: make it scroll.
            let scroll = ClickThroughHostingView(rootView: ScrollView { view }.frame(width: size.width + 16, height: maxSize.height))
            panel.contentView = scroll
            size = CGSize(width: size.width + 16, height: maxSize.height)
        } else {
            panel.contentView = hosting
        }

        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        guard animated else { return } // re-render in place (e.g. level change)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}
