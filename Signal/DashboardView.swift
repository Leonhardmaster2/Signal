import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Dashboard (The Feed)

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Recording> { !$0.isArchived }, sort: \Recording.date, order: .reverse)
    private var recordings: [Recording]

    @State private var showRecorder = false
    @State private var autoStartRecording = false
    @State private var showSettings = false
    @State private var selectedRecording: Recording?
    @State private var searchText = ""
    @State private var recordingToDelete: Recording?
    @State private var showAudioImporter = false
    @State private var showPaywall = false
    @State private var recordingToRename: Recording?
    @State private var renameText = ""

    // MARK: - Computed

    private var filteredRecordings: [Recording] {
        var result = recordings
        
        // Apply history limit for free tier
        if let limit = SubscriptionManager.shared.currentTier.historyLimit {
            result = Array(result.prefix(limit))
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.title.lowercased().contains(query) }
        }
        
        return result
    }
    
    private var isHistoryLimited: Bool {
        guard let limit = SubscriptionManager.shared.currentTier.historyLimit else { return false }
        return recordings.count > limit
    }
    
    private var hiddenRecordingsCount: Int {
        guard let limit = SubscriptionManager.shared.currentTier.historyLimit else { return 0 }
        return max(0, recordings.count - limit)
    }

    private var groupedByDate: [(String, [Recording])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRecordings) { recording in
            calendar.startOfDay(for: recording.date)
        }
        return grouped.sorted { $0.key > $1.key }.map { (key, value) in
            let label: String
            if calendar.isDateInToday(key) {
                label = "TODAY"
            } else if calendar.isDateInYesterday(key) {
                label = "YESTERDAY"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE, MMM d"
                label = formatter.string(from: key).uppercased()
            }
            return (label, value.sorted { $0.date > $1.date })
        }
    }

    private var totalDuration: TimeInterval { recordings.reduce(0) { $0 + $1.duration } }
    private var decodedCount: Int { recordings.filter { $0.hasSummary }.count }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            if recordings.isEmpty {
                emptyState
            } else {
                feedContent
            }

            recordButton
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SIGNAL")
                    .font(AppFont.mono(size: 13, weight: .semibold))
                    .kerning(4.0)
                    .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { selectedRecording != nil },
            set: { if !$0 { selectedRecording = nil } }
        )) {
            if let recording = selectedRecording {
                DecodedView(recording: recording)
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showRecorder, onDismiss: {
            autoStartRecording = false
        }) {
            RecorderView(autoStart: autoStartRecording)
        }
        .onReceive(NotificationCenter.default.publisher(for: .startRecordingFromShortcut)) { _ in
            autoStartRecording = true
            showRecorder = true
        }
        .onAppear {
            // Check for pending shortcut recording (cold-start case)
            if UserDefaults.standard.bool(forKey: "pendingShortcutRecording") {
                UserDefaults.standard.set(false, forKey: "pendingShortcutRecording")
                autoStartRecording = true
                showRecorder = true
            }
        }
        .alert("Delete Recording", isPresented: Binding(
            get: { recordingToDelete != nil },
            set: { if !$0 { recordingToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                recordingToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let recording = recordingToDelete {
                    deleteRecording(recording)
                }
            }
        } message: {
            Text("This will permanently delete the recording and its audio file. This action cannot be undone.")
        }
        .alert("Rename Recording", isPresented: Binding(
            get: { recordingToRename != nil },
            set: { if !$0 { recordingToRename = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, let recording = recordingToRename {
                    recording.title = trimmed
                }
                recordingToRename = nil
            }
            Button("Cancel", role: .cancel) {
                recordingToRename = nil
            }
        } message: {
            Text("Enter a new name for this recording.")
        }
        .audioFileImporter(isPresented: $showAudioImporter) { url in
            importAudioFile(url: url)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                IdleWaveform()
                    .frame(height: 80)
                    .padding(.horizontal, 40)

                VStack(spacing: 8) {
                    Text("No signals captured")
                        .font(AppFont.mono(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Tap the button below to begin\nrecording your first meeting.")
                        .font(AppFont.mono(size: 13, weight: .regular))
                        .foregroundStyle(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppLayout.horizontalPadding)
    }

    // MARK: - Feed

    private var feedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchBar
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                statsBar
                    .padding(.bottom, 20)

                ForEach(Array(groupedByDate.enumerated()), id: \.offset) { _, group in
                    dateSection(label: group.0, recordings: group.1)
                        .padding(.bottom, 20)
                }
                
                // History limit banner for free tier
                if isHistoryLimited {
                    historyLimitBanner
                        .padding(.bottom, 20)
                }

                Spacer(minLength: 120)
            }
            .padding(.horizontal, AppLayout.horizontalPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.muted)

            TextField("Search signals...", text: $searchText)
                .font(AppFont.mono(size: 13, weight: .regular))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.muted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassCard(radius: AppLayout.inputRadius)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 0) {
            statCell(value: "\(recordings.count)", label: "SIGNALS")
            statDivider
            statCell(value: formatTotalDuration(totalDuration), label: "CAPTURED")
            statDivider
            statCell(value: "\(decodedCount)", label: "DECODED")
        }
        .padding(.vertical, 14)
        .glassCard(radius: 10)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(AppFont.mono(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Text(label)
                .font(AppFont.mono(size: 9, weight: .medium))
                .kerning(1.0)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.divider).frame(width: 0.5, height: 32)
    }

    // MARK: - Date Section

    private func dateSection(label: String, recordings: [Recording]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TrackedLabel(label, size: 10, kerning: 2.0)

            VStack(spacing: 0) {
                ForEach(recordings) { recording in
                    SignalRow(
                        recording: recording,
                        onRequestDelete: { recordingToDelete = recording },
                        onRequestRename: {
                            renameText = recording.title
                            recordingToRename = recording
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedRecording = recording }

                    if recording.uid != recordings.last?.uid {
                        Rectangle()
                            .fill(Color.divider)
                            .frame(height: 0.5)
                            .padding(.horizontal, AppLayout.cardPadding)
                    }
                }
            }
            .glassCard(radius: AppLayout.cardRadius)
        }
    }

    // MARK: - FAB

    private var recordButton: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                // Import button (Standard+ feature)
                Button {
                    if FeatureGate.canAccess(.audioUpload) {
                        showAudioImporter = true
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                
                // Record button
                Button {
                    showRecorder = true
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)

                        Text("RECORD")
                            .font(AppFont.mono(size: 13, weight: .bold))
                            .kerning(2.0)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .glassEffect(.regular.interactive())
                }
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .padding(.bottom, AppLayout.fabBottomMargin)
    }

    // MARK: - History Limit Banner
    
    private var historyLimitBanner: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 14))
                    Text("\(hiddenRecordingsCount) older recording\(hiddenRecordingsCount == 1 ? "" : "s") hidden")
                        .font(AppFont.mono(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                
                Text("Upgrade to unlock unlimited history")
                    .font(AppFont.mono(size: 10, weight: .regular))
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCard(radius: 12)
        }
    }
    
    // MARK: - Helpers

    private func formatTotalDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private func deleteRecording(_ recording: Recording) {
        if let url = recording.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(recording)
        try? modelContext.save()
    }
    
    private func importAudioFile(url: URL) {
        // Extract filename without extension for title
        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "imported_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        
        let fileName = url.lastPathComponent
        
        // Get audio duration asynchronously
        Task {
            let asset = AVURLAsset(url: url)
            let duration: TimeInterval
            if let assetDuration = try? await asset.load(.duration) {
                duration = assetDuration.seconds
            } else {
                duration = 0
            }
            
            await MainActor.run {
                // Create a new recording from the imported file
                let recording = Recording(
                    title: title.isEmpty ? "Imported Audio" : title,
                    duration: duration,
                    amplitudeSamples: []
                )
                recording.audioFileName = fileName
                
                modelContext.insert(recording)
                try? modelContext.save()
                
                // Select the new recording
                selectedRecording = recording
            }
        }
    }
}

// MARK: - Signal Row

struct SignalRow: View {
    let recording: Recording
    var onRequestDelete: (() -> Void)?
    var onRequestRename: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if recording.isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                }

                Text(recording.title)
                    .font(AppFont.mono(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                statusBadge
            }

            if !recording.amplitudeSamples.isEmpty {
                FrequencyBar(samples: recording.amplitudeSamples, height: 28)
            }

            HStack(spacing: 16) {
                metaLabel(recording.timeString)
                metaLabel(recording.formattedDuration)

                if let lang = recording.transcriptLanguage {
                    metaLabel(lang.uppercased())
                }

                if recording.uniqueSpeakers.count > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(recording.uniqueSpeakers.count)")
                            .font(AppFont.mono(size: 11, weight: .regular))
                    }
                    .foregroundStyle(Color.muted)
                }

                Spacer()

                if recording.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, AppLayout.cardPadding)
        .contextMenu {
            Button {
                onRequestRename?()
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                recording.isStarred.toggle()
            } label: {
                Label(recording.isStarred ? "Unstar" : "Star", systemImage: recording.isStarred ? "star.slash" : "star")
            }

            Button {
                withAnimation { recording.isArchived = true }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                onRequestDelete?()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                recording.isStarred.toggle()
            } label: {
                Image(systemName: recording.isStarred ? "star.slash.fill" : "star.fill")
            }
            .tint(.white)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onRequestDelete?()
            } label: {
                Image(systemName: "trash.fill")
            }

            Button {
                withAnimation { recording.isArchived = true }
            } label: {
                Image(systemName: "archivebox.fill")
            }
            .tint(Color.white.opacity(0.3))
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let label = recording.statusLabel
        let isActive = label == "TRANSCRIBING" || label == "SUMMARIZING"

        Text(label)
            .font(AppFont.mono(size: 9, weight: .bold))
            .kerning(1.0)
            .foregroundStyle(isActive ? .white : .gray)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isActive ? Color.white.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.mono(size: 11, weight: .regular))
            .foregroundStyle(Color.muted)
    }
}

extension Recording {
    var timeString: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - Frequency Bar

struct FrequencyBar: View {
    let samples: [Float]
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            let count = samples.count
            guard count > 0 else { return }
            let gap: CGFloat = 1.5
            let barWidth = max(1.5, (size.width - CGFloat(count - 1) * gap) / CGFloat(count))

            for i in 0..<count {
                let x = CGFloat(i) * (barWidth + gap)
                let barHeight = max(2, CGFloat(samples[i]) * size.height)
                let y = (size.height - barHeight) / 2
                let opacity = Double(samples[i]) * 0.7 + 0.15

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: 1)
                context.fill(path, with: .color(.white.opacity(opacity)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Idle Waveform

struct IdleWaveform: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            var path = Path()
            for x in stride(from: 0, through: size.width, by: 1) {
                let norm = x / size.width
                let envelope = sin(.pi * norm)
                let y = midY + sin(norm * .pi * 4 + phase) * 12 * envelope
                if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.white.opacity(0.15)), lineWidth: 1.5)
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .modelContainer(for: Recording.self, inMemory: true)
}
