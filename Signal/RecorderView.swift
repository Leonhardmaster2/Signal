import SwiftUI
import SwiftData

// MARK: - Recorder (The Interferometer)

struct RecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private var recorder = AudioRecorder.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var phase: CGFloat = 0
    @State private var displayAmplitude: CGFloat = 0.05
    @State private var permissionDenied = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var savedRecording: Recording?
    @State private var showOverview = false
    @State private var showDiscardAlert = false
    @State private var meetingNotes = ""
    @State private var showNotesEditor = false
    @State private var hasAutoStarted = false

    /// When true, recording starts automatically when the view appears
    private let autoStart: Bool

    init(autoStart: Bool = false) {
        self.autoStart = autoStart
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 16)
                .padding(.horizontal, AppLayout.horizontalPadding)

            Spacer()

            WaveVisualizerView(
                isRecording: recorder.isRecording,
                isPaused: recorder.isPaused,
                amplitude: CGFloat(recorder.smoothedAmplitude)
            )
            .frame(height: 200)
            .padding(.horizontal, 8)

            Spacer()

            timeDisplay
                .padding(.bottom, 32)

            marksDisplay
                .padding(.bottom, 24)
                .padding(.horizontal, AppLayout.horizontalPadding)

            controls
                .padding(.bottom, 48)
                .padding(.horizontal, AppLayout.horizontalPadding)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .alert("Recording Error", isPresented: $permissionDenied) {
            if errorMessage.contains("not authorized") || errorMessage.contains("permission") {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { dismiss() }
            } else {
                Button("OK", role: .cancel) { dismiss() }
            }
        } message: {
            Text(errorMessage.isEmpty ? "Signal needs microphone access to record. Enable it in Settings." : errorMessage)
        }
        .alert("Discard Recording?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                discardAndDismiss()
            }
            Button("Keep Recording", role: .cancel) { }
        } message: {
            Text("This recording will be permanently deleted.")
        }
        .sheet(isPresented: $showOverview, onDismiss: { dismiss() }) {
            if let recording = savedRecording {
                RecordingOverviewSheet(recording: recording)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                // App returned to foreground - sync recorder state
                recorder.reactivateSessionIfNeeded()
            case .background:
                // App going to background - save checkpoint in case of termination
                if recorder.isRecording {
                    recorder.saveRecoveryCheckpoint()
                }
            case .inactive:
                // Transitional state - no action needed
                break
            @unknown default:
                break
            }
        }
        .sheet(isPresented: $showNotesEditor) {
            MeetingNotesSheet(notes: $meetingNotes)
        }
        .onAppear {
            if autoStart && !hasAutoStarted && !recorder.isRecording {
                hasAutoStarted = true
                startRecording()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                if recorder.isRecording {
                    showDiscardAlert = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.gray)
            }

            Spacer()

            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .opacity(recorder.isPaused ? 0.25 : 1.0)

                    Text(recorder.isPaused ? "PAUSED" : "RECORDING")
                        .font(AppFont.mono(size: 11, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(.white)
                        .opacity(recorder.isPaused ? 0.25 : 1.0)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Spacer()

            Color.clear.frame(width: 16, height: 16)
        }
    }

    // MARK: - Time Display

    private var timeDisplay: some View {
        VStack(spacing: 4) {
            Text(recorder.currentTime.formattedPadded)
                .font(AppFont.mono(size: 48, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())

            if !recorder.marks.isEmpty {
                Text("\(recorder.marks.count) MARK\(recorder.marks.count == 1 ? "" : "S")")
                    .font(AppFont.mono(size: 11, weight: .medium))
                    .kerning(1.5)
                    .foregroundStyle(.gray)
            }
        }
    }

    // MARK: - Marks

    @ViewBuilder
    private var marksDisplay: some View {
        if !recorder.marks.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(recorder.marks.enumerated()), id: \.offset) { _, mark in
                        HStack(spacing: 4) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 8))
                            Text(mark.formattedPadded)
                                .font(AppFont.mono(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassCard(radius: 100)
                    }
                }
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 24) {
            if recorder.isRecording {
                // MARK button
                Button {
                    recorder.addMark()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    glassControl(icon: "flag.fill", label: "MARK")
                }

                // NOTES button
                Button {
                    showNotesEditor = true
                } label: {
                    glassControl(icon: "note.text", label: "NOTES")
                }

                // PAUSE / RESUME button
                Button {
                    if recorder.isPaused {
                        recorder.resumeRecording()
                    } else {
                        recorder.pauseRecording()
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    glassControl(
                        icon: recorder.isPaused ? "play.fill" : "pause.fill",
                        label: recorder.isPaused ? "RESUME" : "PAUSE"
                    )
                }

                // CUT (stop) button
                Button {
                    saveAndDismiss()
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 56, height: 56)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black)
                                .frame(width: 18, height: 18)
                        }

                        Text("CUT")
                            .font(AppFont.mono(size: 9, weight: .medium))
                            .kerning(1.2)
                            .foregroundStyle(.gray)
                    }
                }
                .disabled(isSaving)
            } else {
                // RECORD button
                Button {
                    startRecording()
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        }

                        Text("RECORD")
                            .font(AppFont.mono(size: 9, weight: .medium))
                            .kerning(1.2)
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        .animation(.easeInOut(duration: 0.2), value: recorder.isPaused)
    }

    /// Glass circle control used for MARK and PAUSE/RESUME buttons
    private func glassControl(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)

                Circle()
                    .stroke(Color.glassBorder, lineWidth: AppLayout.glassBorderWidth)
                    .frame(width: 56, height: 56)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text(label)
                .font(AppFont.mono(size: 9, weight: .medium))
                .kerning(1.2)
                .foregroundStyle(.gray)
        }
    }

    // MARK: - Actions

    private func startRecording() {
        // Reset immediately so the time display shows 00:00 right away
        recorder.reset()
        Task {
            let granted = await recorder.requestPermission()
            guard granted else {
                errorMessage = "Microphone access is required to record. Please enable it in Settings."
                permissionDenied = true
                return
            }
            do {
                try await recorder.startRecording(source: .external)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                print("Failed to start recording: \(error)")
                // Provide a more helpful error message
                if error.localizedDescription.contains("not authorized") {
                    errorMessage = "Microphone access is required. Please enable it in Settings."
                } else {
                    errorMessage = "Failed to start recording: \(error.localizedDescription). Please try again or check your device's microphone."
                }
                permissionDenied = true
            }
        }
    }

    private func saveAndDismiss() {
        isSaving = true
        guard let fileURL = recorder.stopRecording() else {
            dismiss()
            return
        }

        let recording = Recording(
            title: generateTitle(),
            date: Date(),
            duration: recorder.currentTime,
            amplitudeSamples: recorder.amplitudeHistory,
            audioFileName: fileURL.lastPathComponent
        )
        recording.marks = recorder.marks
        if !meetingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recording.notes = meetingNotes
        }

        modelContext.insert(recording)
        recorder.reset()

        savedRecording = recording
        showOverview = true
    }

    private func discardAndDismiss() {
        if let url = recorder.stopRecording() {
            recorder.deleteFile(at: url)
        }
        recorder.reset()
        dismiss()
    }

    // MARK: - Helpers

    private func generateTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Recording \(formatter.string(from: Date()))"
    }
}

// MARK: - Meeting Notes Sheet

struct MeetingNotesSheet: View {
    @Binding var notes: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $notes)
                    .font(AppFont.mono(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .padding(.horizontal, AppLayout.horizontalPadding)
                    .padding(.top, 12)
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MEETING NOTES")
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(AppFont.mono(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Wave Visualizer (TimelineView-based for efficient animation)

/// A high-performance wave visualizer using TimelineView for GPU-driven animation.
/// This avoids main thread timers and only redraws when the system is ready.
struct WaveVisualizerView: View {
    let isRecording: Bool
    let isPaused: Bool
    let amplitude: CGFloat
    
    var body: some View {
        TimelineView(.animation(minimumInterval: isRecording && !isPaused ? 1.0 / 30.0 : 1.0 / 15.0)) { timeline in
            WaveCanvas(
                date: timeline.date,
                isRecording: isRecording,
                amplitude: isRecording && !isPaused ? amplitude : 0.01
            )
        }
    }
}

/// The actual Canvas drawing, separated to avoid recomputing the view hierarchy
private struct WaveCanvas: View {
    let date: Date
    let isRecording: Bool
    let amplitude: CGFloat
    
    // Compute phase based on time for smooth animation
    private var phase: CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100)) * 1.5
    }
    
    // Smooth the amplitude display using animation
    @State private var displayAmplitude: CGFloat = 0.01
    
    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let width = size.width
            
            if isRecording {
                // Ghost waves (raw signal echoes)
                drawSmoothWave(context: context, midY: midY, width: width, height: size.height,
                               amplitude: displayAmplitude * 0.5, frequency: 4.5, phaseOffset: .pi / 3,
                               opacity: 0.10, lineWidth: 1)
                
                drawSmoothWave(context: context, midY: midY, width: width, height: size.height,
                               amplitude: displayAmplitude * 0.35, frequency: 3.0, phaseOffset: -.pi / 4,
                               opacity: 0.10, lineWidth: 1)
                
                // Primary wave (constructive interference)
                drawSmoothWave(context: context, midY: midY, width: width, height: size.height,
                               amplitude: displayAmplitude * 0.8, frequency: 2.5, phaseOffset: .pi / 6,
                               opacity: 0.85, lineWidth: 2.5)
            } else {
                // Idle breathing line
                drawSmoothWave(context: context, midY: midY, width: width, height: size.height,
                               amplitude: displayAmplitude, frequency: 2.0, phaseOffset: 0,
                               opacity: 0.15, lineWidth: 1.5)
            }
        }
        .onChange(of: amplitude) { _, newValue in
            withAnimation(.easeOut(duration: 0.1)) {
                displayAmplitude = newValue
            }
        }
        .onAppear {
            displayAmplitude = amplitude
        }
    }
    
    private func drawSmoothWave(context: GraphicsContext, midY: CGFloat, width: CGFloat, height: CGFloat,
                                amplitude: CGFloat, frequency: CGFloat, phaseOffset: CGFloat,
                                opacity: Double, lineWidth: CGFloat) {
        var path = Path()
        let maxAmp = height * 0.4 * amplitude
        let step: CGFloat = 3 // Increased step for fewer points
        
        for x in stride(from: 0, through: width, by: step) {
            let norm = x / width
            let envelope = 0.5 * (1.0 - cos(2.0 * .pi * norm))
            let y = midY + sin(norm * .pi * 2 * frequency + phase + phaseOffset) * maxAmp * envelope
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        
        context.stroke(path, with: .color(.white.opacity(opacity)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}



#Preview {
    RecorderView()
        .modelContainer(for: Recording.self, inMemory: true)
}
