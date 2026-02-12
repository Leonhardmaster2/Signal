import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit
import UserNotifications

@main
struct SignalApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        try! ModelContainer(for: Recording.self)
    }()

    init() {
        // Immediately end any orphaned Live Activities on app launch
        // This handles force quit scenarios
        endOrphanedLiveActivities()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    await recoverInterruptedRecordingIfNeeded()
                    // Request notification permissions
                    await requestNotificationPermissions()
                }
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                AudioRecorder.shared.saveRecoveryCheckpoint()
            case .active:
                AudioRecorder.shared.clearRecoveryCheckpoint()
                // End any orphaned activities when becoming active
                // (handles cases where activities weren't properly cleaned up)
                if !AudioRecorder.shared.isRecording {
                    endOrphanedLiveActivities()
                }
            default:
                break
            }
        }
    }

    /// If the app was force-quit while recording, recover the partial audio file
    /// and save it as a recording so the user doesn't lose their data.
    private func recoverInterruptedRecordingIfNeeded() async {
        let recorder = AudioRecorder.shared
        guard let recovery = recorder.checkForInterruptedRecording() else { return }

        // Determine actual duration from the audio file if possible
        let asset = AVURLAsset(url: recovery.url)
        let duration: TimeInterval
        if let assetDuration = try? await asset.load(.duration) {
            duration = assetDuration.seconds
        } else {
            duration = recovery.duration
        }

        guard duration > 1.0 else {
            // Too short to be useful — clean up
            recorder.deleteFile(at: recovery.url)
            recorder.clearRecoveryCheckpoint()
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"

        // Use the saved start date if available, otherwise file creation date
        let startDate: Date
        let savedTimestamp = UserDefaults.standard.double(forKey: "activeRecordingStartDate")
        if savedTimestamp > 0 {
            startDate = Date(timeIntervalSince1970: savedTimestamp)
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: recovery.url.path)
            startDate = (attrs?[.creationDate] as? Date) ?? Date()
        }

        let recording = Recording(
            title: "Recovered \(formatter.string(from: startDate))",
            date: startDate,
            duration: duration,
            amplitudeSamples: [],
            audioFileName: recovery.url.lastPathComponent
        )

        let context = sharedModelContainer.mainContext
        context.insert(recording)
        try? context.save()

        recorder.clearRecoveryCheckpoint()
    }

    /// End any Live Activities that survived a force-quit.
    /// After a force-quit, the process is dead but the Live Activity can linger.
    private func endOrphanedLiveActivities() {
        // Only clean up if we're NOT currently recording (fresh launch)
        guard !AudioRecorder.shared.isRecording else { return }

        let activities = Activity<RecordingActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        
        for activity in activities {
            let finalState = RecordingActivityAttributes.ContentState(
                isPaused: false,
                timerStart: Date(),
                pausedAt: 0
            )
            let content = ActivityContent(state: finalState, staleDate: nil)
            Task {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
    }
    
    /// Request notification permissions for transcription completion alerts
    private func requestNotificationPermissions() async {
        let _ = await NotificationService.shared.requestAuthorization()
    }
}

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Show banner and play sound even when app is in foreground
        return [.banner, .sound]
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        
        if let recordingUIDString = userInfo["recordingUID"] as? String,
           let _ = UUID(uuidString: recordingUIDString) {
            // Post notification to navigate to the recording
            // The view can observe this to open the recording detail
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .openRecordingFromNotification,
                    object: nil,
                    userInfo: ["recordingUID": recordingUIDString]
                )
            }
        }
    }
}

extension Notification.Name {
    static let openRecordingFromNotification = Notification.Name("openRecordingFromNotification")
}

// MARK: - Root View (Handles Onboarding)

struct RootView: View {
    @State private var showOnboarding = !OnboardingManager.hasCompletedOnboarding
    
    var body: some View {
        ContentView()
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(isPresented: $showOnboarding)
            }
    }
}
