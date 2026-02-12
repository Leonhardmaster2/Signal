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

private let logger = Logger(subsystem: "com.Proceduralabs.Signal", category: "Transcription")

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
    @State private var showAskYourAudio = false
    @State private var showAudioSearch = false
    @State private var showExportOptions = false
    
    // Transcription method chooser
    @State private var showTranscriptionChooser = false

    // Audio compression
    @State private var isCompressing = false
    @State private var compressionResult: String?
    
    // Adaptive layout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                    Text("COPIED")
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .glassCard(radius: 8)
                        .padding(.bottom, 40)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("DECODED")
                    .font(AppFont.mono(size: 13, weight: .semibold))
                    .kerning(2.0)
                    .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                toolbarMenu
            }
        }
        .alert("Delete Transcript?", isPresented: $showDeleteTranscriptConfirmation) {
            Button("Delete", role: .destructive) {
                deleteTranscript()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the transcript and summary. The audio recording will be kept.")
        }
        .alert("Rename Recording", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    recording.title = trimmed
                    // Also rename the audio file if desired
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a new name for this recording.")
        }
        .alert("Delete Recording?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let url = recording.audioURL {
                    try? FileManager.default.removeItem(at: url)
                }
                modelContext.delete(recording)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the recording and its audio file.")
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showAskYourAudio) {
            AskYourAudioView(recording: recording)
        }
        .sheet(isPresented: $showAudioSearch) {
            AudioSearchView(recording: recording)
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
                sharedPlayer.load(url: url)
            }
        }
        .onDisappear {
            sharedPlayer.stop()
        }
    }
    
    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
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

            tabSelector
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.bottom, 24)

            ScrollView {
                Group {
                    switch selectedTab {
                    case 0: distillationTab
                    case 1: transcriptTab
                    case 2: notesTab
                    case 3: audioTab
                    default: EmptyView()
                    }
                }
                .padding(.horizontal, AppLayout.horizontalPadding)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
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
                                context.fill(path, with: .color(.white.opacity(isPast ? 0.6 : 0.1)))
                            }
                        } else {
                            // No waveform data — show simple progress bar
                            let trackRect = CGRect(x: 0, y: size.height / 2 - 1.5, width: size.width, height: 3)
                            context.fill(Path(roundedRect: trackRect, cornerRadius: 1.5), with: .color(.white.opacity(0.08)))

                            let prog = sharedPlayer.progress
                            if prog > 0 {
                                let fillRect = CGRect(x: 0, y: size.height / 2 - 1.5, width: size.width * prog, height: 3)
                                context.fill(Path(roundedRect: fillRect, cornerRadius: 1.5), with: .color(.white.opacity(0.5)))
                            }
                        }
                    }
                    .frame(height: height)

                    // Scrub line
                    if sharedPlayer.progress > 0 {
                        Rectangle()
                            .fill(Color.white)
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
                .foregroundStyle(.gray)
                .frame(width: 42, alignment: .trailing)

            // Skip forward 15s
            Button {
                let newTime = min(recording.duration, sharedPlayer.currentTime + 15)
                sharedPlayer.seek(to: CGFloat(newTime / max(1, recording.duration)))
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
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
                            TrackedLabel("PLAYBACK", size: 10, kerning: 1.5)
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
                            TrackedLabel("TRANSCRIPT", size: 10, kerning: 1.5)
                            if recording.wasTranscribedOnDevice == true {
                                OnDeviceBadge(type: .transcription, compact: true)
                            }
                        }
                        
                        ScrollView {
                            wideTranscriptContent
                        }
                        .frame(maxHeight: .infinity)
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
                            TrackedLabel("DISTILLATION", size: 10, kerning: 1.5)
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
                        TrackedLabel("NOTES", size: 10, kerning: 1.5)
                        
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
                        .foregroundStyle(.white)
                    
                    if recording.isStarred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                }
                
                HStack(spacing: 16) {
                    Label(formattedDate(recording.date), systemImage: "calendar")
                    Label(recording.duration.durationLabel, systemImage: "clock")
                    if let lang = recording.transcriptLanguage {
                        Label(lang.uppercased(), systemImage: "globe")
                    }
                    if recording.uniqueSpeakers.count > 0 {
                        Label("\(recording.uniqueSpeakers.count) speakers", systemImage: "person.2.fill")
                    }
                }
                .font(AppFont.mono(size: 12, weight: .regular))
                .foregroundStyle(.gray)
            }
            
            Spacer()
            
            // Status / actions
            HStack(spacing: 12) {
                if recording.isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        Text("TRANSCRIBING")
                            .font(AppFont.mono(size: 11, weight: .semibold))
                            .kerning(1.0)
                            .foregroundStyle(.white)

                        if (recording.transcriptionProgress ?? 0) > 0 {
                            Text("\(Int((recording.transcriptionProgress ?? 0) * 100))%")
                                .font(AppFont.mono(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Button {
                            cancelTranscription()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassCard(radius: 8)
                } else if recording.isSummarizing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        Text("SUMMARIZING")
                            .font(AppFont.mono(size: 11, weight: .semibold))
                            .kerning(1.0)
                            .foregroundStyle(.white)
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
                            Text(SubscriptionManager.shared.canTranscribeAtAll ? "TRANSCRIBE" : "UNLOCK TRANSCRIPTION")
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
                        Text("SUMMARIZE")
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
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
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
                    wideTranscriptRow(segment, index: index, isActive: currentSegmentIndex == index)
                }
            }
        } else if recording.isTranscribing {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Transcribing...")
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(.gray)

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
                            .foregroundStyle(.gray)
                    }
                }

                Button {
                    cancelTranscription()
                } label: {
                    Text("CANCEL")
                        .font(AppFont.mono(size: 10, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(Color.muted)
                Text("No transcript yet")
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    private func wideTranscriptRow(_ segment: SegmentData, index: Int, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp + play indicator
            VStack(alignment: .trailing, spacing: 4) {
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
                }
                Text(segment.timestamp.formatted)
                    .font(AppFont.mono(size: 10, weight: .regular))
                    .foregroundStyle(Color.muted)
            }
            .frame(width: 50, alignment: .trailing)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                if !segment.speaker.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(recording.displayName(for: segment.speaker))
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(segment.text)
                    .font(AppFont.mono(size: 13, weight: .regular))
                    .foregroundStyle(isActive ? .white : .gray)
                    .lineSpacing(3)
            }
            
            Spacer()
            
            // Edit button
            Button {
                editingSegmentIndex = index
                editingSegmentText = segment.text
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isActive ? Color.white.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    private var wideDistillationContent: some View {
        if let summary = recording.summary {
            VStack(alignment: .leading, spacing: 20) {
                // One-liner
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE ONE-LINER")
                        .font(AppFont.mono(size: 9, weight: .medium))
                        .kerning(1.0)
                        .foregroundStyle(.gray)
                    Text(summary.oneLiner)
                        .font(AppFont.mono(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .lineSpacing(3)
                }
                
                // Action vectors
                if !summary.actionVectors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTION VECTORS")
                            .font(AppFont.mono(size: 9, weight: .medium))
                            .kerning(1.0)
                            .foregroundStyle(.gray)
                        
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
                                        .foregroundStyle(.white)
                                    Text(action.assignee)
                                        .font(AppFont.mono(size: 10, weight: .regular))
                                        .foregroundStyle(.gray)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                
                // Context
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTEXT")
                        .font(AppFont.mono(size: 9, weight: .medium))
                        .kerning(1.0)
                        .foregroundStyle(.gray)
                    Text(summary.context)
                        .font(AppFont.mono(size: 13, weight: .regular))
                        .foregroundStyle(.gray)
                        .lineSpacing(4)
                }
            }
        } else if recording.isSummarizing {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Summarizing...")
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if recording.hasTranscript {
            VStack(spacing: 12) {
                Image(systemName: "brain")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(Color.muted)
                Text("Ready to summarize")
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "brain")
                    .font(.system(size: 24, weight: .thin))
                    .foregroundStyle(Color.muted)
                Text("Transcribe first to unlock summarization")
                    .font(AppFont.mono(size: 12))
                    .foregroundStyle(.gray)
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
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 100)
            .padding(10)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Image attachments
            HStack {
                Text("ATTACHMENTS")
                    .font(AppFont.mono(size: 9, weight: .medium))
                    .kerning(1.0)
                    .foregroundStyle(.gray)
                
                Spacer()
                
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                #if os(iOS)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
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
                    recording.isStarred ? "Unstar" : "Star",
                    systemImage: recording.isStarred ? "star.slash" : "star"
                )
            }

            Button {
                renameText = recording.title
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            if recording.isTranscribing {
                Button(role: .destructive) {
                    cancelTranscription()
                } label: {
                    Label("Cancel Transcription", systemImage: "xmark.circle")
                }
            }

            if !recording.hasTranscript && !recording.isTranscribing {
                Button {
                    transcribe()
                } label: {
                    Label("Transcribe", systemImage: "waveform.badge.magnifyingglass")
                }
            }

            if recording.hasTranscript && !recording.hasSummary && !recording.isSummarizing {
                Button {
                    summarize()
                } label: {
                    Label("Summarize", systemImage: "brain")
                }
            }

            // Premium features section
            if recording.hasTranscript {
                // Transcript management
                Button {
                    transcribe()
                } label: {
                    Label("Re-transcribe", systemImage: "arrow.clockwise")
                }

                Button(role: .destructive) {
                    showDeleteTranscriptConfirmation = true
                } label: {
                    Label("Delete Transcript", systemImage: "text.badge.minus")
                }

                Divider()

                // Ask Your Audio - Pro only
                Button {
                    if FeatureGate.canAccess(.askYourAudio) {
                        showAskYourAudio = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Ask Your Audio", systemImage: "bubble.left.and.bubble.right")
                }
                
                // Audio Search - Pro only
                Button {
                    if FeatureGate.canAccess(.audioSearch) {
                        showAudioSearch = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Search Transcript", systemImage: "magnifyingglass")
                }
            }

            Divider()

            if recording.audioURL != nil {
                Button {
                    if let url = recording.audioURL {
                        shareItems = [url]
                        showShareSheet = true
                    }
                } label: {
                    Label("Share Audio", systemImage: "square.and.arrow.up")
                }
            }

            if recording.hasTranscript {
                Button {
                    copyTranscript()
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
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
                        Label("Export as Markdown", systemImage: "doc.text")
                    }
                    
                    Button {
                        if FeatureGate.canAccess(.exportPDF) {
                            exportAsPDF()
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Label("Export as PDF", systemImage: "doc.richtext")
                    }
                    
                    Divider()
                    
                    Button {
                        if let text = recording.transcriptFullText {
                            shareItems = [text]
                            showShareSheet = true
                        }
                    } label: {
                        Label("Share as Text", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Export Transcript", systemImage: "arrow.up.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Recording", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Spacer()

                if recording.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
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
            .foregroundStyle(.gray)

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
                    .tint(.white)

                Text(label)
                    .font(AppFont.mono(size: 11, weight: .semibold))
                    .kerning(1.0)
                    .foregroundStyle(.white)

                if let progress, progress > 0 {
                    Text("\(Int(progress * 100))%")
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                if showCancel {
                    Button {
                        cancelTranscription()
                    } label: {
                        Text("CANCEL")
                            .font(AppFont.mono(size: 10, weight: .bold))
                            .kerning(1.0)
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.1))
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
                .foregroundStyle(.white)

            Text(message)
                .font(AppFont.mono(size: 11, weight: .regular))
                .foregroundStyle(.gray)
                .lineLimit(2)

            Spacer()

            Button("Retry") { transcribe() }
                .font(AppFont.mono(size: 11, weight: .bold))
                .foregroundStyle(.white)
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
                tabButton("DISTILL", index: 0)
                tabButton("TRANSCRIPT", index: 1)
                tabButton("NOTES", index: 2)
                tabButton("AUDIO", index: 3)
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
                .foregroundStyle(selectedTab == index ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if selectedTab == index {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.15))
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
                        TrackedLabel("THE ONE-LINER", size: 10, kerning: 1.5)
                        if recording.wasSummarizedOnDevice == true {
                            OnDeviceBadge(type: .summarization, compact: true)
                        }
                    }
                    Text(summary.oneLiner)
                        .font(AppFont.mono(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TrackedLabel("ACTION VECTORS", size: 10, kerning: 1.5)
                    ForEach(summary.actionVectors) { action in
                        actionRow(action)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TrackedLabel("CONTEXT", size: 10, kerning: 1.5)
                    Text(summary.context)
                        .font(AppFont.mono(size: 14, weight: .regular))
                        .foregroundStyle(.gray)
                        .lineSpacing(5)
                }
            } else if recording.isSummarizing {
                callToAction(
                    icon: "brain",
                    title: "SUMMARIZING",
                    subtitle: "Distilling your meeting into key signals...",
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
                    subtitle: "Transcript available. Tap to distill key signals.",
                    action: ("SUMMARIZE", summarize)
                )
            } else if recording.isTranscribing {
                callToAction(
                    icon: "waveform.badge.magnifyingglass",
                    title: "TRANSCRIBING",
                    subtitle: "Processing your recording...",
                    action: ("CANCEL", cancelTranscription)
                )
            } else {
                callToAction(
                    icon: SubscriptionManager.shared.canTranscribeAtAll ? "waveform.badge.magnifyingglass" : "lock.fill",
                    title: SubscriptionManager.shared.canTranscribeAtAll ? "NOT YET DECODED" : "TRANSCRIPTION LOCKED",
                    subtitle: SubscriptionManager.shared.canTranscribeAtAll ? "Transcribe this recording to extract signals." : "Upgrade to unlock AI transcription and summaries.",
                    action: (SubscriptionManager.shared.canTranscribeAtAll ? "TRANSCRIBE" : "UNLOCK TRANSCRIPTION", transcribe)
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
                        TrackedLabel("\(recording.uniqueSpeakers.count) SPEAKER\(recording.uniqueSpeakers.count == 1 ? "" : "S")", size: 10, kerning: 1.5)

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
                                                .foregroundStyle(.white.opacity(0.4))
                                        }
                                        .foregroundStyle(.white)
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

                Text("\(segments.count) SEGMENTS")
                    .font(AppFont.mono(size: 10, weight: .medium))
                    .kerning(1.0)
                    .foregroundStyle(.gray)
                    .padding(.bottom, 4)

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    transcriptRow(segment, index: index, isActive: currentSegmentIndex == index)
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
                    title: "TRANSCRIBING",
                    subtitle: "Your transcript will appear here.",
                    action: ("CANCEL", cancelTranscription)
                )
            } else {
                callToAction(
                    icon: SubscriptionManager.shared.canTranscribeAtAll ? "text.alignleft" : "lock.fill",
                    title: SubscriptionManager.shared.canTranscribeAtAll ? "NO TRANSCRIPT" : "TRANSCRIPTION LOCKED",
                    subtitle: SubscriptionManager.shared.canTranscribeAtAll ? "Transcribe this recording first." : "Upgrade to unlock AI transcription.",
                    action: (SubscriptionManager.shared.canTranscribeAtAll ? "TRANSCRIBE" : "UNLOCK TRANSCRIPTION", transcribe)
                )
            }
        }
        .alert("Rename Speaker", isPresented: Binding(
            get: { editingSpeaker != nil },
            set: { if !$0 { editingSpeaker = nil } }
        )) {
            TextField("Name", text: $editingSpeakerName)
            Button("Save") {
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
            Button("Cancel", role: .cancel) { editingSpeaker = nil }
        } message: {
            Text("Enter a name for this speaker.")
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
            TrackedLabel("MEETING NOTES", size: 10, kerning: 1.5)

            TextEditor(text: Binding(
                get: { recording.notes ?? "" },
                set: { recording.notes = $0.isEmpty ? nil : $0 }
            ))
            .font(AppFont.mono(size: 14, weight: .regular))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 150)
            .padding(12)
            .glassCard(radius: 10)

            if recording.notes == nil || recording.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                Text("Tap above to add notes about this meeting.")
                    .font(AppFont.mono(size: 12, weight: .regular))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.leading)
            }

            // Image attachments section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TrackedLabel("ATTACHMENTS", size: 10, kerning: 1.5)
                    Spacer()
                    
                    // Add image buttons
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        
                        #if os(iOS)
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                showCamera = true
                            } label: {
                                Image(systemName: "camera")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.6))
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
                    Text("Add photos of whiteboards, documents, or handwritten notes. Tap an image to extract text.")
                        .font(AppFont.mono(size: 12, weight: .regular))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(4)
                        .padding(.vertical, 8)
                }
            }

            if isProcessingImage {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("Processing image...")
                        .font(AppFont.mono(size: 12))
                        .foregroundStyle(.gray)
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
                    TrackedLabel("PLAYBACK", size: 10, kerning: 1.5)
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
                TrackedLabel("DETAILS", size: 10, kerning: 1.5)
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
                TrackedLabel("EXPORT COMPRESSED", size: 10, kerning: 1.5)

                Text("Re-encode audio at lower bitrate to reduce file size.")
                    .font(AppFont.mono(size: 11))
                    .foregroundStyle(.gray)
                    .lineSpacing(3)

                if isCompressing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                        Text("Compressing...")
                            .font(AppFont.mono(size: 11))
                            .foregroundStyle(.gray)
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
                        .foregroundStyle(.gray)
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
                .foregroundStyle(.white)
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
                let duration = try await asset.load(.duration)

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

                await exportSession.export()

                if exportSession.status == .completed {
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
                } else {
                    await MainActor.run {
                        isCompressing = false
                        compressionResult = "Compression failed: \(exportSession.error?.localizedDescription ?? "Unknown")"
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
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                Text(action.assignee)
                    .font(AppFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(.gray)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, AppLayout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func transcriptRow(_ segment: SegmentData, index: Int, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Playing indicator
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isActive)
                }
                
                if !segment.speaker.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(recording.displayName(for: segment.speaker))
                        .font(AppFont.mono(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(segment.timestamp.formatted)
                    .font(AppFont.mono(size: 11, weight: .regular))
                    .foregroundStyle(Color.muted)

                Spacer()

                // Edit button
                Button {
                    editingSegmentIndex = index
                    editingSegmentText = segment.text
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            Text(segment.text)
                .font(AppFont.mono(size: 14, weight: .regular))
                .foregroundStyle(isActive ? .white : .gray)
                .lineSpacing(4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, AppLayout.cardPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap to seek to this segment
            if recording.duration > 0 {
                let fraction = CGFloat(segment.timestamp / recording.duration)
                sharedPlayer.seek(to: fraction)
                if !sharedPlayer.isPlaying {
                    sharedPlayer.play()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.white.opacity(0.15) : Color.clear)
        )
        .glassCard(radius: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private func callToAction(icon: String, title: String, subtitle: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            Image(systemName: icon)
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color.muted)

            Text(title)
                .font(AppFont.mono(size: 13, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(Color.muted)

            Text(subtitle)
                .font(AppFont.mono(size: 12, weight: .regular))
                .foregroundStyle(.gray)
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
                .foregroundStyle(.gray)
            Spacer()
            Text(value)
                .font(AppFont.mono(size: 12, weight: .bold))
                .foregroundStyle(.white)
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
            }
        }
    }

    private func summarize() {
        guard let transcriptText = recording.transcriptFullText else { return }

        recording.isSummarizing = true
        recording.summarizationError = nil

        Task {
            do {
                let result = try await SummarizationService.shared.summarizeAuto(
                    transcript: transcriptText,
                    meetingNotes: recording.notes
                )

                recording.summaryOneLiner = result.oneLiner
                recording.summaryContext = result.context
                recording.summaryActions = result.actions
                recording.wasSummarizedOnDevice = result.wasOnDevice
                recording.isSummarizing = false
            } catch {
                recording.isSummarizing = false
                recording.summarizationError = error.localizedDescription
                logger.error("Summarization failed for '\(recording.title)': \(error.localizedDescription)")
            }
        }
    }

    private func copyTranscript() {
        guard let text = recording.transcriptFullText else { return }
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
    let samples: [Float]
    let duration: TimeInterval
    let marks: [TimeInterval]
    let audioURL: URL?
    @Bindable var player: AudioPlayer

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
                            context.fill(path, with: .color(.white.opacity(isPast ? 0.7 : 0.12)))
                        }

                        // Draw mark indicators
                        for mark in marks {
                            guard duration > 0 else { continue }
                            let markX = CGFloat(mark / duration) * size.width
                            let markRect = CGRect(x: markX - 0.5, y: 0, width: 1, height: size.height)
                            context.fill(Path(markRect), with: .color(.white.opacity(0.4)))
                        }
                    }
                    .frame(height: height)

                    // Playback scrub line
                    Rectangle()
                        .fill(Color.white)
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
                    .foregroundStyle(.white)
                    .frame(width: 54, alignment: .leading)

                Spacer()

                // Skip back 15s
                Button {
                    let newTime = max(0, player.currentTime - 15)
                    player.seek(to: CGFloat(newTime / max(1, duration)))
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
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
                            .fill(Color.white)
                            .frame(width: 48, height: 48)

                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
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
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 40, height: 40)
                        .glassCard(radius: 20)
                }

                Spacer()

                // Total duration
                Text(AudioPlayer.formatTime(duration))
                    .font(AppFont.mono(size: 12, weight: .regular))
                    .foregroundStyle(.gray)
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

    @State private var loadedImage: PlatformImage?

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
                    .stroke(Color.glassBorder, lineWidth: AppLayout.glassBorderWidth)
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
    let image: PlatformImage
    let onExtractText: (String) -> Void
    @Environment(\.dismiss) private var dismiss

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
                            .stroke(Color.glassBorder, lineWidth: AppLayout.glassBorderWidth)
                    )
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.glassBorder, lineWidth: AppLayout.glassBorderWidth)
                    )
                #endif

                if isExtracting {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("Extracting text...")
                            .font(AppFont.mono(size: 14))
                            .foregroundStyle(.gray)
                    }
                    .padding()
                } else if let text = extractedText {
                    VStack(alignment: .leading, spacing: 12) {
                        TrackedLabel("EXTRACTED TEXT", size: 10, kerning: 1.5)

                        ScrollView {
                            Text(text.isEmpty ? "No text found in image." : text)
                                .font(AppFont.mono(size: 14))
                                .foregroundStyle(text.isEmpty ? .gray : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 200)
                        .padding(12)
                        .glassCard(radius: 10)

                        if !text.isEmpty {
                            Button {
                                onExtractText(text)
                            } label: {
                                Text("ADD TO NOTES")
                                    .font(AppFont.mono(size: 12, weight: .bold))
                                    .kerning(1.5)
                                    .foregroundStyle(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                } else if let error = error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.gray)
                        Text(error)
                            .font(AppFont.mono(size: 14))
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)

                        Button("Retry") {
                            extractText()
                        }
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .foregroundStyle(.white)
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
                            Text("EXTRACT TEXT")
                        }
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("IMAGE")
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(.white)
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
    @Binding var text: String
    let speakerName: String
    let timestamp: TimeInterval
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                // Segment info
                HStack(spacing: 12) {
                    if !speakerName.trimmingCharacters(in: .whitespaces).isEmpty {
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(speakerName)
                            .font(AppFont.mono(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    Text(timestamp.formatted)
                        .font(AppFont.mono(size: 12))
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal)
                
                // Text editor
                VStack(alignment: .leading, spacing: 8) {
                    TrackedLabel("TRANSCRIPT TEXT", size: 10, kerning: 1.5)
                        .padding(.horizontal)
                    
                    TextEditor(text: $text)
                        .font(AppFont.mono(size: 14))
                        .foregroundStyle(.white)
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
                    Text("SAVE CHANGES")
                        .font(AppFont.mono(size: 12, weight: .bold))
                        .kerning(1.5)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top)
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EDIT SEGMENT")
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(.white)
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
    let recordingDuration: TimeInterval
    let onChooseApple: () -> Void
    let onChooseAPI: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var subscription: SubscriptionManager { SubscriptionManager.shared }
    private var isOnDeviceAvailable: Bool { OnDeviceTranscriptionService.shared.isOnDeviceAvailable }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 40, weight: .thin))
                        .foregroundStyle(.white)
                    
                    Text("Choose Transcription Method")
                        .font(AppFont.mono(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("Select how you'd like to transcribe this recording")
                        .font(AppFont.mono(size: 12))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)
                
                // Options
                VStack(spacing: 12) {
                    // Apple On-Device Option
                    Button {
                        onChooseApple()
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("APPLE ON-DEVICE")
                                        .font(AppFont.mono(size: 13, weight: .bold))
                                        .kerning(1.0)
                                        .foregroundStyle(.white)
                                    
                                    Text("Private & Free")
                                        .font(AppFont.mono(size: 11))
                                        .foregroundStyle(.gray)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("FREE")
                                        .font(AppFont.mono(size: 11, weight: .bold))
                                        .foregroundStyle(.green)
                                    
                                    Text("Unlimited")
                                        .font(AppFont.mono(size: 10))
                                        .foregroundStyle(.gray)
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
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .disabled(!isOnDeviceAvailable)
                    .opacity(isOnDeviceAvailable ? 1 : 0.5)
                    
                    if !isOnDeviceAvailable {
                        Text("On-device transcription not available for selected language")
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(.orange)
                    }
                    
                    // ElevenLabs API Option
                    Button {
                        onChooseAPI()
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ELEVENLABS API")
                                        .font(AppFont.mono(size: 13, weight: .bold))
                                        .kerning(1.0)
                                        .foregroundStyle(.white)
                                    
                                    Text("Higher Accuracy")
                                        .font(AppFont.mono(size: 11))
                                        .foregroundStyle(.gray)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(subscription.remainingTranscriptionLabel)
                                        .font(AppFont.mono(size: 11, weight: .bold))
                                        .foregroundStyle(subscription.remainingTranscriptionSeconds > recordingDuration ? .white : .orange)
                                    
                                    // Usage bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.white.opacity(0.1))
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
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .disabled(!subscription.canTranscribe(duration: recordingDuration))
                    .opacity(subscription.canTranscribe(duration: recordingDuration) ? 1 : 0.5)
                    
                    if !subscription.canTranscribe(duration: recordingDuration) {
                        Text("Not enough API usage remaining for this recording")
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal)
                
                // Usage info
                VStack(spacing: 8) {
                    HStack {
                        Text("Monthly API Usage")
                            .font(AppFont.mono(size: 11))
                            .foregroundStyle(.gray)
                        Spacer()
                        Text("\(subscription.currentTier.displayName) Plan")
                            .font(AppFont.mono(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    
                    // Full-width usage bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(usageColor)
                                .frame(width: geo.size.width * subscription.usagePercentage)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        Text(formatDuration(subscription.usage.transcriptionSecondsUsed) + " used")
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(.gray)
                        Spacer()
                        Text(subscription.currentTier.transcriptionLimitLabel)
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(.gray)
                    }
                }
                .padding()
                .glassCard(radius: 10)
                .padding(.horizontal)
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("TRANSCRIBE")
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(AppFont.mono(size: 14, weight: .medium))
                    .foregroundStyle(.white)
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
        .foregroundStyle(.gray)
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
