import AppKit
import KanpeCore

/// Feeds global keyboard events into `TriggerStateMachine` and carries out its effects.
/// See `TriggerMode` for the supported gestures.
final class ActivationMonitor {
    var onBegin: () -> Void = {}
    var onShow: () -> Void = {}
    var onHide: () -> Void = {}

    private var machine: TriggerStateMachine
    private var pending: DispatchWorkItem?
    private var previousModifiers: NSEvent.ModifierFlags = []
    private var monitors: [Any] = []

    init(mode: TriggerMode, holdDelay: TimeInterval) {
        machine = TriggerStateMachine(mode: mode, holdDelay: holdDelay)
    }

    var mode: TriggerMode {
        get { machine.mode }
        set { reset(); machine.mode = newValue }
    }

    var holdDelay: TimeInterval {
        get { machine.holdDelay }
        set { machine.holdDelay = newValue }
    }

    var isShowing: Bool { machine.isShowing }

    func start() {
        guard monitors.isEmpty else { return }
        let flags: (NSEvent) -> Void = { [weak self] in self?.handleFlags($0) }
        let key: (NSEvent) -> Void = { [weak self] _ in self?.send(.otherInput) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        // Keys and clicks (e.g. ⌘-click to open a link in a new tab) are not part of the gesture.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown], handler: key) { monitors.append(m) }
        // Local monitors cover the rare case where Kanpe itself is active (e.g. its menu is open).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { key($0); return $0 }) { monitors.append(m) }
        Log.trigger.notice("Monitors started (\(self.monitors.count) installed, mode: \(self.machine.mode.rawValue, privacy: .public), accessibility trusted: \(AX.isTrusted))")
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        reset()
    }

    private func reset() {
        send(.otherInput)
    }

    private func handleFlags(_ event: NSEvent) {
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        defer { previousModifiers = mods }
        guard mods != previousModifiers else { return }
        Log.trigger.debug("flagsChanged: \(mods.rawValue, format: .hex) (was \(self.previousModifiers.rawValue, format: .hex))")

        if mods == .command, previousModifiers.isEmpty {
            send(.commandDown(event.timestamp))
        } else if mods.isEmpty, previousModifiers == .command {
            send(.commandUp(event.timestamp))
        } else {
            // Another modifier joined or left (⌘⇧, ⌥…): not our gesture.
            send(.otherInput)
        }
    }

    private func send(_ event: TriggerStateMachine.Event) {
        let effects = machine.handle(event)
        if !effects.isEmpty {
            Log.trigger.debug("\(String(describing: event), privacy: .public) → \(String(describing: effects), privacy: .public)")
        }
        for effect in effects {
            switch effect {
            case .begin:
                onBegin()
            case .scheduleShow(let delay):
                pending?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.pending = nil
                    self?.send(.timerFired)
                }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            case .cancelScheduledShow:
                pending?.cancel()
                pending = nil
            case .show:
                onShow()
            case .hide:
                onHide()
            }
        }
    }
}
