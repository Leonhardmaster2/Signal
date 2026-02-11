import AVFoundation
import ActivityKit
import UIKit

@Observable
final class AudioRecorder: NSObject {
    static let shared = AudioRecorder()

    var isRecording = false
    var isPaused = false
    var currentTime: TimeInterval = 0
    var currentAmplitude: Float = 0
    var smoothedAmplitude: Float = 0
    var amplitudeHistory: [Float] = []
    var marks: [TimeInterval] = []

    private var recorder: AVAudioRecorder?
    private var meteringTimer: DispatchSourceTimer?
    private(set) var fileURL: URL?

    // Smoothing factor for amplitude
    private let smoothingFactor: Float = 0.35
    private var sampleCounter: Int = 0
    
    // Track if app is in foreground for metering optimization
    private var isInForeground = true

    // Live Activity
    private var liveActivity: Activity<RecordingActivityAttributes>?
    private var recordingStartDate: Date = .now

    // Audio session handling
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var willTerminateObserver: NSObjectProtocol?
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var willEnterForegroundObserver: NSObjectProtocol?

    // Background task
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        setupAppLifecycleObservers()
    }
    
    deinit {
        removeAppLifecycleObservers()
    }

    // MARK: - Recording Control

    func startRecording() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        )
        try session.setActive(true, options: [])

        beginBackgroundTask()

        let filename = "signal_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = recordingsDirectory.appendingPathComponent(filename)
        fileURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record()

        isRecording = true
        isPaused = false
        currentTime = 0
        currentAmplitude = 0
        smoothedAmplitude = 0
        amplitudeHistory = []
        marks = []
        sampleCounter = 0
        recordingStartDate = Date()

        startLiveActivity()
        setupAudioObservers()
        startMeteringTimer()
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        isPaused = true
        updateLiveActivity()
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        recorder?.record()
        isPaused = false
        // Adjust start date to account for pause duration
        let pauseDuration = currentTime
        recordingStartDate = Date().addingTimeInterval(-pauseDuration)
        updateLiveActivity()
    }

    func addMark() {
        guard isRecording else { return }
        marks.append(currentTime)
    }

    func stopRecording() -> URL? {
        stopMeteringTimer()
        removeAudioObservers()

        recorder?.stop()
        isRecording = false
        isPaused = false

        endLiveActivity()
        endBackgroundTask()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return fileURL
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func reset() {
        fileURL = nil
        currentTime = 0
        currentAmplitude = 0
        smoothedAmplitude = 0
        amplitudeHistory = []
        marks = []
        sampleCounter = 0
    }

    @MainActor
    func reactivateSessionIfNeeded() {
        guard isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        )
        try? session.setActive(true, options: [])

        if let rec = recorder {
            if isPaused {
                // Stay paused
            } else if !rec.isRecording {
                rec.record()
            }
            currentTime = rec.currentTime
        }

        updateLiveActivity()
        restartMeteringTimerIfNeeded()
    }

    // MARK: - Metering Timer

    private func startMeteringTimer() {
        stopMeteringTimer()
        
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        // Use slower rate in background to save CPU
        let interval = isInForeground ? (1.0 / 10.0) : 1.0 // 10Hz foreground, 1Hz background
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.processMeteringTick()
        }
        timer.resume()
        meteringTimer = timer
    }

    private func stopMeteringTimer() {
        meteringTimer?.cancel()
        meteringTimer = nil
    }

    private func restartMeteringTimerIfNeeded() {
        guard isRecording else { return }
        startMeteringTimer()
    }

    private func processMeteringTick() {
        guard let rec = recorder else { return }
        
        // Always update current time, even when paused
        let time = rec.currentTime
        
        // Only do metering work if recording (not paused) and in foreground
        let shouldMeter = rec.isRecording && isInForeground
        
        var power: Float = 0
        var linear: Float = 0
        
        if shouldMeter {
            rec.updateMeters()
            power = rec.averagePower(forChannel: 0)
            linear = max(0, min(1, (power + 50) / 50))
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentTime = time
            
            if shouldMeter {
                self.currentAmplitude = linear
                self.smoothedAmplitude = self.smoothedAmplitude * self.smoothingFactor
                    + linear * (1.0 - self.smoothingFactor)

                // Store waveform sample
                self.sampleCounter += 1
                if self.sampleCounter % 2 == 0 {
                    self.amplitudeHistory.append(self.smoothedAmplitude)
                }
            }
        }
    }

    // MARK: - Audio Session Observers

    private func setupAudioObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func removeAudioObservers() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }
    
    // MARK: - App Lifecycle Observers
    
    private func setupAppLifecycleObservers() {
        // Handle app termination - end Live Activity immediately
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillTerminate()
        }
        
        // Handle entering background - reduce CPU usage
        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        
        // Handle entering foreground - restore full metering
        willEnterForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
    }
    
    private func removeAppLifecycleObservers() {
        if let observer = willTerminateObserver {
            NotificationCenter.default.removeObserver(observer)
            willTerminateObserver = nil
        }
        if let observer = didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(observer)
            didEnterBackgroundObserver = nil
        }
        if let observer = willEnterForegroundObserver {
            NotificationCenter.default.removeObserver(observer)
            willEnterForegroundObserver = nil
        }
    }
    
    private func handleAppWillTerminate() {
        // Immediately end all Live Activities when app is terminated
        endAllLiveActivities()
    }
    
    private func handleDidEnterBackground() {
        isInForeground = false
        saveRecoveryCheckpoint()
        // Restart timer with slower background rate
        if isRecording {
            startMeteringTimer()
        }
    }
    
    private func handleWillEnterForeground() {
        isInForeground = true
        // Restart timer with faster foreground rate
        if isRecording {
            startMeteringTimer()
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            isPaused = true
            updateLiveActivity()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    try? AVAudioSession.sharedInstance().setActive(true, options: [])
                    recorder?.record()
                    isPaused = false
                    // Recalculate start date
                    recordingStartDate = Date().addingTimeInterval(-currentTime)
                    updateLiveActivity()
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isRecording else { return }
        // Just ensure session is active and recorder is running
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        if let rec = recorder, !rec.isRecording && !isPaused {
            rec.record()
        }
        if let rec = recorder {
            currentTime = rec.currentTime
        }
    }

    // MARK: - Recovery Checkpoint

    func saveRecoveryCheckpoint() {
        guard isRecording, let url = fileURL else {
            UserDefaults.standard.removeObject(forKey: "activeRecordingURL")
            return
        }
        UserDefaults.standard.set(url.path, forKey: "activeRecordingURL")
        UserDefaults.standard.set(currentTime, forKey: "activeRecordingTime")
        UserDefaults.standard.set(recordingStartDate.timeIntervalSince1970, forKey: "activeRecordingStartDate")
    }

    func clearRecoveryCheckpoint() {
        UserDefaults.standard.removeObject(forKey: "activeRecordingURL")
        UserDefaults.standard.removeObject(forKey: "activeRecordingTime")
        UserDefaults.standard.removeObject(forKey: "activeRecordingStartDate")
    }

    func checkForInterruptedRecording() -> (url: URL, duration: TimeInterval)? {
        guard let path = UserDefaults.standard.string(forKey: "activeRecordingURL") else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            clearRecoveryCheckpoint()
            return nil
        }
        let duration = UserDefaults.standard.double(forKey: "activeRecordingTime")
        return (url, duration)
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let title = "Recording \(formatter.string(from: Date()))"

        let attributes = RecordingActivityAttributes(title: title)
        let state = RecordingActivityAttributes.ContentState(
            isPaused: false,
            timerStart: recordingStartDate,
            pausedAt: 0
        )

        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    private func updateLiveActivity() {
        guard let activity = liveActivity else { return }

        let state = RecordingActivityAttributes.ContentState(
            isPaused: isPaused,
            timerStart: recordingStartDate,
            pausedAt: currentTime
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }

        let state = RecordingActivityAttributes.ContentState(
            isPaused: false,
            timerStart: recordingStartDate,
            pausedAt: currentTime
        )

        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }
    
    /// End all Live Activities - used when app terminates or force quits
    func endAllLiveActivities() {
        // End the current activity if we have a reference
        if let activity = liveActivity {
            let state = RecordingActivityAttributes.ContentState(
                isPaused: false,
                timerStart: Date(),
                pausedAt: 0
            )
            Task {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
            liveActivity = nil
        }
        
        // Also end any orphaned activities
        for activity in Activity<RecordingActivityAttributes>.activities {
            let state = RecordingActivityAttributes.ContentState(
                isPaused: false,
                timerStart: Date(),
                pausedAt: 0
            )
            Task {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Background Task

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SignalRecording") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
