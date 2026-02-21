import SwiftUI
import SwiftData
import os

private let overviewLogger = Logger(subsystem: "com.Proceduralabs.Trace", category: "Transcription")

struct RecordingOverviewSheet: View {
    @Bindable var recording: Recording
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }

    @State private var editedTitle: String = ""
    @State private var trimStart: CGFloat = 0
    @State private var trimEnd: CGFloat = 1
    @State private var dragStartTrimStart: CGFloat = 0
    @State private var dragStartTrimEnd: CGFloat = 1
    @State private var isTranscribing = false
    @State private var showDeleteConfirm = false
    @State private var showShareSheet = false
    @State private var showPaywall = false
    @State private var player = AudioPlayer()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    waveformSection
                        .padding(.top, 8)

                    playbackControls

                    infoSection

                    titleSection

                    actionsSection
                }
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(colors.background.ignoresSafeArea())
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbarBackground(colors.toolbarBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.discard) {
                        showDeleteConfirm = true
                    }
                    .font(AppFont.mono(size: 14, weight: .regular))
                    .foregroundStyle(colors.secondaryText)
                }

                ToolbarItem(placement: .principal) {
                    TrackedLabel(L10n.review, size: 13, weight: .semibold)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.save) {
                        save()
                    }
                    .font(AppFont.mono(size: 14, weight: .bold))
                    .foregroundStyle(colors.primaryText)
                }
            }
            .alert(L10n.discardRecording, isPresented: $showDeleteConfirm) {
                Button(L10n.discard, role: .destructive) { discardRecording() }
                Button(L10n.cancel, role: .cancel) { }
            } message: {
                Text(L10n.discardMessage)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = recording.audioURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .onAppear {
            editedTitle = recording.title
            if let url = recording.audioURL {
                player.load(url: url)
            }
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - Waveform with Trim

    private var waveformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(L10n.waveform, size: 10, kerning: 1.5)

            GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = 80

                ZStack(alignment: .leading) {
                    // Waveform canvas — all coloring handled here
                    Canvas { context, size in
                        let ts = trimStart
                        let te = trimEnd
                        let pp = player.progress
                        let count = recording.amplitudeSamples.count
                        guard count > 0 else { return }
                        let gap: CGFloat = 1.5
                        let barWidth = max(1.5, (size.width - CGFloat(count - 1) * gap) / CGFloat(count))

                        for i in 0..<count {
                            let x = CGFloat(i) * (barWidth + gap)
                            let norm = CGFloat(i) / CGFloat(count)
                            let inRange = norm >= ts && norm <= te
                            let isPast = norm <= pp
                            let barHeight = max(2, CGFloat(recording.amplitudeSamples[i]) * size.height)
                            let y = (size.height - barHeight) / 2

                            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                            let path = Path(roundedRect: rect, cornerRadius: 1)

                            let opacity: Double
                            if !inRange {
                                opacity = 0.06
                            } else if isPast {
                                opacity = 0.7
                            } else {
                                opacity = 0.2
                            }

                            context.fill(path, with: .color(.white.opacity(opacity)))
                        }

                        // Playback position line drawn in canvas
                        if pp > 0 {
                            let lineX = pp * size.width
                            let lineRect = CGRect(x: lineX - 0.75, y: -8, width: 1.5, height: size.height + 16)
                            context.fill(Path(lineRect), with: .color(.white))
                        }
                    }
                    .frame(height: height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let fraction = max(0, min(1, value.location.x / width))
                                player.seek(to: fraction)
                            }
                    )

                    // Left trim handle
                    trimHandleView(isLeading: true)
                        .offset(x: trimStart * width - 16)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let delta = value.translation.width / width
                                    let newPos = max(0, min(dragStartTrimStart + delta, trimEnd - 0.05))
                                    trimStart = newPos
                                }
                                .onEnded { _ in
                                    dragStartTrimStart = trimStart
                                }
                        )

                    // Right trim handle
                    trimHandleView(isLeading: false)
                        .offset(x: trimEnd * width - 16)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let delta = value.translation.width / width
                                    let newPos = min(1, max(dragStartTrimEnd + delta, trimStart + 0.05))
                                    trimEnd = newPos
                                }
                                .onEnded { _ in
                                    dragStartTrimEnd = trimEnd
                                }
                        )
                }
            }
            .frame(height: 80)

            // Trim time labels
            HStack {
                Text((Double(trimStart) * recording.duration).formatted)
                    .font(AppFont.mono(size: 11, weight: .medium))
                    .foregroundStyle(colors.primaryText)

                Spacer()

                Text("\(L10n.trimmed): \(trimmedDuration.formatted)")
                    .font(AppFont.mono(size: 11, weight: .medium))
                    .kerning(0.8)
                    .foregroundStyle(colors.secondaryText)

                Spacer()

                Text((Double(trimEnd) * recording.duration).formatted)
                    .font(AppFont.mono(size: 11, weight: .medium))
                    .foregroundStyle(colors.primaryText)
            }
        }
    }

    private func trimHandleView(isLeading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(colors.glassBorder, lineWidth: 1)
            )
            .frame(width: 4, height: 96)
            .padding(.horizontal, 14) // 32pt total hit area
            .contentShape(Rectangle())
    }

    private var trimmedDuration: TimeInterval {
        Double(trimEnd - trimStart) * recording.duration
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 0) {
            Text(AudioPlayer.formatTime(player.currentTime))
                .font(AppFont.mono(size: 12, weight: .bold))
                .foregroundStyle(colors.primaryText)
                .frame(width: 50, alignment: .leading)

            Spacer()

            // Skip back
            Button {
                let newTime = max(0, player.currentTime - 10)
                player.seek(to: CGFloat(newTime / max(1, recording.duration)))
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .glassCard(radius: 18)
            }

            Spacer().frame(width: 20)

            // Play / Pause
            Button {
                player.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)

                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: player.isPlaying ? 0 : 2)
                }
            }

            Spacer().frame(width: 20)

            // Skip forward
            Button {
                let newTime = min(recording.duration, player.currentTime + 10)
                player.seek(to: CGFloat(newTime / max(1, recording.duration)))
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 36, height: 36)
                    .glassCard(radius: 18)
            }

            Spacer()

            Text(AudioPlayer.formatTime(recording.duration))
                .font(AppFont.mono(size: 12, weight: .regular))
                .foregroundStyle(colors.secondaryText)
                .frame(width: 50, alignment: .trailing)
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel(L10n.recordingInfo, size: 10, kerning: 1.5)

            HStack(spacing: 0) {
                infoCell(value: recording.formattedDuration, label: "TOTAL")
                infoDivider
                infoCell(value: trimmedDuration.formatted, label: "SELECTED")
                infoDivider
                infoCell(value: "\(recording.marks.count)", label: "MARKS")
            }
            .padding(.vertical, 14)
            .glassCard(radius: 10)
        }
    }

    private func infoCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppFont.mono(size: 18, weight: .bold))
                .foregroundStyle(colors.primaryText)
            Text(label)
                .font(AppFont.mono(size: 9, weight: .medium))
                .kerning(1.0)
                .foregroundStyle(colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var infoDivider: some View {
        Rectangle().fill(colors.divider).frame(width: 0.5, height: 28)
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackedLabel(L10n.titleLabel, size: 10, kerning: 1.5)

            TextField("", text: $editedTitle)
                .font(AppFont.mono(size: 18, weight: .bold))
                .foregroundStyle(colors.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.thinMaterial.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: AppLayout.inputRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.inputRadius)
                        .stroke(colors.glassBorder, lineWidth: AppLayout.glassBorderWidth)
                )
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel(L10n.actions, size: 10, kerning: 1.5)

            // Transcribe button (primary CTA — stays white)
            Button {
                save()
                transcribe()
            } label: {
                HStack {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 16))

                    Text(L10n.saveAndTranscribe)
                        .font(AppFont.mono(size: 13, weight: .bold))
                        .kerning(1.0)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Save only
            Button {
                save()
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 16))

                    Text(L10n.saveWithoutTranscribing)
                        .font(AppFont.mono(size: 12, weight: .medium))
                        .kerning(0.8)
                }
                .foregroundStyle(colors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassCard(radius: 12)
            }

            // Share audio
            if recording.audioURL != nil {
                Button {
                    showShareSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))

                        Text(L10n.shareAudioFile)
                            .font(AppFont.mono(size: 12, weight: .medium))
                            .kerning(0.8)
                    }
                    .foregroundStyle(colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassCard(radius: 12)
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        player.stop()

        recording.title = editedTitle.trimmingCharacters(in: .whitespaces).isEmpty
            ? recording.title
            : editedTitle.trimmingCharacters(in: .whitespaces)

        // Apply trim if changed
        if trimStart > 0.01 || trimEnd < 0.99 {
            let startIdx = Int(trimStart * CGFloat(recording.amplitudeSamples.count))
            let endIdx = Int(trimEnd * CGFloat(recording.amplitudeSamples.count))
            let clamped = max(0, startIdx)...min(recording.amplitudeSamples.count - 1, endIdx)
            recording.amplitudeSamples = Array(recording.amplitudeSamples[clamped])
            recording.duration = trimmedDuration
        }

        dismiss()
    }

    private func transcribe() {
        guard let url = recording.audioURL else { return }

        // Check subscription limits before transcribing
        let subscription = SubscriptionManager.shared
        if !subscription.canTranscribe(duration: recording.duration) {
            showPaywall = true
            return
        }

        recording.isTranscribing = true
        recording.transcriptionError = nil

        let recordingUID = recording.uid
        let recordingDuration = recording.duration
        Task.detached {
            await performTranscription(uid: recordingUID, fileURL: url, duration: recordingDuration)
        }
    }

    @MainActor
    private func performTranscription(uid: UUID, fileURL: URL, duration: TimeInterval) async {
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.uid == uid })
        guard let recording = try? modelContext.fetch(descriptor).first else { return }

        do {
            let result = try await TranscriptionService.shared.transcribeAuto(fileURL: fileURL)

            recording.transcriptFullText = result.transcript.fullText
            recording.transcriptSegments = result.transcript.segments.map {
                SegmentData(speaker: $0.speaker, text: $0.text, timestamp: $0.timestamp)
            }
            recording.transcriptLanguage = result.response.language_code
            recording.wasTranscribedOnDevice = result.wasOnDevice
            recording.isTranscribing = false

            // Log silence trimming info for demo
            if result.wasSilenceTrimmed, let trimmedSeconds = result.silenceTrimmedSeconds {
                let trimmedFormatted = String(format: "%.1f", trimmedSeconds)
                let originalFormatted = String(format: "%.1f", duration)
                let sentFormatted = String(format: "%.1f", duration - trimmedSeconds)
                let savingsPercent = String(format: "%.0f", (trimmedSeconds / duration) * 100)
                overviewLogger.info("✂️ Silence Trimming: Removed \(trimmedFormatted)s of silence (\(savingsPercent)% savings)")
                overviewLogger.info("✂️ Original: \(originalFormatted)s → Sent to API: \(sentFormatted)s")
                overviewLogger.info("✂️ Usage charged: \(originalFormatted)s (full original duration)")
            }

            // Record usage after successful transcription (only for cloud)
            if !result.wasOnDevice {
                SubscriptionManager.shared.recordTranscriptionUsage(seconds: duration)
            }

            // Auto-chain into summarization
            await performSummarization(recording: recording)
            // Send notification (will only show if app is in background)
            NotificationService.shared.notifyTranscriptionComplete(
                recordingTitle: recording.title,
                recordingUID: recording.uid,
                detectedLanguage: result.detectedLanguage,
                wasOnDevice: result.wasOnDevice
            )
        } catch is CancellationError {
            recording.isTranscribing = false
        } catch let error as TranscriptionError where error == .cancelled {
            recording.isTranscribing = false
        } catch let error as OnDeviceTranscriptionError where error == .cancelled {
            recording.isTranscribing = false
        } catch {
            recording.isTranscribing = false
            recording.transcriptionError = error.localizedDescription
            overviewLogger.error("Transcription failed for '\(recording.title)': \(error.localizedDescription)")
            
            // Send failure notification
            NotificationService.shared.notifyTranscriptionFailed(
                recordingTitle: recording.title,
                recordingUID: recording.uid,
                errorMessage: error.localizedDescription
            )
        }
    }

    @MainActor
    private func performSummarization(recording: Recording) async {
        guard let transcriptText = recording.transcriptFullText else { return }

        recording.isSummarizing = true
        recording.summarizationError = nil

        do {
            // Pass the detected language so summary is in the same language as the transcript
            let result = try await SummarizationService.shared.summarizeAuto(
                transcript: transcriptText,
                meetingNotes: recording.notes,
                language: recording.transcriptLanguage
            )

            recording.summaryOneLiner = result.oneLiner
            recording.summaryContext = result.context
            recording.summaryActions = result.actions
            recording.wasSummarizedOnDevice = result.wasOnDevice
            recording.isSummarizing = false
            
            // Send combined completion notification (transcription + summary done)
            NotificationService.shared.notifyProcessingComplete(
                recordingTitle: recording.title,
                recordingUID: recording.uid,
                oneLiner: result.oneLiner,
                detectedLanguage: recording.transcriptLanguage
            )
        } catch {
            recording.isSummarizing = false
            recording.summarizationError = error.localizedDescription
            overviewLogger.error("Summarization failed for '\(recording.title)': \(error.localizedDescription)")
        }
    }

    private func discardRecording() {
        player.stop()
        if let url = recording.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        ChatPersistence.delete(for: recording.uid)
        modelContext.delete(recording)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    RecordingOverviewSheet(recording: Recording.previewSample)
        .modelContainer(for: Recording.self, inMemory: true)
}
extension Recording {
    static var previewSample: Recording {
        let recording = Recording(
            title: "Team Standup Meeting",
            date: Date(),
            duration: 248.5,
            amplitudeSamples: (0..<60).map { _ in Float.random(in: 0.2...0.9) },
            audioFileName: nil
        )
        recording.marks = [45.2, 120.8, 185.3]
        return recording
    }
}



