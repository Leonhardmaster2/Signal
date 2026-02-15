import AVFoundation
import ActivityKit
import UIKit

// MARK: - Audio Source Type

enum AudioSource: Equatable {
    case external  // Microphone (surroundings)
    
    var displayName: String {
        return "Microphone"
    }
    
    var icon: String {
        return "mic.fill"
    }
}

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
    var currentAudioSource: AudioSource = .external

    private var recorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private(set) var fileURL: URL?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?

    // Smoothing factor for amplitude
    private let smoothingFactor: Float = 0.35
    private var sampleCounter: Int = 0
    
    // Track if app is in foreground for metering optimization
    private var isInForeground = true

    // Live Activity
    private var liveActivity: Activity<RecordingActivityAttributes>?
    private var recordingStartDate: Date = .now
    private var liveActivityUpdateCount: Int = 0
    private var lastLiveActivityUpdate: Date = .distantPast
    private var pendingLiveActivityUpdate: Task<Void, Never>?

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

    func startRecording(source: AudioSource = .external) async throws {
        // Verify we have permission before trying to start
        let status = AVAudioApplication.shared.recordPermission
        guard status == .granted else {
            throw NSError(
                domain: "AudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission not authorized"]
            )
        }
        
        currentAudioSource = source
        let session = AVAudioSession.sharedInstance()
        
        // Deactivate first to clear any previous state
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        
        // Configure audio session for microphone recording
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        )
        
        // Activate the audio session
        try session.setActive(true, options: [])

        beginBackgroundTask()

        let filename = "trace_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = recordingsDirectory.appendingPathComponent(filename)
        fileURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,  // 44kHz studio-quality recording
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
    
    private func startInternalAudioRecording(url: URL) throws {
        // Setup audio engine for internal recording
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create audio file for writing
        audioFile = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        
        // Install tap on input node to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            do {
                try file.write(from: buffer)
            } catch {
                print("Failed to write audio buffer: \\(error)")
            }
        }
        
        // Start the engine
        try engine.start()
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
        
        // Stop audio engine if using internal recording
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            audioEngine = nil
            audioFile = nil
        }
        
        isRecording = false
        isPaused = false

        endLiveActivity()
        endBackgroundTask()

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return fileURL
    }

    func requestPermission() async -> Bool {
        // Check current permission status first
        let status = AVAudioApplication.shared.recordPermission
        
        switch status {
        case .granted:
            // Already have permission
            return true
        case .denied:
            // User previously denied
            return false
        case .undetermined:
            // Need to request permission
            if #available(iOS 17.0, *) {
                return await AVAudioApplication.requestRecordPermission()
            } else {
                return await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
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
        
        // Use main thread Timer for reliability in background audio mode
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.processMeteringTick()
        }
        // Ensure timer continues in background
        RunLoop.main.add(timer, forMode: .common)
        meteringTimer = timer
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
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
        
        // Do metering work if recording (not paused) - works in both foreground and background
        let shouldMeter = rec.isRecording
        
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
                
                // Update Live Activity every 2 ticks (~0.2 seconds / 5Hz) for smooth animation
                if self.sampleCounter % 2 == 0 {
                    self.updateLiveActivity()
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

    /// Compute per-bar height levels for the waveform visualization.
    /// Runs in the main app so the widget doesn't need TimelineView or Canvas.
    private func computeBarLevels(audioLevel: Double, time: Double, count: Int) -> [Double] {
        var levels = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let barIndex = Double(i)
            let normalizedPos = Double(i) / Double(max(count - 1, 1))
            let centerDist = abs(normalizedPos - 0.5) * 2.0
            let envelope = 1.0 - (centerDist * centerDist * 0.5)

            let t1 = time * 2.5 + barIndex * 0.4
            let t2 = time * 1.6 + barIndex * 0.6
            let t3 = time * 3.2 + barIndex * 0.2

            let wave = 0.3 + sin(t1) * 0.35 + cos(t2) * 0.25 + sin(t3) * 0.15
            let height = abs(wave) * envelope * max(0.25, min(1.0, audioLevel * 2.0))
            levels[i] = max(0.05, min(1.0, height))
        }
        return levels
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let title = "\(L10n.recordingLive) \(formatter.string(from: Date()))"

        let attributes = RecordingActivityAttributes(title: title)
        let state = RecordingActivityAttributes.ContentState(
            isPaused: false,
            timerStart: recordingStartDate,
            pausedAt: 0,
            audioLevel: 0.0,
            updateCount: 0,
            barLevels: computeBarLevels(audioLevel: 0.0, time: Date().timeIntervalSinceReferenceDate, count: 30),
            recordingStatusText: L10n.recordingLive,
            pausedStatusText: L10n.pausedLive
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
        
        // Throttle: ensure minimum 0.15s between updates to prevent system throttling
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastLiveActivityUpdate)
        guard timeSinceLastUpdate >= 0.15 else { return }
        
        lastLiveActivityUpdate = now
        liveActivityUpdateCount += 1

        let audioLevel = Double(smoothedAmplitude)
        let barLevels = computeBarLevels(
            audioLevel: audioLevel,
            time: now.timeIntervalSinceReferenceDate,
            count: 30
        )

        let state = RecordingActivityAttributes.ContentState(
            isPaused: isPaused,
            timerStart: recordingStartDate,
            pausedAt: currentTime,
            audioLevel: audioLevel,
            updateCount: liveActivityUpdateCount,
            barLevels: barLevels,
            recordingStatusText: L10n.recordingLive,
            pausedStatusText: L10n.pausedLive
        )

        // Cancel any pending update
        pendingLiveActivityUpdate?.cancel()
        
        // Create new update task
        pendingLiveActivityUpdate = Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }

        let state = RecordingActivityAttributes.ContentState(
            isPaused: false,
            timerStart: recordingStartDate,
            pausedAt: currentTime,
            audioLevel: Double(smoothedAmplitude),
            updateCount: liveActivityUpdateCount,
            barLevels: Array(repeating: 0.05, count: 30),
            recordingStatusText: L10n.recordingLive,
            pausedStatusText: L10n.pausedLive
        )

        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }
    
    /// End all Live Activities - used when app terminates or force quits
    func endAllLiveActivities() {
        let emptyBars = Array(repeating: 0.05, count: 30)

        // End the current activity if we have a reference
        if let activity = liveActivity {
            let state = RecordingActivityAttributes.ContentState(
                isPaused: false,
                timerStart: Date(),
                pausedAt: 0,
                audioLevel: 0.0,
                updateCount: 0,
                barLevels: emptyBars,
                recordingStatusText: L10n.recordingLive,
                pausedStatusText: L10n.pausedLive
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
                pausedAt: 0,
                audioLevel: 0.0,
                updateCount: 0,
                barLevels: emptyBars,
                recordingStatusText: L10n.recordingLive,
                pausedStatusText: L10n.pausedLive
            )
            Task {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Background Task

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TraceRecording") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
