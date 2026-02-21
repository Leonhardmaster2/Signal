import SwiftUI
import SwiftData
import AVFoundation
import PhotosUI
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "com.Proceduralabs.Trace", category: "Transcription")

// MARK: - Pending Date Action

private enum PendingDateAction {
    case reminder(index: Int, title: String, recordingTitle: String)
    case calendarEvent(index: Int, title: String, duration: TimeInterval, recordingTitle: String)
}

// MARK: - Decoded View (The Output)

struct DecodedView: View {
    @Bindable var recording: Recording
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var isTranscribing = false
    @State private var errorMessage: String?

    // Delete flow
    @State private var showDeleteConfirmation = false

    // Share flow
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    // Copy toast
    @State private var showCopiedToast = false

    // Notes image handling
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isProcessingImage = false
    @State private var selectedImageForOCR: (url: URL, image: PlatformImage)?

    // Speaker renaming
    @State private var editingSpeaker: String?
    @State private var editingSpeakerName = ""

    // Shared audio player for transcript sync
    @State private var sharedPlayer = AudioPlayer()
    
    // Transcript editing
    @State private var editingSegmentIndex: Int?
    @State private var editingSegmentText = ""
    
    // Renaming
    @State private var showRenameAlert = false
    @State private var renameText = ""

    // Transcript management
    @State private var showDeleteTranscriptConfirmation = false

    // Subscription
    @State private var showPaywall = false
    @State private var subscriptionLimitError: String?
    
    // Premium features

    @State private var showAudioSearch = false
    @State private var showExportOptions = false
    
    // Transcription method chooser
    @State private var showTranscriptionChooser = false

    // Smart actions tracking
    @State private var createdReminders: Set<Int> = []
    @State private var createdEvents: Set<Int> = []
    @State private var showActionToast = false
    @State private var actionToastText = ""
    @State private var showDatePicker = false
    @State private var datePickerDate = Date()
    @State private var pendingDatePickerItem: PendingDateAction?

    // Audio compression
    @State private var isCompressing = false
    @State private var compressionResult: String?
    
    // Chat → transcript highlight navigation
    @State private var highlightedSegmentIndex: Int?
    @State private var scrollToSegmentIndex: Int?

    // Adaptive layout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                // iPad/Mac: Wide layout with side-by-side panels
                wideLayout
            } else {
                // iPhone: Compact tabbed layout
                compactLayout
            }

            // Copied toast overlay
            if showCopiedToast {
                VStack {
                    Spacer()
                    Text(L10n.copied)
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(colors.primaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .glassCard(radius: 8)
                        .padding(.bottom, 40)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
            }

            // Smart action toast overlay
            if showActionToast {
                VStack {
                    Spacer()
                    Text(actionToastText.uppercased())
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(colors.primaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .glassCard(radius: 8)
                        .padding(.bottom, 40)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
            }
        }
        .background(colors.background.ignoresSafeArea())
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbarBackground(colors.toolbarBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(L10n.decodedTitle)
                    .font(AppFont.mono(size: 13, weight: .semibold))
                    .kerning(2.0)
                    .foregroundStyle(colors.primaryText)
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    if recording.hasTranscript {
                        Button {
                            if FeatureGate.canAccess(.audioSearch) {
                                showAudioSearch = true
                            } else {
                                showPaywall = true
                            }
                        } label: {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 15))
                                .foregroundStyle(colors.primaryText)
                        }
                    }
                    toolbarMenu
                }
            }
        }
        .alert(L10n.delete + "?", isPresented: $showDeleteTranscriptConfirmation) {
            Button(L10n.delete, role: .destructive) {
                deleteTranscript()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.deleteTranscriptMessage)
        }
        .alert(L10n.renameRecording, isPresented: $showRenameAlert) {
            TextField(L10n.renameRecording, text: $renameText)
            Button(L10n.save) {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    recording.title = trimmed
                    // Also rename the audio file if desired
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.enterNewName)
        }
        .alert(L10n.deleteRecording + "?", isPresented: $showDeleteConfirmation) {
            Button(L10n.delete, role: .destructive) {
                if let url = recording.audioURL {
                    try? FileManager.default.removeItem(at: url)
                }
                ChatPersistence.delete(for: recording.uid)
                modelContext.delete(recording)
                dismiss()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.deleteRecordingMessage)
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            shareItems = []
        }) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }

        .sheet(isPresented: $showAudioSearch) {
            AskAudioView(recording: recording) { segmentIndex in
                showAudioSearch = false
                selectedTab = 1 // Switch to TRANSCRIPT tab
                scrollToSegmentIndex = segmentIndex
                highlightedSegmentIndex = segmentIndex
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.easeOut(duration: 0.5)) {
                        highlightedSegmentIndex = nil
                    }
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                VStack(spacing: 24) {
                    Text(L10n.pickDateTime)
                        .font(AppFont.mono(size: 13, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(colors.primaryText)

                    DatePicker("", selection: $datePickerDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .tint(colors.primaryText)
                        .labelsHidden()

                    Button {
                        showDatePicker = false
                        if let item = pendingDatePickerItem {
                            let pickedDate = datePickerDate
                            switch item {
                            case .reminder(let index, let title, let recordingTitle):
                                createReminder(index: index, title: title, dueDate: pickedDate, recordingTitle: recordingTitle)
                            case .calendarEvent(let index, let title, let duration, let recordingTitle):
                                createCalendarEvent(index: index, title: title, startDate: pickedDate, duration: duration, recordingTitle: recordingTitle)
                            }
                            pendingDatePickerItem = nil
                        }
                    } label: {
                        Text(L10n.confirm)
                            .font(AppFont.mono(size: 14, weight: .bold))
                            .kerning(1.5)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: AppLayout.inputRadius))
                    }
                }
                .padding(AppLayout.horizontalPadding)
                .background(colors.background.ignoresSafeArea())
                
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) {
                            showDatePicker = false
                            pendingDatePickerItem = nil
                        }
                        .font(AppFont.mono(size: 13))
                    }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showTranscriptionChooser) {
            TranscriptionMethodChooser(
                recordingDuration: recording.duration,
                onChooseApple: {
                    // Dismiss sheet first, then start transcription after a brief delay
                    // This ensures the progress UI is visible
                    showTranscriptionChooser = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        performTranscription(useOnDevice: true)
                    }
                },
                onChooseAPI: {
                    showTranscriptionChooser = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        performTranscription(useOnDevice: false)
                    }
                }
            )
        }
        .onAppear {
            // Load audio into shared player for transcript sync
            if let url = recording.audioURL {
                sharedPlayer.load(url: url, title: recording.title)
            }
        }
        .onDisappear {
            sharedPlayer.stop()
        }
    }
    
    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        TabView(selection: $selectedTab) {
            Tab(L10n.distill, systemImage: "sparkles", value: 0) {
                tabContentView(content: distillationTab)
            }
            
            Tab(L10n.transcript, systemImage: "doc.text", value: 1) {
                tabContentView(content: transcriptTab)
            }
            
            Tab(L10n.notes, systemImage: "note.text", value: 2) {
                tabContentView(content: notesTab)
            }
            
            Tab(L10n.audio, systemImage: "waveform", value: 3) {
                tabContentView(content: audioTab)
            }
        }
    }
    
    private func tabContentView<Content: View>(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            recordingHeader
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Persistent mini audio player — always available
            if recording.audioURL != nil {
                miniAudioPlayer
                    .padding(.horizontal, AppLayout.horizontalPadding)
                    .padding(.bottom, 16)
            }

            ScrollViewReader { scrollProxy in
                ScrollView {
                    content
                        .padding(.horizontal, AppLayout.horizontalPadding)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: scrollToSegmentIndex) { _, newValue in
                    if let idx = newValue {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            scrollProxy.scrollTo("segment_\(idx)", anchor: .center)
                        }
                        scrollToSegmentIndex = nil
                    }
                }
            }
        }
    }

    // MARK: - Mini Audio Player (Always Visible)

    private var miniAudioPlayer: some View {
        HStack(spacing: 12) {
            // Play / Pause button
            Button {
                sharedPlayer.togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 36, height: 36)

                    Image(systemName: sharedPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .offset(x: sharedPlayer.isPlaying ? 0 : 1.5)
                }
            }

            // Mini waveform / progress scrubber
            GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = 28

                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        let samples = recording.amplitudeSamples
                        let count = samples.count
                        if count > 0 {
                            let gap: CGFloat = 1.5
                            let barWidth = max(1.5, (size.width - CGFloat(count - 1) * gap) / CGFloat(count))

                            for i in 0..<count {
                                let x = CGFloat(i) * (barWidth + gap)
                                let normalizedPos = CGFloat(i) / CGFloat(count)
                                let isPast = normalizedPos <= sharedPlayer.progress
                                let barHeight = max(2, CGFloat(samples[i]) * height)
                                let y = (height - barHeight) / 2

                                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                                let path = Path(roundedRect: rect, cornerRadius: 1)
                                context.fill(path, with: .color(colors.primaryText.opacity(isPast ? 0.6 : 0.1)))
                            }
                        } else {
                            // No waveform data — show simple progress bar
                            let trackRect = CGRect(x: 0, y: size.height / 2 - 1.5, width: size.width, height: 3)
                            context.fill(Path(roundedRect: trackRect, cornerRadius: 1.5), with: .color(colors.primaryText.opacity(0.08)))

                            let prog = sharedPlayer.progress
                            if prog > 0 {
                                let fillRect = CGRect(x: 0, y: size.height / 2 - 1.5, width: size.width * prog, height: 3)
                                context.fill(Path(roundedRect: fillRect, cornerRadius: 1.5), with: .color(colors.primaryText.opacity(0.5)))
                            }
                        }
                    }
                    .frame(height: height)

                    // Scrub line
                    if sharedPlayer.progress > 0 {
                        Rectangle()
                            .fill(colors.primaryText)
                            .frame(width: 1.5, height: height + 8)
                            .offset(x: sharedPlayer.progress * width - 0.75)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / width))
                            sharedPlayer.seek(to: fraction)
                        }
                )
            }
            .frame(height: 28)

            // Current time
            Text(AudioPlayer.formatTime(sharedPlayer.isPlaying || sharedPlayer.currentTime > 0 ? sharedPlayer.currentTime : recording.duration))
                .font(AppFont.mono(size: 10, weight: .medium))
                .foregroundStyle(colors.secondaryText)
                .frame(width: 42, alignment: .trailing)

            // Skip forward 15s
            Button {
                let newTime = min(recording.duration, sharedPlayer.currentTime + 15)
                sharedPlayer.seek(to: CGFloat(newTime / max(1, recording.duration)))
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassCard(radius: 12)
    }
    
    // MARK: - Wide Layout (iPad/Mac)
    
    private var wideLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header spans full width
            wideHeader
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 24)
            
            // Two-column content
            HStack(alignment: .top, spacing: 24) {
                // Left column: Audio + Transcript
                VStack(alignment: .leading, spacing: 24) {
                    // Audio player (always visible)
                    if !recording.amplitudeSamples.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            TrackedLabel(L10n.playback, size: 10, kerning: 1.5)
                            PlaybackWaveformView(
                                samples: recording.amplitudeSamples,
                                duration: recording.duration,
                                marks: recording.marks,
                                audioURL: recording.audioURL,
                                player: sharedPlayer
                            )
                        }
                        .padding(20)
                        .glassCard(radius: 14)
                    }
                    
                    // Transcript (scrollable)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            TrackedLabel(L10n.transcript, size: 10, kerning: 1.5)
                            if recording.wasTranscribedOnDevice == true {
                                OnDeviceBadge(type: .transcription, compact: true)
                            }
                        }

                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                wideTranscriptContent
                            }
                            .frame(maxHeight: .infinity)
                            .onChange(of: scrollToSegmentIndex) { _, newValue in
                                if let idx = newValue {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        scrollProxy.scrollTo("segment_\(idx)", anchor: .center)
                                    }
                                    scrollToSegmentIndex = nil
                                }
                            }
                        }
                    }
                    .padding(20)
                    .glassCard(radius: 14)
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                
                // Right column: Summary + Notes
                VStack(alignment: .leading, spacing: 24) {
                    // Summary/Distillation
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            TrackedLabel(L10n.distillation, size: 10, kerning: 1.5)
                            if recording.wasSummarizedOnDevice == true {
                                OnDeviceBadge(type: .summarization, compact: true)
                            }
                        }
                        
                        ScrollView {
                            wideDistillationContent
                        }
                    }
                    .padding(20)
                    .glassCard(radius: 14)
                    .frame(maxHeight: .infinity)
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 12) {
                        TrackedLabel(L10n.notes, size: 10, kerning: 1.5)
                        
                        wideNotesContent
                    }
                    .padding(20)
                    .glassCard(radius: 14)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Wide Header
    
    private var wideHeader: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(recording.title)
                        .font(AppFont.mono(size: 28, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                    
                    if recording.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.primaryText)
                    }
                }
                
                HStack(spacing: 16) {
                    Label(formattedDate(recording.date), systemImage: "calendar")
                    Label(recording.duration.durationLabel, systemImage: "clock")
                    if let lang = recording.transcriptLanguage {
                        Label(lang.uppercased(), systemImage: "globe")
                    }
                    if recording.uniqueSpeakers.count > 0 {
                        Label("\(recording.uniqueSpeakers.count) \(L10n.speakers)", systemImage: "person.2.fill")
                    }
                }
                .font(AppFont.mono(size: 12, weight: .regular))
                .foregroundStyle(colors.secondaryText)
            }
            
            Spacer()
            
            // Status / actions
            HStack(spacing: 12) {
                if recording.isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(colors.primaryText)
                        Text(L10n.transcribing)
                            .font(AppFont.mono(size: 11, weight: .semibold))
                            .kerning(1.0)
                            .foregroundStyle(colors.primaryText)

                        if (recording.transcriptionProgress ?? 0) > 0 {
                            Text("\(Int((recording.transcriptionProgress ?? 0) * 100))%")
                                .font(AppFont.mono(size: 11, weight: .bold))
                                .foregroundStyle(colors.secondaryText)
                        }

                        Button {
                            cancelTranscription()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(colors.secondaryText)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassCard(radius: 8)
                } else if recording.isSummarizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(colors.primaryText)
                        Text(L10n.summarizing)
                            .font(AppFont.mono(size: 11, weight: .semibold))
                            .kerning(1.0)
                            .foregroundStyle(colors.primaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassCard(radius: 8)
                } else if !recording.hasTranscript {
                    Button {
                        transcribe()
                    } label: {
                        HStack(spacing: 6) {
                            if !SubscriptionManager.shared.canTranscribeAtAll {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                            }
                            Text(SubscriptionManager.shared.canTranscribeAtAll ? L10n.transcribe.uppercased() : L10n.unlockTranscription)
                                .font(AppFont.mono(size: 11, weight: .bold))
                                .kerning(1.5)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                } else if !recording.hasSummary {
                    Button {
                        summarize()
                    } label: {
                        Text(L10n.summarize.uppercased())
                            .font(AppFont.mono(size: 11, weight: .bold))
                            .kerning(1.5)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
    
    // MARK: - Wide Content Sections
    
    @ViewBuilder
    private var wideTranscriptContent: some View {
        if let segments = recording.transcriptSegments, !segments.isEmpty {
            // Speaker chips
            if !recording.uniqueSpeakers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recording.uniqueSpeakers, id: \.self) { speaker in
                            Button {
                                editingSpeaker = speaker
                                editingSpeakerName = recording.displayName(for: speaker)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 9))
                                    Text(recording.displayName(for: speaker))
                                        .font(AppFont.mono(size: 11, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(colors.primaryText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(colors.selection)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            
            // Segments
            VStack(spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    wideTranscriptRow(segment, index: index, isActive: currentSegmentIndex == index, isHighlighted: highlightedSegmentIndex == index)
                        .id("segment_\(index)")
                }
            }
        } else if recording.isTranscribing {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(colors.primaryText)
                Text(L10n.transcribing)
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(colors.secondaryText)

                if (recording.transcriptionProgress ?? 0) > 0 {
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.6))
                                    .frame(width: geo.size.width * (recording.transcriptionProgress ?? 0), height: 3)
                                    .animation(.easeInOut(duration: 0.3), value: recording.transcriptionProgress)
                            }
                        }
                        .frame(height: 3)
                        .frame(maxWidth: 200)

                        Text("\(Int((recording.transcriptionProgress ?? 0) * 100))%")
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(colors.secondaryText)
                    }
                }

                Button {
                    cancelTranscription()
                } label: {
                    Text(L10n.cancel.uppercased())
                        .font(AppFont.mono(size: 10, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(colors.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(colors.selection)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(colors.mutedText)
                Text(L10n.noTranscriptYet)
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    private func wideTranscriptRow(_ segment: SegmentData, index: Int, isActive: Bool, isHighlighted: Bool = false) -> some View {
        let bgColor: Color = isHighlighted ? Color.yellow.opacity(0.15) : (isActive ? colors.selection : Color.clear)
        let borderColor: Color = isHighlighted ? Color.yellow.opacity(0.4) : Color.clear
        let textColor: Color = isActive ? colors.primaryText : colors.secondaryText

        return wideTranscriptRowContent(segment, index: index, isActive: isActive, textColor: textColor)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.5), value: isHighlighted)
            .contentShape(Rectangle())
            .onTapGesture {
                if recording.duration > 0 {
                    let fraction = CGFloat(segment.timestamp / recording.duration)
                    sharedPlayer.seek(to: fraction)
                    if !sharedPlayer.isPlaying {
                        sharedPlayer.play()
                    }
                }
            }
    }

    @ViewBuilder
    private func wideTranscriptRowContent(_ segment: SegmentData, index: Int, isActive: Bool, textColor: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 4) {
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.primaryText)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
                }
                Text(segment.timestamp.formatted)
                    .font(AppFont.mono(size: 10, weight: .regular))
                    .foregroundStyle(colors.mutedText)
            }
            .frame(width: 50, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                if !segment.speaker.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(recording.displayName(for: segment.speaker))
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                }

                Text(segment.text)
                    .font(AppFont.mono(size: 13, weight: .regular))
                    .foregroundStyle(textColor)
                    .lineSpacing(3)
            }

            Spacer()

            Button {
                editingSegmentIndex = index
                editingSegmentText = segment.text
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(colors.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var wideDistillationContent: some View {
        if let summary = recording.summary {
            VStack(alignment: .leading, spacing: 20) {
                // One-liner
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.theOneLiner)
                        .font(AppFont.mono(size: 9, weight: .medium))
                        .kerning(1.0)
                        .foregroundStyle(colors.secondaryText)
                    Text(summary.oneLiner)
                        .font(AppFont.mono(size: 16, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                        .lineSpacing(3)
                }
                
                // Action vectors
                if !summary.actionVectors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.actionVectors)
                            .font(AppFont.mono(size: 9, weight: .medium))
                            .kerning(1.0)
                            .foregroundStyle(colors.secondaryText)
                        
                        ForEach(summary.actionVectors) { action in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .stroke(Color.white.opacity(action.isCompleted ? 1 : 0.25), lineWidth: 1.5)
                                    .background(Circle().fill(action.isCompleted ? Color.white : Color.clear))
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        if action.isCompleted {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.black)
                                        }
                                    }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.task)
                                        .font(AppFont.mono(size: 13, weight: .medium))
                                        .foregroundStyle(colors.primaryText)
                                    Text(action.assignee)
                                        .font(AppFont.mono(size: 10, weight: .regular))
                                        .foregroundStyle(colors.secondaryText)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                
                // Context
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.context)
                        .font(AppFont.mono(size: 9, weight: .medium))
                        .kerning(1.0)
                        .foregroundStyle(colors.secondaryText)
                    Text(summary.context)
                        .font(AppFont.mono(size: 13, weight: .regular))
                        .foregroundStyle(colors.secondaryText)
                        .lineSpacing(4)
                }
            }
        } else if recording.isSummarizing {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(colors.primaryText)
                Text(L10n.summarizing)
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if recording.hasTranscript {
            VStack(spacing: 12) {
                Image(systemName: "brain")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(colors.mutedText)
                Text(L10n.readyToSummarize)
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "brain")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(colors.mutedText)
                Text(L10n.transcribeFirstToUnlock)
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    @ViewBuilder
    private var wideNotesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: Binding(
                get: { recording.notes ?? "" },
                set: { recording.notes = $0.isEmpty ? nil : $0 }
            ))
            .font(AppFont.mono(size: 13, weight: .regular))
            .foregroundStyle(colors.primaryText)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 100)
            .padding(10)
            .background(colors.selection)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Image attachments
            HStack {
                Text(L10n.attachments)
                    .font(AppFont.mono(size: 9, weight: .medium))
                    .kerning(1.0)
                    .foregroundStyle(colors.secondaryText)
                
                Spacer()
                
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(colors.secondaryText)
                }
                
                #if os(iOS)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 14))
                            .foregroundStyle(colors.secondaryText)
                    }
                }
                #endif
            }
            
            if let imageNames = recording.noteImageNames, !imageNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recording.noteImageURLs, id: \.absoluteString) { url in
                            NoteImageThumbnail(
                                url: url,
                                onTap: { image in
                                    selectedImageForOCR = (url, image)
                                },
                                onDelete: {
                                    deleteNoteImage(url: url)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Toolbar Menu

    private var toolbarMenu: some View {
        Menu {
            Button {
                recording.isStarred.toggle()
            } label: {
                Label(
                    recording.isStarred ? L10n.unstar : L10n.star,
                    systemImage: recording.isStarred ? "star.slash" : "star"
                )
            }

            Button {
                renameText = recording.title
                showRenameAlert = true
            } label: {
                Label(L10n.rename, systemImage: "pencil")
            }

            if recording.isTranscribing {
                Button(role: .destructive) {
                    cancelTranscription()
                } label: {
                    Label(L10n.cancelTranscription, systemImage: "xmark.circle")
                }
            }

            if !recording.hasTranscript && !recording.isTranscribing {
                Button {
                    transcribe()
                } label: {
                    Label(L10n.transcribe, systemImage: "waveform.badge.magnifyingglass")
                }
            }

            if recording.hasTranscript && !recording.hasSummary && !recording.isSummarizing {
                Button {
                    summarize()
                } label: {
                    Label(L10n.summarize, systemImage: "brain")
                }
            }

            // Premium features section
            if recording.hasTranscript {
                // Transcript management
                Button {
                    transcribe()
                } label: {
                    Label(L10n.retranscribe, systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    showDeleteTranscriptConfirmation = true
                } label: {
                    Label(L10n.deleteTranscript, systemImage: "text.badge.minus")
                }
            }

            Divider()

            if recording.audioURL != nil {
                Button {
                    shareAudio()
                } label: {
                    Label(L10n.shareAudio, systemImage: "square.and.arrow.up")
                }
            }
            
            Button {
                shareTracePackage()
            } label: {
                Label(L10n.shareTracePackage, systemImage: "shippingbox")
            }

            if recording.hasTranscript {
                Button {
                    copyTranscript()
                } label: {
                    Label(L10n.copyTranscript, systemImage: "doc.on.doc")
                }

                // Export options - Standard+ only
                Menu {
                    Button {
                        if FeatureGate.canAccess(.exportMarkdown) {
                            exportAsMarkdown()
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label(L10n.exportAsMarkdown, systemImage: "doc.text")
                    }
                    
                    Button {
                        if FeatureGate.canAccess(.exportPDF) {
                            exportAsPDF()
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label(L10n.exportAsPDF, systemImage: "doc.richtext")
                    }
                    
                    Divider()
                    
                    Button {
                        if let text = formattedTranscriptText() {
                            shareItems = [text]
                            showShareSheet = true
                        }
                    } label: {
                        Label(L10n.shareAsText, systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label(L10n.exportTranscript, systemImage: "arrow.up.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label(L10n.deleteRecording, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(colors.primaryText)
        }
    }

    // MARK: - Header

    private var recordingHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    renameText = recording.title
                    showRenameAlert = true
                } label: {
                    HStack(spacing: 6) {
                        Text(recording.title)
                            .font(AppFont.mono(size: 24, weight: .bold))
                            .foregroundStyle(colors.primaryText)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.secondaryText)
                    }
                }

                Spacer()

                if recording.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.primaryText)
                }
            }

            HStack(spacing: 12) {
                Label(formattedDate(recording.date), systemImage: "calendar")
                Label(recording.duration.durationLabel, systemImage: "clock")
                if let lang = recording.transcriptLanguage {
                    Label(lang.uppercased(), systemImage: "globe")
                }
                if recording.uniqueSpeakers.count > 0 {
                    Label("\(recording.uniqueSpeakers.count)", systemImage: "person.2.fill")
                }
            }
            .font(AppFont.mono(size: 11, weight: .regular))
            .foregroundStyle(colors.secondaryText)

            if !recording.amplitudeSamples.isEmpty {
                FrequencyBar(samples: recording.amplitudeSamples, height: 20)
                    .padding(.top, 4)
            }

            // Status / error banner
            if recording.isTranscribing {
                processingBanner(label: "TRANSCRIBING...", showCancel: true, progress: recording.transcriptionProgress ?? 0)
            } else if recording.isSummarizing {
                processingBanner(label: "SUMMARIZING...")
            } else if let error = recording.transcriptionError {
                errorBanner(error)
            }
        }
    }

    private func processingBanner(label: String, showCancel: Bool = false, progress: Double? = nil) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(colors.primaryText)

                Text(label)
                    .font(AppFont.mono(size: 11, weight: .semibold))
                    .kerning(1.0)
                    .foregroundStyle(colors.primaryText)

                if let progress, progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .foregroundStyle(colors.secondaryText)
                }

                Spacer()

                if showCancel {
                    Button {
                        cancelTranscription()
                    } label: {
                        Text(L10n.cancel.uppercased())
                            .font(AppFont.mono(size: 10, weight: .bold))
                            .kerning(1.0)
                            .foregroundStyle(colors.secondaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(colors.selection)
                            .clipShape(Capsule())
                    }
                }
            }

            // Progress bar
            if let progress, progress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.6))
                            .frame(width: geo.size.width * progress, height: 3)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 8)
        .padding(.top, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(colors.primaryText)

            Text(message)
                .font(AppFont.mono(size: 11, weight: .regular))
                .foregroundStyle(colors.secondaryText)
                .lineLimit(2)

            Spacer()

            Button(L10n.retry) { transcribe() }
                .font(AppFont.mono(size: 11, weight: .bold))
                .foregroundStyle(colors.primaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(radius: 8)
        .padding(.top, 8)
    }

    // MARK: - Tab Selector
    
    @Namespace private var tabNamespace

    private var tabSelector: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                tabButton(L10n.distill, index: 0)
                tabButton(L10n.transcript, index: 1)
                tabButton(L10n.notes, index: 2)
                tabButton(L10n.audio, index: 3)
            }
            .padding(4)
        }
        .glassEffect(in: .rect(cornerRadius: 12))
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedTab = index }
        } label: {
            Text(title)
                .font(AppFont.mono(size: 11, weight: selectedTab == index ? .bold : .medium))
                .kerning(1.2)
                .foregroundStyle(selectedTab == index ? colors.primaryText : colors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if selectedTab == index {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colors.selection)
                            .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                    }
                }
        }
    }
    


    // MARK: - Tab 1: Distillation

    private var distillationTab: some View {
        VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
            if let summary = recording.summary {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TrackedLabel(L10n.theOneLiner, size: 10, kerning: 1.5)
                        if recording.wasSummarizedOnDevice == true {
                            OnDeviceBadge(type: .summarization, compact: true)
                        }
                    }
                    Text(summary.oneLiner)
                        .font(AppFont.mono(size: 18, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TrackedLabel(L10n.actionVectors, size: 10, kerning: 1.5)
                    ForEach(summary.actionVectors) { action in
                        actionRow(action)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TrackedLabel(L10n.context, size: 10, kerning: 1.5)
                    Text(summary.context)
                        .font(AppFont.mono(size: 14, weight: .regular))
                        .foregroundStyle(colors.secondaryText)
                        .lineSpacing(5)
                }

                // Emails
                if !summary.emails.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TrackedLabel(L10n.emails, size: 10, kerning: 1.5)
                        ForEach(summary.emails) { email in
                            Button {
                                openMailto(recipient: email.recipient, subject: email.subject, body: email.body)
                            } label: {
                                smartActionCard(
                                    icon: "envelope.fill",
                                    iconColor: .blue,
                                    title: "Email \(email.recipient)",
                                    subtitle: email.subject,
                                    trailing: "arrow.up.right"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Reminders
                if !summary.reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TrackedLabel(L10n.reminders, size: 10, kerning: 1.5)
                        ForEach(Array(summary.reminders.enumerated()), id: \.element.id) { index, reminder in
                            Button {
                                if createdReminders.contains(index) { return }
                                if reminder.dueDate != nil {
                                    createReminder(index: index, title: reminder.title, dueDate: reminder.dueDate, recordingTitle: recording.title)
                                } else {
                                    datePickerDate = Date()
                                    pendingDatePickerItem = .reminder(index: index, title: reminder.title, recordingTitle: recording.title)
                                    showDatePicker = true
                                }
                            } label: {
                                smartActionCard(
                                    icon: createdReminders.contains(index) ? "checkmark.circle.fill" : "bell.fill",
                                    iconColor: createdReminders.contains(index) ? .green : .orange,
                                    title: reminder.title,
                                    subtitle: reminder.dueDescription,
                                    trailing: createdReminders.contains(index) ? nil : "plus.circle"
                                )
                            }
                            .buttonStyle(.plain)
                            .opacity(createdReminders.contains(index) ? 0.6 : 1)
                        }
                    }
                }

                // Calendar Events
                if !summary.calendarEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        TrackedLabel(L10n.calendarEvents, size: 10, kerning: 1.5)
                        ForEach(Array(summary.calendarEvents.enumerated()), id: \.element.id) { index, event in
                            Button {
                                if createdEvents.contains(index) { return }
                                if let eventDate = event.eventDate {
                                    createCalendarEvent(index: index, title: event.title, startDate: eventDate, duration: event.duration ?? 3600, recordingTitle: recording.title)
                                } else {
                                    datePickerDate = Date()
                                    pendingDatePickerItem = .calendarEvent(index: index, title: event.title, duration: event.duration ?? 3600, recordingTitle: recording.title)
                                    showDatePicker = true
                                }
                            } label: {
                                smartActionCard(
                                    icon: createdEvents.contains(index) ? "checkmark.circle.fill" : "calendar.badge.plus",
                                    iconColor: createdEvents.contains(index) ? .green : .purple,
                                    title: event.title,
                                    subtitle: event.dateDescription,
                                    trailing: createdEvents.contains(index) ? nil : "plus.circle"
                                )
                            }
                            .buttonStyle(.plain)
                            .opacity(createdEvents.contains(index) ? 0.6 : 1)
                        }
                    }
                }
            } else if recording.isSummarizing {
                callToAction(
                    icon: "brain",
                    title: "SUMMARIZING",
                    subtitle: "Distilling your meeting into key insights...",
                    action: nil
                )
            } else if recording.hasTranscript && recording.summarizationError != nil {
                VStack(spacing: 16) {
                    errorBanner(recording.summarizationError ?? "Unknown error")
                    callToAction(
                        icon: "brain",
                        title: "SUMMARIZATION FAILED",
                        subtitle: "Tap to retry distilling this transcript.",
                        action: ("RETRY SUMMARIZE", summarize)
                    )
                }
            } else if recording.hasTranscript {
                callToAction(
                    icon: "brain",
                    title: "READY TO DECODE",
                    subtitle: "Transcript available. Tap to distill key insights.",
                    action: ("SUMMARIZE", summarize)
                )
            } else if recording.isTranscribing {
                callToAction(
                    icon: "waveform.badge.magnifyingglass",
                    title: L10n.statusTranscribingTitle,
                    subtitle: L10n.processingRecording,
                    action: (L10n.cancel.uppercased(), cancelTranscription)
                )
            } else {
                callToAction(
                    icon: SubscriptionManager.shared.canTranscribeAtAll ? "waveform.badge.magnifyingglass" : "lock.fill",
                    title: SubscriptionManager.shared.canTranscribeAtAll ? L10n.notYetDecoded : L10n.transcriptionLocked,
                    subtitle: SubscriptionManager.shared.canTranscribeAtAll ? L10n.transcribeToExtract : L10n.upgradeToUnlockAI,
                    action: (SubscriptionManager.shared.canTranscribeAtAll ? L10n.transcribe.uppercased() : L10n.unlockTranscription, transcribe)
                )
            }
        }
    }

    // MARK: - Tab 2: Transcript

    /// Current segment index based on playback position
    private var currentSegmentIndex: Int? {
        guard sharedPlayer.isPlaying || sharedPlayer.currentTime > 0 else { return nil }
        return recording.segmentIndex(at: sharedPlayer.currentTime)
    }

    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let segments = recording.transcriptSegments, !segments.isEmpty {
                // On-device badge at the top of transcript
                if recording.wasTranscribedOnDevice == true {
                    HStack {
                        OnDeviceBadge(type: .transcription)
                        Spacer()
                    }
                    .padding(.bottom, 4)
                }
                
                // Speaker section — always show if there are speakers
                if !recording.uniqueSpeakers.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        TrackedLabel("\(recording.uniqueSpeakers.count) \(L10n.speakers.uppercased())", size: 10, kerning: 1.5)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recording.uniqueSpeakers, id: \.self) { speaker in
                                    Button {
                                        editingSpeaker = speaker
                                        editingSpeakerName = recording.displayName(for: speaker)
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 9))

                                            let displayName = recording.displayName(for: speaker)
                                            let isRenamed = displayName != speaker

                                            Text(displayName)
                                                .font(AppFont.mono(size: 11, weight: isRenamed ? .bold : .medium))
                                                .lineLimit(1)

                                            Image(systemName: "pencil")
                                                .font(.system(size: 8))
                                                .foregroundStyle(colors.secondaryText)
                                        }
                                        .foregroundStyle(colors.primaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .glassCard(radius: 100)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }

                Text("\(segments.count) \(L10n.segments)")
                    .font(AppFont.mono(size: 10, weight: .medium))
                    .kerning(1.0)
                    .foregroundStyle(colors.secondaryText)
                    .padding(.bottom, 4)

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    transcriptRow(segment, index: index, isActive: currentSegmentIndex == index, isHighlighted: highlightedSegmentIndex == index)
                        .id("segment_\(index)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                withAnimation { deleteSegment(at: index) }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                }
            } else if recording.isTranscribing {
                callToAction(
                    icon: "waveform.badge.magnifyingglass",
                    title: L10n.statusTranscribingTitle,
                    subtitle: L10n.processingRecording,
                    action: (L10n.cancel.uppercased(), cancelTranscription)
                )
            } else {
                callToAction(
                    icon: SubscriptionManager.shared.canTranscribeAtAll ? "text.alignleft" : "lock.fill",
                    title: SubscriptionManager.shared.canTranscribeAtAll ? L10n.noTranscriptTitle : L10n.transcriptionLocked,
                    subtitle: SubscriptionManager.shared.canTranscribeAtAll ? L10n.transcribeFirst : L10n.upgradeToUnlockTranscription,
                    action: (SubscriptionManager.shared.canTranscribeAtAll ? L10n.transcribe.uppercased() : L10n.unlockTranscription, transcribe)
                )
            }
        }
        .alert(L10n.renameSpeaker, isPresented: Binding(
            get: { editingSpeaker != nil },
            set: { if !$0 { editingSpeaker = nil } }
        )) {
            TextField(L10n.name, text: $editingSpeakerName)
            Button(L10n.save) {
                if let speaker = editingSpeaker {
                    var names = recording.speakerNames ?? [:]
                    let trimmed = editingSpeakerName.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        names.removeValue(forKey: speaker)
                    } else {
                        names[speaker] = trimmed
                    }
                    recording.speakerNames = names
                }
                editingSpeaker = nil
            }
            Button(L10n.cancel, role: .cancel) { editingSpeaker = nil }
        } message: {
            Text(L10n.enterSpeakerName)
        }
        .sheet(isPresented: Binding(
            get: { editingSegmentIndex != nil },
            set: { if !$0 { editingSegmentIndex = nil } }
        )) {
            if let index = editingSegmentIndex {
                TranscriptSegmentEditor(
                    text: $editingSegmentText,
                    speakerName: recording.displayName(for: recording.transcriptSegments?[index].speaker ?? ""),
                    timestamp: recording.transcriptSegments?[index].timestamp ?? 0,
                    onSave: {
                        recording.updateSegmentText(at: index, newText: editingSegmentText)
                        editingSegmentIndex = nil
                    },
                    onCancel: {
                        editingSegmentIndex = nil
                    }
                )
            }
        }
    }

    // MARK: - Tab 3: Notes

    private var notesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrackedLabel(L10n.meetingNotes, size: 10, kerning: 1.5)

            TextEditor(text: Binding(
                get: { recording.notes ?? "" },
                set: { recording.notes = $0.isEmpty ? nil : $0 }
            ))
            .font(AppFont.mono(size: 14, weight: .regular))
            .foregroundStyle(colors.primaryText)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 150)
            .padding(12)
            .glassCard(radius: 10)

            if recording.notes == nil || recording.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                Text(L10n.tapToAddNotes)
                    .font(AppFont.mono(size: 12, weight: .regular))
                    .foregroundStyle(colors.secondaryText)
                    .multilineTextAlignment(.leading)
            }

            // Image attachments section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TrackedLabel(L10n.attachments, size: 10, kerning: 1.5)
                    Spacer()
                    
                    // Add image buttons
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundStyle(colors.secondaryText)
                        }
                        
                        #if os(iOS)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Image(systemName: "camera")
                                    .font(.system(size: 16))
                                    .foregroundStyle(colors.secondaryText)
                            }
                        }
                        #endif
                    }
                }

                if let imageNames = recording.noteImageNames, !imageNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recording.noteImageURLs, id: \.absoluteString) { url in
                                NoteImageThumbnail(
                                    url: url,
                                    onTap: { image in
                                        selectedImageForOCR = (url, image)
                                    },
                                    onDelete: {
                                        deleteNoteImage(url: url)
                                    }
                                )
                            }
                        }
                    }
                } else {
                    Text(L10n.addPhotosDescription)
                        .font(AppFont.mono(size: 12, weight: .regular))
                        .foregroundStyle(colors.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .padding(.vertical, 8)
                }
            }

            if isProcessingImage {
                HStack {
                    ProgressView()
                        .tint(colors.primaryText)
                    Text(L10n.processingImage)
                        .font(AppFont.mono(size: 12))
                        .foregroundStyle(colors.secondaryText)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            if let item = newItem {
                processSelectedPhoto(item)
                selectedPhotoItem = nil
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                saveNoteImage(image)
            }
        }
        #endif
        .sheet(item: Binding(
            get: { selectedImageForOCR.map { ImageForOCR(url: $0.url, image: $0.image) } },
            set: { selectedImageForOCR = $0.map { ($0.url, $0.image) } }
        )) { item in
            ImageOCRSheet(
                image: item.image,
                onExtractText: { text in
                    appendTextToNotes(text)
                    selectedImageForOCR = nil
                }
            )
        }
    }

    // MARK: - Notes Image Helpers

    private func processSelectedPhoto(_ item: PhotosPickerItem) {
        isProcessingImage = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = PlatformImage(data: data) {
                await MainActor.run {
                    saveNoteImage(image)
                }
            }
            await MainActor.run {
                isProcessingImage = false
            }
        }
    }

    private func saveNoteImage(_ image: PlatformImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        let fileName = "\(recording.uid.uuidString)_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = Recording.notesImageDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: url)
            var names = recording.noteImageNames ?? []
            names.append(fileName)
            recording.noteImageNames = names
        } catch {
            print("Failed to save note image: \(error)")
        }
    }

    private func deleteNoteImage(url: URL) {
        let fileName = url.lastPathComponent
        try? FileManager.default.removeItem(at: url)
        
        var names = recording.noteImageNames ?? []
        names.removeAll { $0 == fileName }
        recording.noteImageNames = names.isEmpty ? nil : names
    }

    private func appendTextToNotes(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        if let existingNotes = recording.notes, !existingNotes.isEmpty {
            recording.notes = existingNotes + "\n\n--- Extracted from image ---\n" + trimmedText
        } else {
            recording.notes = trimmedText
        }
    }

    // MARK: - Tab 4: Audio (with real playback)

    private var audioTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !recording.amplitudeSamples.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    TrackedLabel(L10n.playback, size: 10, kerning: 1.5)
                    PlaybackWaveformView(
                        samples: recording.amplitudeSamples,
                        duration: recording.duration,
                        marks: recording.marks,
                        audioURL: recording.audioURL,
                        player: sharedPlayer
                    )
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                TrackedLabel(L10n.details, size: 10, kerning: 1.5)
                detailRow("FORMAT", value: "M4A / AAC")
                detailRow("SAMPLE RATE", value: "16 kHz")
                detailRow("CHANNELS", value: "Mono")
                detailRow("DURATION", value: recording.duration.formatted)
                if let fileName = recording.audioFileName {
                    detailRow("FILE", value: fileName)
                }
                detailRow("FILE SIZE", value: audioFileSize)
            }

            // Audio compression / export
            VStack(alignment: .leading, spacing: 12) {
                TrackedLabel(L10n.exportCompressed, size: 10, kerning: 1.5)

                Text(L10n.reencodeDescription)
                    .font(AppFont.mono(size: 11))
                    .foregroundStyle(colors.secondaryText)
                    .lineSpacing(3)

                if isCompressing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(colors.primaryText)
                        Text(L10n.compressing)
                            .font(AppFont.mono(size: 11))
                            .foregroundStyle(colors.secondaryText)
                    }
                } else {
                    HStack(spacing: 8) {
                        compressionButton(label: "LOW", bitrate: 32_000)
                        compressionButton(label: "MED", bitrate: 64_000)
                        compressionButton(label: "HIGH", bitrate: 128_000)
                    }
                }

                if let result = compressionResult {
                    Text(result)
                        .font(AppFont.mono(size: 10))
                        .foregroundStyle(colors.secondaryText)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var audioFileSize: String {
        guard let url = recording.audioURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func compressionButton(label: String, bitrate: Int) -> some View {
        Button {
            compressAudio(bitrate: bitrate)
        } label: {
            Text(label)
                .font(AppFont.mono(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(colors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .glassCard(radius: 8)
        }
    }

    private func compressAudio(bitrate: Int) {
        guard let sourceURL = recording.audioURL else { return }
        isCompressing = true
        compressionResult = nil

        Task {
            do {
                let asset = AVURLAsset(url: sourceURL)
                _ = try await asset.load(.duration)

                let tempDir = FileManager.default.temporaryDirectory
                let outputName = "\(recording.title)_\(bitrate / 1000)kbps.m4a"
                let outputURL = tempDir.appendingPathComponent(outputName)

                // Remove existing temp file if any
                try? FileManager.default.removeItem(at: outputURL)

                guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                    await MainActor.run {
                        isCompressing = false
                        compressionResult = "Export not available."
                    }
                    return
                }

                exportSession.outputURL = outputURL
                exportSession.outputFileType = .m4a
                exportSession.audioTimePitchAlgorithm = .varispeed

                do {
                    try await exportSession.export(to: outputURL, as: .m4a)
                    
                    // Get compressed size
                    let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                    let size = attrs[.size] as? Int64 ?? 0
                    let formatter = ByteCountFormatter()
                    formatter.allowedUnits = [.useKB, .useMB]
                    formatter.countStyle = .file
                    let sizeStr = formatter.string(fromByteCount: size)

                    await MainActor.run {
                        isCompressing = false
                        compressionResult = "Compressed to \(sizeStr)"
                        shareItems = [outputURL]
                        showShareSheet = true
                    }
                } catch {
                    await MainActor.run {
                        isCompressing = false
                        compressionResult = "Compression failed: \(error.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    isCompressing = false
                    compressionResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Subviews

    private func actionRow(_ action: ActionVector) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .stroke(Color.white.opacity(action.isCompleted ? 1 : 0.25), lineWidth: 1.5)
                .background(Circle().fill(action.isCompleted ? Color.white : Color.clear))
                .frame(width: 20, height: 20)
                .overlay {
                    if action.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(action.task)
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                    .lineSpacing(3)
                Text(action.assignee)
                    .font(AppFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, AppLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Smart Action Helpers

    private func smartActionCard(icon: String, iconColor: Color, title: String, subtitle: String, trailing: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                    .lineSpacing(3)
                Text(subtitle)
                    .font(AppFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(colors.secondaryText)
            }

            Spacer()

            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 16))
                    .foregroundStyle(colors.secondaryText)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, AppLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func openMailto(recipient: String, subject: String, body: String) {
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:?subject=\(subjectEncoded)&body=\(bodyEncoded)") {
            #if canImport(UIKit)
            UIApplication.shared.open(url)
            #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
        showActionToastMessage("Opening Mail...")
    }

    private func createReminder(index: Int, title: String, dueDate: Date?, recordingTitle: String) {
        Task {
            do {
                try await EventKitService.shared.createReminder(
                    title: title,
                    dueDate: dueDate,
                    notes: "From Trace recording: \(recordingTitle)"
                )
                createdReminders.insert(index)
                showActionToastMessage("Reminder created")
            } catch {
                showActionToastMessage("Failed: \(error.localizedDescription)")
            }
        }
    }

    private func createCalendarEvent(index: Int, title: String, startDate: Date, duration: TimeInterval, recordingTitle: String) {
        Task {
            do {
                try await EventKitService.shared.createCalendarEvent(
                    title: title,
                    startDate: startDate,
                    duration: duration,
                    notes: "From Trace recording: \(recordingTitle)"
                )
                createdEvents.insert(index)
                showActionToastMessage("Event added to calendar")
            } catch {
                showActionToastMessage("Failed: \(error.localizedDescription)")
            }
        }
    }

    private func showActionToastMessage(_ text: String) {
        actionToastText = text
        withAnimation(.easeInOut(duration: 0.25)) {
            showActionToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.25)) {
                showActionToast = false
            }
        }
    }

    private func transcriptRow(_ segment: SegmentData, index: Int, isActive: Bool, isHighlighted: Bool = false) -> some View {
        let bgColor: Color = isHighlighted ? Color.yellow.opacity(0.15) : (isActive ? colors.selection : Color.clear)
        let borderColor: Color = isHighlighted ? Color.yellow.opacity(0.4) : (isActive ? colors.selection : Color.clear)
        let textColor: Color = isActive ? colors.primaryText : colors.secondaryText

        return transcriptRowContent(segment, index: index, isActive: isActive, textColor: textColor)
            .padding(.vertical, 10)
            .padding(.horizontal, AppLayout.cardPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                if sharedPlayer.duration > 0 {
                    let fraction = CGFloat(segment.timestamp / sharedPlayer.duration)
                    sharedPlayer.seek(to: fraction)
                    if !sharedPlayer.isPlaying {
                        sharedPlayer.play()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(bgColor))
            .glassCard(radius: 10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: 1))
            .animation(.easeOut(duration: 0.5), value: isHighlighted)
    }

    @ViewBuilder
    private func transcriptRowContent(_ segment: SegmentData, index: Int, isActive: Bool, textColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.primaryText)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
                }

                if !segment.speaker.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(recording.displayName(for: segment.speaker))
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                }

                Text(segment.timestamp.formatted)
                    .font(AppFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(colors.mutedText)

                Spacer()

                Button {
                    editingSegmentIndex = index
                    editingSegmentText = segment.text
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(colors.secondaryText)
                }
            }

            Text(segment.text)
                .font(AppFont.mono(size: 14, weight: .regular))
                .foregroundStyle(textColor)
                .lineSpacing(4)
        }
    }

    private func callToAction(icon: String, title: String, subtitle: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            Image(systemName: icon)
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(colors.mutedText)

            Text(title)
                .font(AppFont.mono(size: 13, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(colors.mutedText)

            Text(subtitle)
                .font(AppFont.mono(size: 12, weight: .regular))
                .foregroundStyle(colors.secondaryText)
                .multilineTextAlignment(.center)

            if let (label, fn) = action {
                Button(action: fn) {
                    Text(label)
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppFont.mono(size: 12, weight: .medium))
                .foregroundStyle(colors.secondaryText)
            Spacer()
            Text(value)
                .font(AppFont.mono(size: 12, weight: .bold))
                .foregroundStyle(colors.primaryText)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, AppLayout.cardPadding)
        .glassCard(radius: 8)
    }

    // MARK: - Actions

    private func cancelTranscription() {
        TranscriptionService.shared.cancelTranscription()
        recording.isTranscribing = false
        recording.transcriptionError = nil
        recording.transcriptionProgress = 0
    }

    private func deleteTranscript() {
        recording.transcriptFullText = nil
        recording.transcriptSegments = nil
        recording.transcriptLanguage = nil
        recording.wasTranscribedOnDevice = nil
        recording.transcriptionError = nil
        // Also clear summary since it depends on transcript
        recording.summaryOneLiner = nil
        recording.summaryContext = nil
        recording.summaryActions = nil
        recording.summarySources = nil
        recording.summaryEmails = nil
        recording.summaryReminders = nil
        recording.summaryCalendarEvents = nil
        recording.wasSummarizedOnDevice = nil
        recording.summarizationError = nil
        recording.speakerNames = nil
    }

    private func deleteSegment(at index: Int) {
        guard var segments = recording.transcriptSegments, index >= 0, index < segments.count else { return }
        segments.remove(at: index)
        recording.transcriptSegments = segments.isEmpty ? nil : segments
        recording.transcriptFullText = segments.isEmpty ? nil : segments.map { $0.text }.joined(separator: " ")
    }

    private func transcribe() {
        guard recording.audioURL != nil else { return }

        // Check if user is subscribed (free users must upgrade to transcribe)
        let subscription = SubscriptionManager.shared
        if !subscription.canTranscribeAtAll {
            showPaywall = true
            return
        }

        // Check if on-device transcription is available for preferred language - if so, show chooser
        if OnDeviceTranscriptionService.shared.isOnDeviceAvailableForPreferredLanguage {
            showTranscriptionChooser = true
            return
        }

        // Otherwise, use cloud transcription directly
        performTranscription(useOnDevice: false)
    }
    
    private func performTranscription(useOnDevice: Bool) {
        guard let url = recording.audioURL else { return }
        
        print("🚀 [PerformTranscription] Starting with useOnDevice: \(useOnDevice)")
        
        // Check subscription limits (only for cloud)
        if !useOnDevice {
            let subscription = SubscriptionManager.shared
            if !subscription.canTranscribe(duration: recording.duration) {
                subscriptionLimitError = "You've reached your monthly transcription limit. Upgrade to continue."
                showPaywall = true
                print("❌ [PerformTranscription] Subscription limit reached")
                return
            }
        }

        recording.isTranscribing = true
        recording.transcriptionError = nil
        recording.transcriptionProgress = 0
        
        print("📝 [PerformTranscription] Set isTranscribing = true, starting Task")

        Task {
            do {
                print("🔄 [PerformTranscription] Calling transcribeAuto with forceOnDevice: \(useOnDevice)")
                let result = try await TranscriptionService.shared.transcribeAuto(
                    fileURL: url,
                    forceOnDevice: useOnDevice,
                    progressFraction: { fraction in
                        Task { @MainActor in
                            withAnimation { recording.transcriptionProgress = fraction }
                        }
                    }
                )

                recording.transcriptFullText = result.transcript.fullText
                recording.transcriptSegments = result.transcript.segments.map {
                    SegmentData(speaker: $0.speaker, text: $0.text, timestamp: $0.timestamp)
                }
                recording.transcriptLanguage = result.response.language_code
                recording.wasTranscribedOnDevice = result.wasOnDevice
                recording.isTranscribing = false
                recording.transcriptionProgress = 0

                // Record usage (only for cloud transcription)
                if !result.wasOnDevice {
                    SubscriptionManager.shared.recordTranscriptionUsage(seconds: recording.duration)
                }

                // Send transcription complete notification
                NotificationService.shared.notifyTranscriptionComplete(
                    recordingTitle: recording.title,
                    recordingUID: recording.uid,
                    detectedLanguage: result.detectedLanguage,
                    wasOnDevice: result.wasOnDevice
                )

                // Auto-chain into summarization
                summarize()
            } catch is CancellationError {
                recording.isTranscribing = false
                recording.transcriptionProgress = 0
            } catch let error as TranscriptionError where error == .cancelled {
                recording.isTranscribing = false
                recording.transcriptionProgress = 0
            } catch let error as OnDeviceTranscriptionError where error == .cancelled {
                recording.isTranscribing = false
                recording.transcriptionProgress = 0
            } catch {
                recording.isTranscribing = false
                recording.transcriptionProgress = 0
                recording.transcriptionError = error.localizedDescription
                logger.error("Transcription failed for '\(recording.title)': \(error.localizedDescription)")

                // Send failure notification
                NotificationService.shared.notifyTranscriptionFailed(
                    recordingTitle: recording.title,
                    recordingUID: recording.uid,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    private func summarize() {
        guard let transcriptText = recording.transcriptFullText else { return }
        
        // Check if user has access to AI summarization
        if !FeatureGate.canAccess(.aiSummarization) {
            showPaywall = true
            return
        }

        recording.isSummarizing = true
        recording.summarizationError = nil

        Task {
            do {
                let result = try await SummarizationService.shared.summarizeAuto(
                    transcript: transcriptText,
                    meetingNotes: recording.notes,
                    language: recording.transcriptLanguage
                )

                recording.summaryOneLiner = result.oneLiner
                recording.summaryContext = result.context
                recording.summaryActions = result.actions
                recording.summarySources = result.sources
                recording.summaryEmails = result.emails
                recording.summaryReminders = result.reminders
                recording.summaryCalendarEvents = result.calendarEvents
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
                logger.error("Summarization failed for '\(recording.title)': \(error.localizedDescription)")
            }
        }
    }

    /// Format transcript with speaker names and timestamps for sharing/copying
    private func formattedTranscriptText() -> String? {
        // If we have segments with speaker info, build a formatted version
        if let segments = recording.transcriptSegments, !segments.isEmpty {
            let speakerNames = recording.speakerNames ?? [:]
            var result = ""
            var previousSpeaker: String? = nil

            for segment in segments {
                let speaker = speakerNames[segment.speaker] ?? segment.speaker
                let timestamp = segment.timestamp.formatted

                // Add speaker header when speaker changes or at the start
                if speaker != previousSpeaker && !speaker.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !result.isEmpty { result += "\n" }
                    result += "[\(timestamp)] \(speaker):\n"
                }

                result += "\(segment.text)\n"
                previousSpeaker = speaker
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Fallback to plain text
        return recording.transcriptFullText
    }

    private func copyTranscript() {
        guard let text = formattedTranscriptText() else { return }
        UIPasteboard.general.string = text
        withAnimation(.easeInOut(duration: 0.25)) {
            showCopiedToast = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.25)) {
                showCopiedToast = false
            }
        }
    }
    
    private func shareAudio() {
        guard let url = recording.audioURL else {
            print("❌ No audio URL available for sharing")
            return
        }
        
        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Audio file doesn't exist at: \(url.path)")
            return
        }
        
        // Get file size for logging
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            print("✅ Sharing audio file: \(url.lastPathComponent) (\(fileSize) bytes)")
        }
        
        shareItems = [url]
        showShareSheet = true
    }
    
    private func exportAsMarkdown() {
        let markdown = ExportService.shared.exportAsMarkdown(recording: recording)
        shareItems = [markdown]
        showShareSheet = true
    }
    
    private func exportAsPDF() {
        if let pdfData = ExportService.shared.exportAsPDF(recording: recording) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(recording.title).pdf")
            try? pdfData.write(to: tempURL)
            shareItems = [tempURL]
            showShareSheet = true
        }
    }
    
    private func shareTracePackage() {
        if let packageURL = TracePackageExporter.shared.createTracePackage(recording: recording) {
            shareItems = [packageURL]
            showShareSheet = true
            
            // Clean up after sharing completes (delayed)
            Task {
                try? await Task.sleep(for: .seconds(60))
                TracePackageExporter.shared.cleanupPackage(at: packageURL)
            }
        }
    }

    // MARK: - Formatters

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Playback Waveform View (with real audio)

struct PlaybackWaveformView: View {
    @Environment(\.colorScheme) private var colorScheme
    let samples: [Float]
    let duration: TimeInterval
    let marks: [TimeInterval]
    let audioURL: URL?
    @Bindable var player: AudioPlayer

    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Waveform with scrub
            GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = 64

                ZStack(alignment: .leading) {
                    Canvas { context, size in
                        let count = samples.count
                        guard count > 0 else { return }
                        let gap: CGFloat = 1.5
                        let barWidth = max(1.5, (size.width - CGFloat(count - 1) * gap) / CGFloat(count))

                        for i in 0..<count {
                            let x = CGFloat(i) * (barWidth + gap)
                            let normalizedPos = CGFloat(i) / CGFloat(count)
                            let isPast = normalizedPos <= player.progress
                            let barHeight = max(2, CGFloat(samples[i]) * height)
                            let y = (height - barHeight) / 2

                            let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                            let path = Path(roundedRect: rect, cornerRadius: 1)
                            context.fill(path, with: .color(colors.primaryText.opacity(isPast ? 0.7 : 0.12)))
                        }

                        // Draw mark indicators
                        for mark in marks {
                            guard duration > 0 else { continue }
                            let markX = CGFloat(mark / duration) * size.width
                            let markRect = CGRect(x: markX - 0.5, y: 0, width: 1, height: size.height)
                            context.fill(Path(markRect), with: .color(colors.primaryText.opacity(0.4)))
                        }
                    }
                    .frame(height: height)

                    // Playback scrub line
                    Rectangle()
                        .fill(colors.primaryText)
                        .frame(width: 2, height: height + 16)
                        .offset(x: player.progress * width - 1)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / width))
                            player.seek(to: fraction)
                        }
                )
            }
            .frame(height: 80)

            // Transport controls
            HStack(spacing: 0) {
                // Current time
                Text(AudioPlayer.formatTime(player.currentTime))
                    .font(AppFont.mono(size: 12, weight: .bold))
                    .foregroundStyle(colors.primaryText)
                    .frame(width: 54, alignment: .leading)

                Spacer()

                // Skip back 15s
                Button {
                    let newTime = max(0, player.currentTime - 15)
                    player.seek(to: CGFloat(newTime / max(1, duration)))
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 40, height: 40)
                        .glassCard(radius: 20)
                }

                Spacer().frame(width: 16)

                // Play / Pause
                Button {
                    player.togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(colors.primaryText)
                            .frame(width: 48, height: 48)

                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(colors.background)
                            .offset(x: player.isPlaying ? 0 : 2)
                    }
                }

                Spacer().frame(width: 16)

                // Skip forward 15s
                Button {
                    let newTime = min(duration, player.currentTime + 15)
                    player.seek(to: CGFloat(newTime / max(1, duration)))
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colors.secondaryText)
                        .frame(width: 40, height: 40)
                        .glassCard(radius: 20)
                }

                Spacer()

                // Total duration
                Text(AudioPlayer.formatTime(duration))
                    .font(AppFont.mono(size: 12, weight: .regular))
                    .foregroundStyle(colors.secondaryText)
                    .frame(width: 54, alignment: .trailing)
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            if let url = audioURL {
                player.load(url: url)
            }
        }
        .onDisappear {
            player.stop()
        }
    }
}

// MARK: - Image Support Types

/// Identifiable wrapper for image OCR sheet presentation
struct ImageForOCR: Identifiable {
    let id = UUID()
    let url: URL
    let image: PlatformImage
}

/// Thumbnail view for note images with tap and delete actions
struct NoteImageThumbnail: View {
    let url: URL
    let onTap: (PlatformImage) -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var loadedImage: PlatformImage?
    
    private var colors: AppColors { AppColors(colorScheme: colorScheme) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = loadedImage {
                    #if canImport(UIKit)
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTap(image)
                        }
                    #elseif canImport(AppKit)
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onTap(image)
                        }
                    #endif
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .overlay {
                            ProgressView()
                                .tint(.white)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colors.glassBorder, lineWidth: AppLayout.glassBorderWidth)
            )

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        Task {
            if let data = try? Data(contentsOf: url),
               let image = PlatformImage(data: data) {
                await MainActor.run {
                    loadedImage = image
                }
            }
        }
    }
}

#if os(iOS)
/// Camera view using UIImagePickerController (iOS only)
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif

/// Sheet for viewing an image and extracting text via OCR
struct ImageOCRSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: PlatformImage
    let onExtractText: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }

    @State private var extractedText: String?
    @State private var isExtracting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Image preview
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.glassBorder, lineWidth: AppLayout.glassBorderWidth)
                    )
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(colors.glassBorder, lineWidth: AppLayout.glassBorderWidth)
                    )
                #endif

                if isExtracting {
                    HStack {
                        ProgressView()
                            .tint(colors.primaryText)
                        Text(L10n.extractingText)
                            .font(AppFont.mono(size: 14))
                            .foregroundStyle(colors.secondaryText)
                    }
                    .padding()
                } else if let text = extractedText {
                    VStack(alignment: .leading, spacing: 12) {
                        TrackedLabel(L10n.extractedText, size: 10, kerning: 1.5)

                        ScrollView {
                            Text(text.isEmpty ? "No text found in image." : text)
                                .font(AppFont.mono(size: 14))
                                .foregroundStyle(text.isEmpty ? colors.secondaryText : colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .padding(12)
                        .glassCard(radius: 10)

                        if !text.isEmpty {
                            Button {
                                onExtractText(text)
                            } label: {
                                Text(L10n.addToNotes)
                                    .font(AppFont.mono(size: 12, weight: .bold))
                                    .kerning(1.5)
                                    .foregroundStyle(colors.background)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(colors.primaryText)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } else if let error = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(colors.secondaryText)
                        Text(error)
                            .font(AppFont.mono(size: 14))
                            .foregroundStyle(colors.secondaryText)
                            .multilineTextAlignment(.center)

                        Button(L10n.retry) {
                            extractText()
                        }
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .glassCard(radius: 20)
                    }
                } else {
                    Button {
                        extractText()
                    } label: {
                        HStack {
                            Image(systemName: "text.viewfinder")
                            Text(L10n.extractText)
                        }
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(colors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(colors.primaryText)
                        .clipShape(Capsule())
                    }
                }

                Spacer()
            }
            .padding()
            .background(colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.image)
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done) {
                        dismiss()
                    }
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                }
            }
        }
    }

    private func extractText() {
        isExtracting = true
        error = nil

        Task {
            do {
                let text = try await OCRService.shared.recognizeText(in: image)
                await MainActor.run {
                    extractedText = text
                    isExtracting = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isExtracting = false
                }
            }
        }
    }
}

// MARK: - Transcript Segment Editor

struct TranscriptSegmentEditor: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    let speakerName: String
    let timestamp: TimeInterval
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Segment info
                HStack(spacing: 12) {
                    if !speakerName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(colors.secondaryText)
                        Text(speakerName)
                            .font(AppFont.mono(size: 14, weight: .bold))
                            .foregroundStyle(colors.primaryText)
                    }

                    Text(timestamp.formatted)
                        .font(AppFont.mono(size: 12))
                        .foregroundStyle(colors.secondaryText)
                }
                .padding(.horizontal)
                
                // Text editor
                VStack(alignment: .leading, spacing: 8) {
                    TrackedLabel(L10n.transcriptText, size: 10, kerning: 1.5)
                        .padding(.horizontal)
                    
                    TextEditor(text: $text)
                        .font(AppFont.mono(size: 14))
                        .foregroundStyle(colors.primaryText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 200)
                        .padding(12)
                        .glassCard(radius: 10)
                        .padding(.horizontal)
                        .focused($isTextFieldFocused)
                }
                
                Spacer()
                
                // Save button
                Button {
                    onSave()
                    dismiss()
                } label: {
                    Text(L10n.saveChanges)
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(colors.background)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(colors.primaryText)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top)
            .background(colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.editSegment)
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(colors.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        onCancel()
                        dismiss()
                    }
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Transcription Method Chooser

struct TranscriptionMethodChooser: View {
    @Environment(\.colorScheme) private var colorScheme
    let recordingDuration: TimeInterval
    let onChooseApple: () -> Void
    let onChooseAPI: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var colors: AppColors {
        AppColors(colorScheme: colorScheme)
    }
    
    private var subscription: SubscriptionManager { SubscriptionManager.shared }
    private var isOnDeviceAvailable: Bool { OnDeviceTranscriptionService.shared.isOnDeviceAvailable }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(colors.primaryText)
                    
                    Text(L10n.chooseTranscriptionMethod)
                        .font(AppFont.mono(size: 16, weight: .bold))
                        .foregroundStyle(colors.primaryText)
                    
                    Text(L10n.selectTranscriptionMethod)
                        .font(AppFont.mono(size: 12))
                        .foregroundStyle(colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Options
                VStack(spacing: 12) {
                    // Apple On-Device Option
                    // Only show on-device option if user has Standard+ AND device supports it
                    if FeatureGate.canAccess(.onDeviceTranscription) && isOnDeviceAvailable {
                        Button {
                            onChooseApple()
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 20))
                                        .foregroundStyle(colors.primaryText)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(L10n.appleOnDevice)
                                            .font(AppFont.mono(size: 13, weight: .bold))
                                            .kerning(1.0)
                                            .foregroundStyle(colors.primaryText)
                                        
                                        Text(L10n.privateAndUnlimited)
                                            .font(AppFont.mono(size: 11))
                                            .foregroundStyle(colors.secondaryText)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(L10n.included)
                                            .font(AppFont.mono(size: 11, weight: .bold))
                                            .foregroundStyle(.green)
                                        
                                        Text(L10n.unlimited)
                                            .font(AppFont.mono(size: 10))
                                            .foregroundStyle(colors.secondaryText)
                                    }
                                }
                                
                                // Features
                                HStack(spacing: 16) {
                                    featureTag(icon: "lock.fill", text: "Private")
                                    featureTag(icon: "iphone", text: "On-Device")
                                    featureTag(icon: "bolt.fill", text: "Fast")
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassCard(radius: 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(colors.glassBorder, lineWidth: 1)
                            )
                        }
                    }
                    
                    // ElevenLabs API Option
                    Button {
                        onChooseAPI()
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(colors.primaryText)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.elevenlabsAPI)
                                        .font(AppFont.mono(size: 13, weight: .bold))
                                        .kerning(1.0)
                                        .foregroundStyle(colors.primaryText)
                                    
                                    Text(L10n.higherAccuracy)
                                        .font(AppFont.mono(size: 11))
                                        .foregroundStyle(colors.secondaryText)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(subscription.remainingTranscriptionLabel)
                                        .font(AppFont.mono(size: 11, weight: .bold))
                                        .foregroundStyle(subscription.remainingTranscriptionSeconds > recordingDuration ? colors.primaryText : .orange)
                                    
                                    // Usage bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(colors.surface)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(usageColor)
                                                .frame(width: geo.size.width * (1 - subscription.usagePercentage))
                                        }
                                    }
                                    .frame(width: 60, height: 4)
                                }
                            }
                            
                            // Features
                            HStack(spacing: 16) {
                                featureTag(icon: "waveform", text: "Accurate")
                                featureTag(icon: "person.2.fill", text: "Speakers")
                                featureTag(icon: "globe", text: "99 Languages")
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(radius: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(colors.glassBorder, lineWidth: 1)
                        )
                    }
                    .disabled(!subscription.canTranscribe(duration: recordingDuration))
                    .opacity(subscription.canTranscribe(duration: recordingDuration) ? 1 : 0.5)
                    
                    if !subscription.canTranscribe(duration: recordingDuration) {
                        Text(L10n.notEnoughUsage)
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                
                // Usage info
                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.monthlyAPIUsage)
                            .font(AppFont.mono(size: 11))
                            .foregroundStyle(colors.secondaryText)
                        Spacer()
                        Text("\(subscription.currentTier.displayName) \(L10n.plan)")
                            .font(AppFont.mono(size: 11, weight: .medium))
                            .foregroundStyle(colors.primaryText)
                    }
                    
                    // Full-width usage bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colors.surface)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(usageColor)
                                .frame(width: geo.size.width * subscription.usagePercentage)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        Text(formatDuration(subscription.usage.transcriptionSecondsUsed) + " used")
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(colors.secondaryText)
                        Spacer()
                        Text(subscription.currentTier.transcriptionLimitLabel)
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(colors.secondaryText)
                    }
                }
                .padding()
                .glassCard(radius: 10)
                .padding(.horizontal)
                
                Spacer()
            }
            .background(colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.transcribe.uppercased())
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(colors.primaryText)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        dismiss()
                    }
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private var usageColor: Color {
        if subscription.usagePercentage > 0.9 {
            return .red
        } else if subscription.usagePercentage > 0.7 {
            return .orange
        } else {
            return .green
        }
    }
    
    private func featureTag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(AppFont.mono(size: 9))
        }
        .foregroundStyle(colors.secondaryText)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    NavigationStack {
        DecodedView(recording: {
            let r = Recording(title: "Preview Recording", duration: 1200, amplitudeSamples: (0..<40).map { _ in Float.random(in: 0.1...0.9) })
            return r
        }())
    }
    .modelContainer(for: Recording.self, inMemory: true)
}
