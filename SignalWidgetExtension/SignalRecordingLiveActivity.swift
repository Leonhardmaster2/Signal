import ActivityKit
import WidgetKit
import SwiftUI

struct SignalRecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock screen / notification banner view
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !context.state.isPaused)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.isPaused {
                        Image(systemName: "pause.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        // Pulsing recording dot
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    TimerView(state: context.state, style: .expanded)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    AnimatedWaveform(isPaused: context.state.isPaused)
                        .frame(height: 28)
                }
            } compactLeading: {
                // Animated waveform icon
                Image(systemName: "waveform")
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !context.state.isPaused)
            } compactTrailing: {
                if context.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                }
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !context.state.isPaused)
            }
        }
    }
}

// MARK: - Timer View

private struct TimerView: View {
    let state: RecordingActivityAttributes.ContentState
    let style: TimerStyle
    
    enum TimerStyle {
        case expanded
        case lockScreen
    }
    
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
        .font(style == .expanded ? .title.monospacedDigit() : .title3.monospacedDigit())
        .fontWeight(.medium)
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

// MARK: - Animated Waveform

private struct AnimatedWaveform: View {
    let isPaused: Bool
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: isPaused)) { timeline in
            Canvas { context, size in
                let barCount = 40
                let spacing: CGFloat = 3
                let barWidth = (size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                for i in 0..<barCount {
                    let x = CGFloat(i) * (barWidth + spacing)
                    
                    // Create organic wave motion using multiple sine waves
                    let phase1 = sin(time * 3.0 + Double(i) * 0.3) * 0.3
                    let phase2 = sin(time * 5.0 + Double(i) * 0.2) * 0.2
                    let phase3 = sin(time * 2.0 + Double(i) * 0.5) * 0.15
                    
                    let heightFactor = isPaused ? 0.15 : (0.35 + phase1 + phase2 + phase3)
                    let barHeight = max(3, size.height * CGFloat(heightFactor))
                    
                    let y = (size.height - barHeight) / 2
                    
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    
                    let opacity = isPaused ? 0.3 : 0.9
                    context.fill(path, with: .color(.white.opacity(opacity)))
                }
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Waveform icon
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !context.state.isPaused)

            // Status and waveform
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if context.state.isPaused {
                        Text("Paused")
                            .foregroundStyle(.white.opacity(0.5))
                    } else {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .foregroundStyle(.white)
                    }
                }
                .font(.subheadline.weight(.medium))
                
                AnimatedWaveform(isPaused: context.state.isPaused)
                    .frame(height: 20)
            }

            Spacer()

            // Timer
            TimerView(state: context.state, style: .lockScreen)
        }
        .padding()
        .activityBackgroundTint(.black)
    }
}
