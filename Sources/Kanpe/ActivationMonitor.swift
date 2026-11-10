import AppKit

/// Detects "hold ⌘ alone" and reports begin (start prefetching), show, and hide.
///
/// Holding ⌘ with no other modifier or key for `holdDelay` shows the panel; releasing ⌘
/// hides it. Pressing any key while ⌘ is down (⌘C, ⌘Tab…) cancels, so normal shortcuts
/// never flash the panel.
final class ActivationMonitor {
    var holdDelay: TimeInterval = 0.6
    var onBegin: () -> Void = {}
    var onShow: () -> Void = {}
    var onHide: () -> Void = {}

    private var pending: DispatchWorkItem?
    private(set) var isShowing = false
    private var monitors: [Any] = []

    func start() {
        guard monitors.isEmpty else { return }
        let flags: (NSEvent) -> Void = { [weak self] in self?.handleFlags($0) }
        let key: (NSEvent) -> Void = { [weak self] in self?.handleKey($0) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: key) { monitors.append(m) }
        // Local monitors cover the rare case where Kanpe itself is active (e.g. its menu is open).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { key($0); return $0 }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancelPending()
    }

    private func handleFlags(_ event: NSEvent) {
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])

        if mods == .command {
            guard !isShowing, pending == nil else { return }
            onBegin()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pending = nil
                self.isShowing = true
                self.onShow()
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
        } else {
            cancelPending()
            hideIfShowing()
        }
    }

    private func handleKey(_ event: NSEvent) {
        cancelPending()
        // Escape, or any shortcut typed while the panel is up, dismisses it.
        hideIfShowing()
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    private func hideIfShowing() {
        guard isShowing else { return }
        isShowing = false
        onHide()
    }
}
