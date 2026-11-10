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

final class PanelController {
    private let panel = FloatingPanel()

    func show(_ content: PanelContent, icon: NSImage?) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let maxSize = CGSize(width: visible.width * 0.94, height: visible.height * 0.88)

        let rowHeight: CGFloat = 19
        let maxColumns = max(1, Int((maxSize.width - 36) / (PanelView.columnWidth + 18)))
        let targetRows = max(10, Int((maxSize.height - 90) / rowHeight))
        let columns = ColumnLayout.columns(content.groups, rows: { $0.shortcuts.count },
                                           maxColumns: maxColumns, targetRowsPerColumn: targetRows)

        let view = PanelView(content: content, icon: icon, columns: columns)
        let hosting = NSHostingView(rootView: view)
        var size = hosting.fittingSize

        if size.height > maxSize.height {
            // Too tall even with all columns used: make it scroll.
            let scroll = NSHostingView(rootView: ScrollView { view }.frame(width: size.width + 16, height: maxSize.height))
            panel.contentView = scroll
            size = CGSize(width: size.width + 16, height: maxSize.height)
        } else {
            panel.contentView = hosting
        }

        let origin = CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
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
