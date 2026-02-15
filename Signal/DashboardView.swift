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
                label = L10n.today
            } else if calendar.isDateInYesterday(key) {
                label = L10n.yesterday
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
                Text("TRACE")
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
        .onReceive(NotificationCenter.default.publisher(for: .viewLatestRecordingFromShortcut)) { _ in
            // Open the latest recording
            if let latest = recordings.first {
                selectedRecording = latest
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importAudioFile)) { notification in
            // Handle imported audio file
            if let url = notification.userInfo?["url"] as? URL {
                importAudioFile(url: url)
            }
        }
        .onAppear {
            // Check for pending shortcut recording (cold-start case)
            if UserDefaults.standard.bool(forKey: "pendingShortcutRecording") {
                UserDefaults.standard.set(false, forKey: "pendingShortcutRecording")
                autoStartRecording = true
                showRecorder = true
            }
            
            // Check for pending view latest recording (cold-start case)
            if UserDefaults.standard.bool(forKey: "pendingViewLatestRecording") {
                UserDefaults.standard.set(false, forKey: "pendingViewLatestRecording")
                if let latest = recordings.first {
                    selectedRecording = latest
                }
            }
        }
        .alert(L10n.deleteRecording, isPresented: Binding(
            get: { recordingToDelete != nil },
            set: { if !$0 { recordingToDelete = nil } }
        )) {
            Button(L10n.cancel, role: .cancel) {
                recordingToDelete = nil
            }
            Button(L10n.delete, role: .destructive) {
                if let recording = recordingToDelete {
                    deleteRecording(recording)
                }
            }
        } message: {
            Text(L10n.deleteRecordingMessage)
        }
        .alert(L10n.renameRecording, isPresented: Binding(
            get: { recordingToRename != nil },
            set: { if !$0 { recordingToRename = nil } }
        )) {
            TextField(L10n.renameRecording, text: $renameText)
            Button(L10n.save) {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, let recording = recordingToRename {
                    recording.title = trimmed
                }
                recordingToRename = nil
            }
            Button(L10n.cancel, role: .cancel) {
                recordingToRename = nil
            }
        } message: {
            Text(L10n.enterNewName)
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
                    Text(L10n.noRecordings)
                        .font(AppFont.mono(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text(L10n.tapToRecord)
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

            TextField(L10n.searchRecordings, text: $searchText)
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
            statCell(value: "\(recordings.count)", label: L10n.signals)
            statDivider
            statCell(value: formatTotalDuration(totalDuration), label: L10n.captured)
            statDivider
            statCell(value: "\(decodedCount)", label: L10n.decoded)
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
                    TraceRow(
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

                        Text(L10n.record)
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
                    Text("\(hiddenRecordingsCount) \(L10n.olderRecordingsHidden)")
                        .font(AppFont.mono(size: 12, weight: .medium))
                }
                .foregroundStyle(.white)
                
                Text(L10n.upgradeUnlimitedHistory)
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
        // Check if it's a .trace package
        if url.pathExtension.lowercased() == "trace" || 
           (url.pathExtension.lowercased() == "zip" && url.lastPathComponent.contains(".trace.")) {
            Task {
                let success = await TracePackageExporter.shared.importTracePackage(
                    from: url,
                    modelContext: modelContext
                )
                if !success {
                    print("❌ Failed to import Trace package")
                }
            }
            return
        }
        
        // Check if user has subscription or credits for audio imports
        guard SubscriptionManager.shared.canTranscribeAtAll else {
            // User doesn't have access - show paywall and reject import
            showPaywall = true
            return
        }
        
        // The file has already been copied to Documents/Recordings/ by AudioFileImporter
        // Just use the provided URL directly
        let fileName = url.lastPathComponent
        
        // Extract a readable title from the original filename (before UUID replacement)
        let title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "imported_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        
        print("📁 [DashboardView] Creating recording for imported file: \(fileName)")
        
        // Get audio duration asynchronously
        Task {
            var duration: TimeInterval = 0
            
            // Get audio duration from the already-copied file
            let asset = AVURLAsset(url: url)
            if let assetDuration = try? await asset.load(.duration) {
                duration = assetDuration.seconds
            }
            
            print("📁 [DashboardView] Audio duration: \(duration)s")
            
            await MainActor.run {
                // Create a new recording from the imported file
                let recording = Recording(
                    title: title.isEmpty ? "Imported Audio" : title,
                    duration: duration,
                    amplitudeSamples: []
                )
                recording.audioFileName = fileName
                
                print("📁 [DashboardView] Created recording with audioFileName: \(fileName)")
                
                modelContext.insert(recording)
                try? modelContext.save()

                // Auto-backup to iCloud if signed in
                if AppleSignInService.shared.isSignedIn {
                    Task {
                        try? await iCloudSyncService.shared.backupRecording(recording)
                    }
                }

                // Select the new recording
                selectedRecording = recording
            }
        }
    }
}

// MARK: - Trace Row

struct TraceRow: View {
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
                Label(L10n.rename, systemImage: "pencil")
            }

            Button {
                recording.isStarred.toggle()
            } label: {
                Label(recording.isStarred ? L10n.unstar : L10n.star, systemImage: recording.isStarred ? "star.slash" : "star")
            }

            Button {
                withAnimation { recording.isArchived = true }
            } label: {
                Label(L10n.archive, systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                onRequestDelete?()
            } label: {
                Label(L10n.delete, systemImage: "trash")
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
