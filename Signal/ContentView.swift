import SwiftUI
import SwiftData
import AVFoundation

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad and Mac: Use split view layout
                AdaptiveSplitView()
            } else {
                // iPhone: Use stack navigation
                NavigationStack {
                    DashboardView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Adaptive Split View for iPad/Mac

struct AdaptiveSplitView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Recording> { !$0.isArchived }, sort: \Recording.date, order: .reverse)
    private var recordings: [Recording]
    
    @State private var selectedRecording: Recording?
    @State private var showRecorder = false
    @State private var autoStartRecording = false
    @State private var showSettings = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var recordingToDelete: Recording?
    @State private var showAudioImporter = false
    @State private var showPaywall = false
    
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
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - Recording List
            sidebarContent
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("TRACE")
                            .font(AppFont.mono(size: 13, weight: .semibold))
                            .kerning(4.0)
                            .foregroundStyle(.white)
                    }
                    ToolbarItem(placement: .primaryAction) {
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
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 450)
                #endif
        } detail: {
            // Detail - Recording Detail or Empty State
            if let recording = selectedRecording {
                DecodedView(recording: recording)
            } else {
                detailEmptyState
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color.black.ignoresSafeArea())
        .fullScreenCover(isPresented: $showRecorder, onDismiss: {
            autoStartRecording = false
        }) {
            RecorderView(autoStart: autoStartRecording)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
            .presentationDetents([.large])
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
        .audioFileImporter(isPresented: $showAudioImporter) { url in
            importAudioFile(url: url)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
    
    // MARK: - Audio Import
    
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
    
    // MARK: - Sidebar Content
    
    private var sidebarContent: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Search bar
                    sidebarSearchBar
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                        .padding(.horizontal, 16)
                    
                    // Stats
                    sidebarStats
                        .padding(.bottom, 20)
                        .padding(.horizontal, 16)
                    
                    // Recordings list
                    if recordings.isEmpty {
                        sidebarEmptyState
                    } else {
                        ForEach(Array(groupedByDate.enumerated()), id: \.offset) { _, group in
                            sidebarDateSection(label: group.0, recordings: group.1)
                                .padding(.bottom, 16)
                        }
                        
                        // History limit banner for free tier
                        if isHistoryLimited {
                            historyLimitBanner
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            
            // Record button
            sidebarRecordButton
        }
        .background(Color.black)
    }
    
    private var sidebarSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.muted)
            
            TextField(L10n.searchRecordings, text: $searchText)
                .font(AppFont.mono(size: 13, weight: .regular))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            
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
    
    private var sidebarStats: some View {
        HStack(spacing: 0) {
            sidebarStatCell(value: "\(recordings.count)", label: L10n.signals)
            sidebarStatDivider
            sidebarStatCell(value: formatTotalDuration(totalDuration), label: L10n.captured)
            sidebarStatDivider
            sidebarStatCell(value: "\(decodedCount)", label: L10n.decoded)
        }
        .padding(.vertical, 12)
        .glassCard(radius: 10)
    }
    
    private func sidebarStatCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.mono(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(AppFont.mono(size: 8, weight: .medium))
                .kerning(1.0)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var sidebarStatDivider: some View {
        Rectangle().fill(Color.divider).frame(width: 0.5, height: 28)
    }
    
    private var sidebarEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color.muted)
            
            Text(L10n.noRecordings)
                .font(AppFont.mono(size: 14, weight: .medium))
                .foregroundStyle(.gray)
            
            Text(L10n.tapToRecord)
                .font(AppFont.mono(size: 12, weight: .regular))
                .foregroundStyle(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 16)
    }
    
    private func sidebarDateSection(label: String, recordings: [Recording]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppFont.mono(size: 10, weight: .medium))
                .kerning(2.0)
                .foregroundStyle(.gray)
                .padding(.horizontal, 16)
            
            VStack(spacing: 0) {
                ForEach(recordings) { recording in
                    SidebarRecordingRow(
                        recording: recording,
                        isSelected: selectedRecording?.uid == recording.uid,
                        onSelect: { selectedRecording = recording },
                        onDelete: { recordingToDelete = recording }
                    )
                    
                    if recording.uid != recordings.last?.uid {
                        Rectangle()
                            .fill(Color.divider)
                            .frame(height: 0.5)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .glassCard(radius: 12)
            .padding(.horizontal, 16)
        }
    }
    
    private var sidebarRecordButton: some View {
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
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                
                // Record button
                Button {
                    showRecorder = true
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                        
                        Text(L10n.record)
                            .font(AppFont.mono(size: 12, weight: .bold))
                            .kerning(2.0)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .glassEffect(.regular.interactive())
                }
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .padding(.bottom, 24)
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
    
    // MARK: - Detail Empty State
    
    private var detailEmptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(Color.muted)
            
            VStack(spacing: 8) {
                Text(L10n.selectRecording)
                    .font(AppFont.mono(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                
                Text(L10n.selectRecordingHelp)
                    .font(AppFont.mono(size: 13, weight: .regular))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
    
    // MARK: - Helpers
    
    private func formatTotalDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
    
    private func deleteRecording(_ recording: Recording) {
        if selectedRecording?.uid == recording.uid {
            selectedRecording = nil
        }
        if let url = recording.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(recording)
        try? modelContext.save()
    }
}

// MARK: - Sidebar Recording Row

struct SidebarRecordingRow: View {
    let recording: Recording
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Left: Recording info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if recording.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                        }
                        
                        Text(recording.title)
                            .font(AppFont.mono(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 10) {
                        Text(recording.timeString)
                            .font(AppFont.mono(size: 10, weight: .regular))
                            .foregroundStyle(Color.muted)
                        
                        Text(recording.formattedDuration)
                            .font(AppFont.mono(size: 10, weight: .regular))
                            .foregroundStyle(Color.muted)
                        
                        if recording.uniqueSpeakers.count > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 8))
                                Text("\(recording.uniqueSpeakers.count)")
                                    .font(AppFont.mono(size: 10, weight: .regular))
                            }
                            .foregroundStyle(Color.muted)
                        }
                    }
                }
                
                Spacer()
                
                // Right: Status
                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge
                    
                    if recording.isTranscribing || recording.isSummarizing {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(.white)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                recording.isStarred.toggle()
            } label: {
                Label(recording.isStarred ? L10n.unstar : L10n.star, systemImage: recording.isStarred ? "star.slash" : "star")
            }
            
            Button {
                recording.isArchived = true
            } label: {
                Label(L10n.archive, systemImage: "archivebox")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(L10n.delete, systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        let label = recording.statusLabel
        let isActive = label == "TRANSCRIBING" || label == "SUMMARIZING"
        
        Text(label)
            .font(AppFont.mono(size: 8, weight: .bold))
            .kerning(1.0)
            .foregroundStyle(isActive ? .white : .gray)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isActive ? Color.white.opacity(0.15) : Color.clear)
            .clipShape(Capsule())
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Recording.self, inMemory: true)
}
