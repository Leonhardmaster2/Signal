import ActivityKit
import WidgetKit
import SwiftUI

struct TraceRecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.center) {
                    ExpandedWaveform(state: context.state)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .padding(.horizontal, 16)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        TimerView(state: context.state)
                        Spacer()
                    }
                }
            } compactLeading: {
                HStack(spacing: 3) {
                    if context.state.isPaused {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 6, height: 6)
                    }

                    CompactWaveform(state: context.state)
                        .frame(width: 20, height: 12)
                }
            } compactTrailing: {
                TimerView(state: context.state)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()
            } minimal: {
                if context.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }
}

// MARK: - Timer View

private struct TimerView: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isPaused {
                Text(formatTime(state.pausedAt))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
                    .foregroundStyle(.white)
            }
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText())
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 { return String(format: "%d:%02d:%02d", hrs, mins, secs) }
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Animated Waveform Bar (GPU-driven via KeyframeAnimator)

/// A single bar that animates its height using KeyframeAnimator.
/// The animation runs entirely on the render server — no extension wake-ups needed.
private struct AnimatedWaveBar: View {
    let index: Int
    let barCount: Int
    let maxHeight: CGFloat
    let cornerRadius: CGFloat
    let color: Color
    let activeOpacity: Double
    let pausedOpacity: Double
    let isPaused: Bool

    // Per-bar timing: use prime-ish multipliers so bars never sync up
    private var seed: Double { Double(index) }
    private var cycleDuration: Double {
        let bases = [0.7, 0.85, 0.95, 1.1, 0.8, 1.0, 0.75, 0.9, 1.05, 0.65]
        return bases[index % bases.count]
    }

    // Envelope: center bars are taller, edges are shorter (natural voice shape)
    private var envelope: Double {
        let normalizedPos = Double(index) / Double(max(barCount - 1, 1))
        let centerDist = abs(normalizedPos - 0.5) * 2.0
        return 1.0 - (centerDist * centerDist * 0.4)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(color.opacity(isPaused ? pausedOpacity : activeOpacity))
            .frame(height: isPaused ? max(2, maxHeight * 0.05) : nil)
            .keyframeAnimator(
                initialValue: AnimationValues(scale: 0.15),
                repeating: !isPaused
            ) { content, value in
                content.frame(height: max(2, maxHeight * value.scale * envelope))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    // 4-point cycle with unique heights per bar
                    let h1 = 0.3 + sin(seed * 1.7) * 0.25
                    let h2 = 0.8 + cos(seed * 2.3) * 0.2
                    let h3 = 0.45 + sin(seed * 0.9) * 0.3
                    let h4 = 0.65 + cos(seed * 1.4) * 0.25
                    CubicKeyframe(h2, duration: cycleDuration * 0.28)
                    CubicKeyframe(h1, duration: cycleDuration * 0.22)
                    CubicKeyframe(h4, duration: cycleDuration * 0.3)
                    CubicKeyframe(h3, duration: cycleDuration * 0.2)
                }
            }
    }
}

private struct AnimationValues {
    var scale: Double
}

// MARK: - Expanded Dynamic Island Waveform (30 bars)

private struct ExpandedWaveform: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<30, id: \.self) { i in
                AnimatedWaveBar(
                    index: i,
                    barCount: 30,
                    maxHeight: 60,
                    cornerRadius: 1.5,
                    color: .white,
                    activeOpacity: 0.85,
                    pausedOpacity: 0.2,
                    isPaused: state.isPaused
                )
            }
        }
        .frame(height: 60)
    }
}

// MARK: - Compact Waveform (4 bars, phone call style)

private struct CompactWaveform: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                AnimatedWaveBar(
                    index: i * 7, // spread across the seed space for variety
                    barCount: 4,
                    maxHeight: 12,
                    cornerRadius: 1.5,
                    color: .white,
                    activeOpacity: 0.95,
                    pausedOpacity: 0.3,
                    isPaused: state.isPaused
                )
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !context.state.isPaused)
            }

            VStack(alignment: .leading, spacing: 4) {
                if context.state.isPaused {
                    Text(context.state.pausedStatusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    Text(context.state.recordingStatusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }

                TimerView(state: context.state)
                    .font(.system(size: 32, weight: .thin, design: .rounded))
                    .monospacedDigit()
            }

            Spacer()

            LockScreenWaveform(state: context.state)
                .frame(width: 80, height: 36)
        }
        .padding(16)
        .activityBackgroundTint(.black)
    }
}

// MARK: - Lock Screen Waveform (15 bars, red)

private struct LockScreenWaveform: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<15, id: \.self) { i in
                AnimatedWaveBar(
                    index: i * 2, // spread seeds for visual variety
                    barCount: 15,
                    maxHeight: 36,
                    cornerRadius: 1,
                    color: .red,
                    activeOpacity: 0.85,
                    pausedOpacity: 0.25,
                    isPaused: state.isPaused
                )
            }
        }
        .frame(height: 36)
    }
}

// MARK: - ═══════════════════════════════════════════════
// MARK: - Playback Live Activity (Spotify-style)
// MARK: - ═══════════════════════════════════════════════

struct TracePlaybackLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            PlaybackLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 8) {
                        Text(context.attributes.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        PlaybackProgressBar(progress: context.state.progress)
                            .frame(height: 4)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 16)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(playbackFormatTime(context.state.currentTime))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))

                        Spacer()

                        Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)

                        Spacer()

                        Text("-" + playbackFormatTime(context.state.duration - context.state.currentTime))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(playbackFormatTime(context.state.currentTime))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Playback Lock Screen View

private struct PlaybackLockScreenView: View {
    let context: ActivityViewContext<PlaybackActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Play/Pause icon
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .offset(x: context.state.isPlaying ? 0 : 1.5)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // Progress bar
                PlaybackProgressBar(progress: context.state.progress)
                    .frame(height: 4)

                // Time labels
                HStack {
                    Text(playbackFormatTime(context.state.currentTime))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))

                    Spacer()

                    Text("-" + playbackFormatTime(context.state.duration - context.state.currentTime))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(.black)
    }
}

// MARK: - Progress Bar

private struct PlaybackProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.15))

                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.9))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, progress)))))
            }
        }
    }
}

// MARK: - Playback Time Formatter

private func playbackFormatTime(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hrs = total / 3600
    let mins = (total % 3600) / 60
    let secs = total % 60
    if hrs > 0 { return String(format: "%d:%02d:%02d", hrs, mins, secs) }
    return String(format: "%d:%02d", mins, secs)
}
