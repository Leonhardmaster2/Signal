import AVFoundation
import Combine
import MediaPlayer
import ActivityKit

@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var progress: CGFloat = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var isSeeking = false

    // Now Playing metadata
    private var trackTitle: String = ""
    private var hasSetupCommandCenter = false

    // Live Activity
    private var liveActivity: Activity<PlaybackActivityAttributes>?
    private var lastLiveActivityUpdate: Date = .distantPast
    private var liveActivityUpdateCount = 0

    // Lifecycle observers
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var willEnterForegroundObserver: NSObjectProtocol?
    private var willTerminateObserver: NSObjectProtocol?

    override init() {
        super.init()
        setupLifecycleObservers()
    }

    func load(url: URL, title: String = "") {
        stop()

        trackTitle = title

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.enableRate = true

            duration = player?.duration ?? 0
            currentTime = 0
            progress = 0

            setupRemoteCommandCenter()
            updateNowPlayingInfo()
        } catch {
            print("AudioPlayer load error: \(error)")
        }
    }

    func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
        startTimer()
        updateNowPlayingInfo()
        startPlaybackLiveActivity()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
        updateNowPlayingInfo()
        updatePlaybackLiveActivity()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to fraction: CGFloat) {
        guard let player = player else { return }

        let targetTime = Double(fraction) * duration

        // Clamp to valid range
        let clampedTime = max(0, min(duration - 0.01, targetTime))

        // Update immediately for responsive UI
        currentTime = clampedTime
        progress = fraction

        // Apply to player
        player.currentTime = clampedTime

        // If we were playing, continue playing
        if isPlaying && !player.isPlaying {
            player.play()
        }

        updateNowPlayingInfo()
        updatePlaybackLiveActivity()
    }

    func stop() {
        player?.stop()
        player = nil

        isPlaying = false
        currentTime = 0
        progress = 0
        stopTimer()
        clearNowPlayingInfo()
        endPlaybackLiveActivity()
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }

            // Update time from player
            self.currentTime = player.currentTime
            self.duration = player.duration

            // Calculate progress
            if self.duration > 0 {
                self.progress = CGFloat(self.currentTime / self.duration)
            }

            // Throttled Live Activity updates (~5Hz = every 6th tick of 30fps)
            self.liveActivityUpdateCount += 1
            if self.liveActivityUpdateCount % 6 == 0 {
                self.updatePlaybackLiveActivity()
            }

            // Check if finished
            if !player.isPlaying && self.isPlaying {
                self.isPlaying = false
                self.stopTimer()
                self.clearNowPlayingInfo()
                self.endPlaybackLiveActivity()
            }
        }
        // Use .common mode so timer fires during tracking (scrolling) and in background
        RunLoop.current.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.progress = 0
            self.stopTimer()
            self.clearNowPlayingInfo()
            self.endPlaybackLiveActivity()
        }
    }

    // MARK: - Now Playing Info Center

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: trackTitle.isEmpty ? "Trace Audio" : trackTitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        info[MPMediaItemPropertyArtist] = "Trace"
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        guard !hasSetupCommandCenter else { return }
        hasSetupCommandCenter = true

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let fraction = CGFloat(posEvent.positionTime / self.duration)
            self.seek(to: fraction)
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let newFraction = min(1.0, CGFloat((self.currentTime + 15) / self.duration))
            self.seek(to: newFraction)
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let newFraction = max(0, CGFloat((self.currentTime - 15) / self.duration))
            self.seek(to: newFraction)
            return .success
        }
    }

    private func teardownRemoteCommandCenter() {
        guard hasSetupCommandCenter else { return }
        hasSetupCommandCenter = false

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
    }

    // MARK: - Playback Live Activity

    private func startPlaybackLiveActivity() {
        // Only start if not already active
        guard liveActivity == nil else {
            updatePlaybackLiveActivity()
            return
        }

        let attributes = PlaybackActivityAttributes(title: trackTitle.isEmpty ? "Trace Audio" : trackTitle)
        let state = PlaybackActivityAttributes.ContentState(
            isPlaying: true,
            currentTime: currentTime,
            duration: duration,
            progress: duration > 0 ? Double(currentTime / duration) : 0
        )

        do {
            liveActivity = try Activity<PlaybackActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            print("Failed to start playback Live Activity: \(error)")
        }
    }

    private func updatePlaybackLiveActivity() {
        guard let activity = liveActivity else { return }

        // Throttle to minimum 0.15s between updates
        let now = Date()
        guard now.timeIntervalSince(lastLiveActivityUpdate) >= 0.15 else { return }
        lastLiveActivityUpdate = now

        let state = PlaybackActivityAttributes.ContentState(
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            progress: duration > 0 ? Double(currentTime / duration) : 0
        )

        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endPlaybackLiveActivity() {
        guard let activity = liveActivity else { return }

        let finalState = PlaybackActivityAttributes.ContentState(
            isPlaying: false,
            currentTime: 0,
            duration: duration,
            progress: 0
        )

        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        liveActivity = nil
    }

    // MARK: - App Lifecycle

    private func setupLifecycleObservers() {
        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Audio continues playing via Now Playing session.
            // Update Now Playing info so Control Center shows current state.
            self?.updateNowPlayingInfo()
        }

        willEnterForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let player = self.player else { return }
            // Sync state from player (it may have finished or been interrupted)
            self.currentTime = player.currentTime
            self.isPlaying = player.isPlaying
            if self.duration > 0 {
                self.progress = CGFloat(self.currentTime / self.duration)
            }
            if self.isPlaying {
                self.startTimer()
            } else {
                self.stopTimer()
            }
            self.updateNowPlayingInfo()
        }

        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.endPlaybackLiveActivity()
            self?.clearNowPlayingInfo()
            self?.teardownRemoteCommandCenter()
        }
    }

    // MARK: - Formatters

    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 { return String(format: "%d:%02d:%02d", hrs, mins, secs) }
        return String(format: "%d:%02d", mins, secs)
    }

    deinit {
        if let obs = didEnterBackgroundObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = willEnterForegroundObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = willTerminateObserver { NotificationCenter.default.removeObserver(obs) }
        timer?.invalidate()
        player?.stop()
        teardownRemoteCommandCenter()
        clearNowPlayingInfo()
    }
}
