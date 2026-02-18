import ActivityKit
import Foundation

/// Live Activity attributes for recording.
/// IMPORTANT: This file must be kept in sync with TraceWidgetExtension/RecordingActivityAttributes.swift
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Whether recording is paused
        var isPaused: Bool
        /// Timer start date - iOS handles the actual counting
        var timerStart: Date
        /// Frozen time to display when paused
        var pausedAt: TimeInterval
        /// Localized status text for "Recording" / "Paused" (passed from main app)
        var recordingStatusText: String
        var pausedStatusText: String
    }

    /// Recording title (e.g., "Recording 3:45 PM")
    let title: String
}

/// Live Activity attributes for audio playback.
/// IMPORTANT: This file must be kept in sync with TraceWidgetExtension/RecordingActivityAttributes.swift
struct PlaybackActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Whether audio is currently playing
        var isPlaying: Bool
        /// Current playback position in seconds
        var currentTime: TimeInterval
        /// Total duration in seconds
        var duration: TimeInterval
        /// Playback progress (0.0 to 1.0)
        var progress: Double
    }

    /// Recording title displayed in the Live Activity
    let title: String
}
