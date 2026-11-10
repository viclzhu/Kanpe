import Foundation

/// How the panel is summoned.
public enum TriggerMode: String, CaseIterable, Sendable {
    /// Hold ⌘ alone for `holdDelay`.
    case hold
    /// Tap ⌘, then press it again and keep holding.
    case doubleTapHold

    public var title: String {
        switch self {
        case .hold: return "Hold ⌘"
        case .doubleTapHold: return "Press ⌘ Twice and Hold"
        }
    }
}

/// Pure state machine for the activation gesture. The caller feeds it input events with
/// timestamps and performs the returned effects (start a timer, show, hide). Keeping it free of
/// AppKit makes the timing rules testable.
///
/// Input is reduced to three kinds of events:
/// - `commandDown` / `commandUp`: ⌘ became the only modifier held / was released with nothing else held.
/// - `otherInput`: any other key or modifier change. This always cancels, so normal shortcuts
///   (⌘C, ⌘Tab, ⌘⇧…) never trigger or keep the panel open.
public struct TriggerStateMachine {
    public enum Event: Equatable {
        case commandDown(TimeInterval)
        case commandUp(TimeInterval)
        case otherInput
        /// The timer requested by `.scheduleShow` fired.
        case timerFired
    }

    public enum Effect: Equatable {
        /// Start gathering content (the gesture is underway and likely to complete).
        case begin
        case scheduleShow(after: TimeInterval)
        case cancelScheduledShow
        case show
        case hide
    }

    enum State: Equatable {
        case idle
        case firstPress(at: TimeInterval)
        case waitingForSecondPress(releasedAt: TimeInterval)
        case armed
        case showing
    }

    public var mode: TriggerMode
    /// Hold mode: how long ⌘ must be held.
    public var holdDelay: TimeInterval
    /// Double-tap mode: the first tap must be released within this time…
    public var maxTapDuration: TimeInterval = 0.3
    /// …and the second press must follow within this time…
    public var maxTapGap: TimeInterval = 0.4
    /// …and then be held this long (short, just enough to tell a hold from a triple tap).
    public var secondPressHoldDelay: TimeInterval = 0.15

    private(set) var state: State = .idle
    public var isShowing: Bool { state == .showing }

    public init(mode: TriggerMode, holdDelay: TimeInterval) {
        self.mode = mode
        self.holdDelay = holdDelay
    }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch (state, event) {
        // Anything other than a clean ⌘ press/release cancels whatever is in progress.
        case (.showing, .otherInput), (.showing, .commandUp):
            state = .idle
            return [.hide]
        case (.armed, .otherInput), (.armed, .commandUp):
            state = .idle
            return [.cancelScheduledShow]
        case (_, .otherInput):
            state = .idle
            return []

        case (.armed, .timerFired):
            state = .showing
            return [.show]
        case (_, .timerFired):
            return [] // stale timer

        case (.idle, .commandDown(let t)):
            switch mode {
            case .hold:
                return arm(after: holdDelay)
            case .doubleTapHold:
                state = .firstPress(at: t)
                return []
            }

        case (.firstPress(let pressedAt), .commandUp(let t)):
            state = t - pressedAt <= maxTapDuration ? .waitingForSecondPress(releasedAt: t) : .idle
            return []

        case (.waitingForSecondPress(let releasedAt), .commandDown(let t)):
            if t - releasedAt <= maxTapGap {
                return arm(after: secondPressHoldDelay)
            }
            // Too slow: treat this press as a new first tap.
            state = .firstPress(at: t)
            return []

        default:
            return []
        }
    }

    private mutating func arm(after delay: TimeInterval) -> [Effect] {
        state = .armed
        return [.begin, .scheduleShow(after: delay)]
    }
}
