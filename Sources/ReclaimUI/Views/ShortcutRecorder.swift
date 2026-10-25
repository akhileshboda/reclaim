import AppKit
import SwiftUI

/// Click, then press the new key combination. Escape cancels; the clear button removes the
/// shortcut. Combinations that would hijack standard shortcuts are rejected with an explanation.
public struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @Binding var problem: String?
    @State private var isRecording = false
    @State private var monitor: Any?

    public init(shortcut: Binding<Shortcut?>, problem: Binding<String?>) {
        _shortcut = shortcut
        _problem = problem
    }

    public var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Type Shortcut…" : (shortcut?.displayString ?? "Record Shortcut"))
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .accessibilityLabel(isRecording ? "Recording. Type the new shortcut, or press Escape to cancel." : "Shortcut: \(shortcut?.accessibilityLabel ?? "none")")
            .accessibilityHint("Click to record a new shortcut")
            if shortcut != nil, !isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove Shortcut")
                .accessibilityLabel("Remove shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        problem = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }
            let modifiers = event.modifierFlags.intersection(Shortcut.relevantModifiers)
            guard let key = event.charactersIgnoringModifiers, !key.isEmpty else { return nil }
            if let reason = Shortcut.problem(modifiers: modifiers, key: key) {
                NSSound.beep()
                problem = reason
                return nil
            }
            problem = nil
            shortcut = Shortcut(keyCode: event.keyCode, modifiers: modifiers, key: key)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
