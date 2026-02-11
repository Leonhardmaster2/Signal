import AppIntents
import SwiftUI

// MARK: - Start Recording Intent

struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description: IntentDescription = "Start a new recording in Signal"

    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Set a flag that persists across app launch
        // This handles the cold-start case where the notification might be missed
        await MainActor.run {
            UserDefaults.standard.set(true, forKey: "pendingShortcutRecording")
        }
        
        // Also post notification for warm-start case (app already running)
        // Add a small delay to ensure UI is ready to receive
        try? await Task.sleep(for: .milliseconds(300))
        
        await MainActor.run {
            NotificationCenter.default.post(
                name: .startRecordingFromShortcut,
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct SignalShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Record a meeting with \(.applicationName)",
                "Start \(.applicationName)",
                "Begin recording in \(.applicationName)",
                "Capture meeting with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "waveform"
        )
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Opens RecorderView and automatically starts recording
    static let startRecordingFromShortcut = Notification.Name("startRecordingFromShortcut")
}
