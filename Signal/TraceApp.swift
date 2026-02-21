import SwiftUI
import SwiftData
import AVFoundation
import ActivityKit
import UserNotifications

@main
struct TraceApp: App {
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
                .onOpenURL { url in
                    handleIncomingURL(url)
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
    
    /// Handle incoming audio file or Trace package URLs from share sheet or file picker
    private func handleIncomingURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent.lowercased()
        
        // Check if it's a Trace package (.traceapp, .traceapp.zip, .traceaudio, .traceaudio.zip, .trace)
        let isTracePackage = ext == "traceapp" || ext == "traceaudio" || ext == "trace" || 
                             fileName.hasSuffix(".traceapp.zip") || fileName.hasSuffix(".traceaudio.zip")
        
        if isTracePackage {
            Task { @MainActor in
                let success = await TracePackageExporter.shared.importTracePackage(
                    from: url,
                    modelContext: sharedModelContainer.mainContext
                )
                if success {
                    NotificationCenter.default.post(
                        name: Notification.Name("tracePackageImported"),
                        object: nil
                    )
                }
            }
            return
        }
        
        // Check if it's an audio file
        let audioExtensions = ["m4a", "mp3", "wav", "aiff", "aif", "caf"]
        guard audioExtensions.contains(ext) else { return }
        
        // Store the URL for the app to process
        UserDefaults.standard.set(url.absoluteString, forKey: "pendingAudioImport")
        
        // Notify the app
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .importAudioFile,
                object: nil,
                userInfo: ["url": url]
            )
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
        // Only clean up recording activities if we're NOT currently recording (fresh launch)
        if !AudioRecorder.shared.isRecording {
            for activity in Activity<RecordingActivityAttributes>.activities {
                let finalState = RecordingActivityAttributes.ContentState(
                    isPaused: true,
                    timerStart: Date(),
                    pausedAt: 0,
                    recordingStatusText: L10n.recordingLive,
                    pausedStatusText: L10n.pausedLive
                )
                Task {
                    await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
                }
            }
        }

        // Always clean up orphaned playback activities on launch
        for activity in Activity<PlaybackActivityAttributes>.activities {
            let finalState = PlaybackActivityAttributes.ContentState(
                isPlaying: false,
                currentTime: 0,
                duration: 0,
                progress: 0
            )
            Task {
                await activity.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
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
    static let importAudioFile = Notification.Name("importAudioFile")
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
