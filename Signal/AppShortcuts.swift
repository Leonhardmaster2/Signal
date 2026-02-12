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

// MARK: - View Latest Recording Intent

struct ViewLatestRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "View Latest Recording"
    static var description: IntentDescription = "Open your most recent recording in Signal"
    
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            UserDefaults.standard.set(true, forKey: "pendingViewLatestRecording")
        }
        
        try? await Task.sleep(for: .milliseconds(300))
        
        await MainActor.run {
            NotificationCenter.default.post(
                name: .viewLatestRecordingFromShortcut,
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - View All Recordings Intent

struct ViewAllRecordingsIntent: AppIntent {
    static var title: LocalizedStringResource = "View All Recordings"
    static var description: IntentDescription = "Open Signal to view all your recordings"
    
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        // Just opens the app to the main view
        return .result()
    }
}

// MARK: - App Shortcuts Provider

struct SignalShortcutsProvider: AppShortcutsProvider {
    @AppShortcutsBuilder
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
        AppShortcut(
            intent: ViewLatestRecordingIntent(),
            phrases: [
                "Show my latest recording in \(.applicationName)",
                "Open recent recording in \(.applicationName)",
                "View last recording in \(.applicationName)"
            ],
            shortTitle: "Latest Recording",
            systemImageName: "waveform.badge.magnifyingglass"
        )
        AppShortcut(
            intent: ViewAllRecordingsIntent(),
            phrases: [
                "Show all recordings in \(.applicationName)",
                "View my recordings in \(.applicationName)",
                "Open \(.applicationName) recordings"
            ],
            shortTitle: "All Recordings",
            systemImageName: "list.bullet"
        )
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Opens RecorderView and automatically starts recording
    static let startRecordingFromShortcut = Notification.Name("startRecordingFromShortcut")
    /// Opens the latest recording
    static let viewLatestRecordingFromShortcut = Notification.Name("viewLatestRecordingFromShortcut")
}
