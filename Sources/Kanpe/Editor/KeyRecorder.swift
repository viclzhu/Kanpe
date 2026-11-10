import AppKit
import SwiftUI
import KanpeCore

/// Captures key presses into pack notation. Press one chord ("⇧⌘P") or a sequence
/// ("G" then "I"); recording stops after a short pause or when the button is clicked again.
@MainActor
final class KeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var chords: [String] = []

    /// Only one field records at a time.
    private static weak var active: KeyRecorder?
    private var monitor: Any?
    private var idleTimer: Timer?
    private var onFinish: ((String) -> Void)?
    private let idleTimeout: TimeInterval = 1.4

    func toggle(onFinish: @escaping (String) -> Void) {
        isRecording ? stop(commit: true) : start(onFinish: onFinish)
    }

    func start(onFinish: @escaping (String) -> Void) {
        Self.active?.stop(commit: true)
        Self.active = self
        self.onFinish = onFinish
        chords = []
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }
            self.record(event)
            return nil // swallow: recorded keys shouldn't type into fields or trigger menu items
        }
    }

    func stop(commit: Bool) {
        guard isRecording else { return }
        isRecording = false
        idleTimer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if commit, !chords.isEmpty { onFinish?(chords.joined(separator: " ")) }
        onFinish = nil
        if Self.active === self { Self.active = nil }
    }

    private func record(_ event: NSEvent) {
        let flags = event.modifierFlags
        var mods: KeyRecording.Modifiers = []
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        guard let chord = KeyRecording.notation(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: mods)
        else { return }
        chords.append(chord)
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop(commit: true) }
        }
    }
}

/// Text field for key notation, with a live keycap preview and a record button.
struct KeyField: View {
    @Binding var keys: String
    @StateObject private var recorder = KeyRecorder()

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if recorder.isRecording {
                    HStack(spacing: 5) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text(recorder.chords.isEmpty ? "Press keys…" : recorder.chords.joined(separator: " "))
                            .foregroundStyle(recorder.chords.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.red.opacity(0.5)))
                } else {
                    TextField("g i, cmd+k…", text: $keys)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .font(.system(.callout, design: .monospaced))
            .frame(width: 130)

            Button {
                recorder.toggle { keys = $0 }
            } label: {
                Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                    .foregroundStyle(recorder.isRecording ? Color.red : .secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)
            .help(recorder.isRecording ? "Stop recording" : "Record: press a key, a combination, or a sequence like G then I")

            KeysView(alternatives: KeyNotation.parseAlternatives(recorder.isRecording ? recorder.chords.joined(separator: " ") : keys))
                .frame(width: 140, alignment: .trailing)
                .opacity(keys.isEmpty && !recorder.isRecording ? 0 : 1)
        }
        .onDisappear { recorder.stop(commit: true) }
    }
}
