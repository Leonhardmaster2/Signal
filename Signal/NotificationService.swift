import Foundation
import UserNotifications
import UIKit

/// Service for handling local notifications in the Signal app
final class NotificationService {
    static let shared = NotificationService()
    
    // MARK: - Notification Identifiers
    
    enum NotificationCategory: String {
        case transcriptionComplete = "TRANSCRIPTION_COMPLETE"
        case transcriptionFailed = "TRANSCRIPTION_FAILED"
        case summarizationComplete = "SUMMARIZATION_COMPLETE"
    }
    
    enum NotificationAction: String {
        case view = "VIEW_ACTION"
        case dismiss = "DISMISS_ACTION"
    }
    
    private init() {
        setupNotificationCategories()
    }
    
    // MARK: - Authorization
    
    /// Request notification permissions from the user
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
    
    // MARK: - Notification Categories Setup
    
    private func setupNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: NotificationAction.view.rawValue,
            title: "View",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss.rawValue,
            title: "Dismiss",
            options: [.destructive]
        )
        
        let transcriptionCategory = UNNotificationCategory(
            identifier: NotificationCategory.transcriptionComplete.rawValue,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let failedCategory = UNNotificationCategory(
            identifier: NotificationCategory.transcriptionFailed.rawValue,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let summarizationCategory = UNNotificationCategory(
            identifier: NotificationCategory.summarizationComplete.rawValue,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            transcriptionCategory,
            failedCategory,
            summarizationCategory
        ])
    }
    
    // MARK: - Send Notifications
    
    /// Send a notification when transcription completes successfully
    func notifyTranscriptionComplete(
        recordingTitle: String,
        recordingUID: UUID,
        detectedLanguage: String? = nil,
        wasOnDevice: Bool = false
    ) {
        // Only send notification if app is in background
        guard UIApplication.shared.applicationState != .active else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Transcription Complete"
        
        var body = "\"\(recordingTitle)\" has been transcribed"
        if let language = detectedLanguage, let languageName = languageDisplayName(for: language) {
            body += " (\(languageName))"
        }
        body += "."
        
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.transcriptionComplete.rawValue
        content.userInfo = ["recordingUID": recordingUID.uuidString]
        
        // Add a thread identifier to group notifications per recording
        content.threadIdentifier = recordingUID.uuidString
        
        let request = UNNotificationRequest(
            identifier: "transcription-\(recordingUID.uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Send a notification when transcription fails
    func notifyTranscriptionFailed(
        recordingTitle: String,
        recordingUID: UUID,
        errorMessage: String
    ) {
        // Only send notification if app is in background
        guard UIApplication.shared.applicationState != .active else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Transcription Failed"
        content.body = "\"\(recordingTitle)\" could not be transcribed: \(errorMessage)"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.transcriptionFailed.rawValue
        content.userInfo = ["recordingUID": recordingUID.uuidString]
        content.threadIdentifier = recordingUID.uuidString
        
        let request = UNNotificationRequest(
            identifier: "transcription-failed-\(recordingUID.uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Send a notification when summarization completes
    func notifySummarizationComplete(
        recordingTitle: String,
        recordingUID: UUID,
        oneLiner: String? = nil,
        wasOnDevice: Bool = false
    ) {
        // Only send notification if app is in background
        guard UIApplication.shared.applicationState != .active else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Summary Ready"
        
        if let summary = oneLiner, !summary.isEmpty {
            content.body = summary
        } else {
            content.body = "\"\(recordingTitle)\" has been summarized."
        }
        
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.summarizationComplete.rawValue
        content.userInfo = ["recordingUID": recordingUID.uuidString]
        content.threadIdentifier = recordingUID.uuidString
        
        let request = UNNotificationRequest(
            identifier: "summarization-\(recordingUID.uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Send a combined notification when both transcription and summarization complete
    func notifyProcessingComplete(
        recordingTitle: String,
        recordingUID: UUID,
        oneLiner: String? = nil,
        detectedLanguage: String? = nil
    ) {
        // Only send notification if app is in background
        guard UIApplication.shared.applicationState != .active else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "✓ \(recordingTitle)"
        
        if let summary = oneLiner, !summary.isEmpty {
            content.body = summary
        } else {
            var body = "Transcription and summary ready"
            if let language = detectedLanguage, let languageName = languageDisplayName(for: language) {
                body += " (\(languageName))"
            }
            content.body = body
        }
        
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.transcriptionComplete.rawValue
        content.userInfo = ["recordingUID": recordingUID.uuidString]
        content.threadIdentifier = recordingUID.uuidString
        
        // Use interruptionLevel for time-sensitive delivery
        content.interruptionLevel = .timeSensitive
        
        let request = UNNotificationRequest(
            identifier: "complete-\(recordingUID.uuidString)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func languageDisplayName(for code: String) -> String? {
        OnDeviceTranscriptionService.commonLanguages.first { $0.code == code }?.name
    }
    
    /// Remove pending notifications for a recording
    func cancelNotifications(for recordingUID: UUID) {
        let identifiers = [
            "transcription-\(recordingUID.uuidString)",
            "transcription-failed-\(recordingUID.uuidString)",
            "summarization-\(recordingUID.uuidString)",
            "complete-\(recordingUID.uuidString)"
        ]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
