import ActivityKit
import Foundation

/// Live Activity attributes for recording.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Whether recording is paused
        var isPaused: Bool
        /// Timer start date - iOS handles the actual counting
        var timerStart: Date
        /// Frozen time to display when paused
        var pausedAt: TimeInterval
    }

    /// Recording title (e.g., "Recording 3:45 PM")
    let title: String
}
