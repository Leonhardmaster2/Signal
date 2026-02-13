import SwiftUI
import SwiftData
import Speech

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("autoTranscribe") private var autoTranscribe: Bool = true
    @AppStorage("hapticFeedbackEnabled") private var hapticFeedback: Bool = true
    @AppStorage("recordingQuality") private var recordingQuality: String = "standard"
    
    // On-device intelligence settings
    @AppStorage("useOnDeviceTranscription") private var useOnDeviceTranscription: Bool = false
    @AppStorage("useOnDeviceSummarization") private var useOnDeviceSummarization: Bool = false
    @AppStorage("useAutoLanguageDetection") private var useAutoLanguageDetection: Bool = true
    @AppStorage("preferredTranscriptionLanguage") private var preferredLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"

    @State private var showDeleteConfirmation = false
    @State private var onDeviceTranscriptionAvailable = false
    @State private var onDeviceSummarizationAvailable = false
    @State private var showLanguagePicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppLayout.sectionSpacing) {
                subscriptionSection
                recordingSection
                onDeviceIntelligenceSection
                generalSection
                storageSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, AppLayout.horizontalPadding)
            .padding(.vertical, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SETTINGS")
                    .font(AppFont.mono(size: 13, weight: .semibold))
                    .kerning(2.0)
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Subscription
    
    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel("SUBSCRIPTION")
            SubscriptionOverviewView()
        }
    }

    // MARK: - Recording

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel("RECORDING")

            VStack(spacing: 0) {
                HStack {
                    Text("Auto-transcribe")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $autoTranscribe)
                        .labelsHidden()
                        .tint(.white.opacity(0.5))
                }
                .padding(AppLayout.cardPadding)

                Color.divider.frame(height: 0.5)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quality")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)

                    Picker("Quality", selection: $recordingQuality) {
                        Text("Standard (16 kHz)")
                            .tag("standard")
                        Text("High (44.1 kHz)")
                            .tag("high")
                    }
                    .pickerStyle(.segmented)
                    .font(AppFont.mono(size: 11))
                }
                .padding(AppLayout.cardPadding)
            }
            .glassCard()
        }
    }

    // MARK: - On-Device Intelligence
    
    /// Check if any on-device features are available on this device
    private var anyOnDeviceFeaturesAvailable: Bool {
        onDeviceTranscriptionAvailable || onDeviceSummarizationAvailable
    }
    
    @ViewBuilder
    private var onDeviceIntelligenceSection: some View {
        // Only show this section if at least one on-device feature is available
        if anyOnDeviceFeaturesAvailable {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    TrackedLabel("ON-DEVICE INTELLIGENCE")
                    
                    // Demo badge
                    Text("DEMO")
                        .font(AppFont.mono(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .clipShape(Capsule())
                }
                
                VStack(spacing: 0) {
                    // Apple Transcription toggle - only show if available
                    if onDeviceTranscriptionAvailable {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Apple Transcription")
                                        .font(AppFont.mono(size: 13, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text("Uses on-device speech recognition")
                                        .font(AppFont.mono(size: 10))
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Toggle("", isOn: $useOnDeviceTranscription)
                                    .labelsHidden()
                                    .tint(.white.opacity(0.5))
                            }
                        }
                        .padding(AppLayout.cardPadding)
                        
                        if onDeviceSummarizationAvailable {
                            Color.divider.frame(height: 0.5)
                        }
                    }
                    
                    // Apple Intelligence Summarization toggle - only show if available
                    if onDeviceSummarizationAvailable {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("Apple Intelligence")
                                            .font(AppFont.mono(size: 13, weight: .medium))
                                            .foregroundStyle(.white)
                                        Image(systemName: "apple.intelligence")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    Text("Summarize using on-device AI")
                                        .font(AppFont.mono(size: 10))
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Toggle("", isOn: $useOnDeviceSummarization)
                                    .labelsHidden()
                                    .tint(.white.opacity(0.5))
                            }
                        }
                        .padding(AppLayout.cardPadding)
                    }
                    
                    // Language Settings (only shown when on-device transcription is enabled and available)
                    if useOnDeviceTranscription && onDeviceTranscriptionAvailable {
                        Color.divider.frame(height: 0.5)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-detect Language")
                                        .font(AppFont.mono(size: 13, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text("Automatically detects spoken language")
                                        .font(AppFont.mono(size: 10))
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Toggle("", isOn: $useAutoLanguageDetection)
                                    .labelsHidden()
                                    .tint(.white.opacity(0.5))
                            }
                        }
                        .padding(AppLayout.cardPadding)
                        
                        Color.divider.frame(height: 0.5)
                        
                        // Preferred Language selector
                        Button {
                            showLanguagePicker = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(useAutoLanguageDetection ? "Fallback Language" : "Transcription Language")
                                        .font(AppFont.mono(size: 13, weight: .medium))
                                        .foregroundStyle(.white)
                                    Text(useAutoLanguageDetection ? "Used if detection fails" : "Language for transcription")
                                        .font(AppFont.mono(size: 10))
                                        .foregroundStyle(Color.muted)
                                }
                                Spacer()
                                Text(languageDisplayName(for: preferredLanguage))
                                    .font(AppFont.mono(size: 13))
                                    .foregroundStyle(Color.muted)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.muted)
                            }
                        }
                        .padding(AppLayout.cardPadding)
                    }
                    
                    Color.divider.frame(height: 0.5)
                    
                    // Info about on-device processing
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                        Text("On-device processing keeps your data private")
                            .font(AppFont.mono(size: 10))
                            .foregroundStyle(Color.muted)
                    }
                    .padding(AppLayout.cardPadding)
                }
                .glassCard()
            }
            .onAppear {
                checkOnDeviceAvailability()
            }
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerView(selectedLanguage: $preferredLanguage)
            }
        }
    }
    
    private func languageDisplayName(for code: String) -> String {
        OnDeviceTranscriptionService.commonLanguages.first { $0.code == code }?.name ?? code.uppercased()
    }
    
    private func checkOnDeviceAvailability() {
        // Check transcription availability
        onDeviceTranscriptionAvailable = OnDeviceTranscriptionService.shared.isOnDeviceAvailable
        
        // Check summarization availability
        onDeviceSummarizationAvailable = OnDeviceSummarizationService.shared.isAvailable
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel("GENERAL")

            VStack(spacing: 0) {
                HStack {
                    Text("Haptic Feedback")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: $hapticFeedback)
                        .labelsHidden()
                        .tint(.white.opacity(0.5))
                }
                .padding(AppLayout.cardPadding)
            }
            .glassCard()
        }
    }

    // MARK: - Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel("STORAGE")

            VStack(spacing: 0) {
                HStack {
                    Text("Recordings")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(storageInfo.count)")
                        .font(AppFont.mono(size: 13))
                        .foregroundStyle(Color.muted)
                }
                .padding(AppLayout.cardPadding)

                Color.divider.frame(height: 0.5)

                HStack {
                    Text("Disk Usage")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(storageInfo.size)
                        .font(AppFont.mono(size: 13))
                        .foregroundStyle(Color.muted)
                }
                .padding(AppLayout.cardPadding)

                Color.divider.frame(height: 0.5)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Text("Delete All Recordings")
                            .font(AppFont.mono(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                        Spacer()
                        Image(systemName: "trash")
                            .font(AppFont.mono(size: 13))
                            .foregroundStyle(.red)
                    }
                    .padding(AppLayout.cardPadding)
                }
            }
            .glassCard()
        }
        .alert("Delete All Recordings?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                deleteAllRecordings()
            }
        } message: {
            Text("This will permanently remove all recordings and their audio files. This action cannot be undone.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel("ABOUT")

            VStack(spacing: 0) {
                HStack {
                    Text("Version")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("1.0")
                        .font(AppFont.mono(size: 13))
                        .foregroundStyle(Color.muted)
                }
                .padding(AppLayout.cardPadding)

                Color.divider.frame(height: 0.5)

                HStack {
                    Spacer()
                    Text("Built by Proceduralabs")
                        .font(AppFont.mono(size: 11, weight: .medium))
                        .foregroundStyle(Color.muted)
                    Spacer()
                }
                .padding(AppLayout.cardPadding)
            }
            .glassCard()
        }
    }

    // MARK: - Debug (Development Only)
    
    #if DEBUG
    @State private var subscription = SubscriptionManager.shared
    
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrackedLabel("DEBUG")
            
            VStack(spacing: 0) {
                // Tier switcher
                VStack(alignment: .leading, spacing: 8) {
                    Text("Subscription Tier")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 8) {
                        ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                            Button {
                                subscription.setTierForTesting(tier)
                            } label: {
                                Text(tier.displayName)
                                    .font(AppFont.mono(size: 11, weight: subscription.currentTier == tier ? .bold : .regular))
                                    .foregroundStyle(subscription.currentTier == tier ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(subscription.currentTier == tier ? Color.white : Color.white.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(AppLayout.cardPadding)
                
                Color.divider.frame(height: 0.5)
                
                // Usage simulation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Simulate Usage")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 8) {
                        Button {
                            subscription.addUsageForTesting(seconds: 1800) // 30 min
                        } label: {
                            Text("+30m")
                                .font(AppFont.mono(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Button {
                            subscription.addUsageForTesting(seconds: 3600) // 1 hour
                        } label: {
                            Text("+1h")
                                .font(AppFont.mono(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Button {
                            subscription.resetUsageForTesting()
                        } label: {
                            Text("Reset")
                                .font(AppFont.mono(size: 11, weight: .medium))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.orange.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text("Used: \(formatSeconds(subscription.usage.transcriptionSecondsUsed)) / \(formatSeconds(subscription.currentTier.transcriptionLimitSeconds))")
                        .font(AppFont.mono(size: 10, weight: .regular))
                        .foregroundStyle(.gray)
                }
                .padding(AppLayout.cardPadding)
                
                Color.divider.frame(height: 0.5)
                
                // Demo data generator
                VStack(alignment: .leading, spacing: 8) {
                    Text("Demo Data")
                        .font(AppFont.mono(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 8) {
                        Button {
                            generateDemoRecordings()
                        } label: {
                            Text("Add Demo Items")
                                .font(AppFont.mono(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        
                        Button {
                            deleteAllRecordings()
                        } label: {
                            Text("Clear All")
                                .font(AppFont.mono(size: 11, weight: .medium))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(AppLayout.cardPadding)
            }
            .glassCard()
        }
    }
    
    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
    
    private func generateDemoRecordings() {
        // Demo 1: Team standup with full transcript and summary
        let standup = Recording(
            title: "Team Standup",
            date: Date().addingTimeInterval(-3600 * 2), // 2 hours ago
            duration: 847,
            amplitudeSamples: (0..<120).map { _ in Float.random(in: 0.15...0.85) }
        )
        standup.isStarred = true
        standup.transcriptLanguage = "en"
        standup.wasTranscribedOnDevice = true
        standup.wasSummarizedOnDevice = true
        standup.transcriptFullText = """
        Good morning everyone. Let's get started with our daily standup. Sarah, would you like to go first?
        
        Sure. Yesterday I finished the authentication module and merged it to main. Today I'm going to start working on the user profile page. No blockers for me.
        
        Great progress Sarah. Mike, you're up.
        
        Thanks. So yesterday I was debugging that performance issue in the dashboard. Turns out it was an N+1 query problem. I've got a fix ready for review. Today I'll be working on the notification system. I might need some help from Sarah on the auth integration later.
        
        No problem, just ping me when you're ready.
        
        Perfect. I spent yesterday in meetings mostly, planning the Q2 roadmap with product. Today I'll be reviewing PRs and working on the technical spec for the new analytics feature. Let's make sure we hit our sprint goals this week. Any other blockers or concerns?
        
        Actually, I wanted to mention that the staging server has been a bit slow lately. Might be worth looking into.
        
        Good catch. I'll create a ticket for that. Anything else? Alright, let's have a productive day everyone.
        """
        standup.transcriptSegments = [
            SegmentData(speaker: "Speaker A", text: "Good morning everyone. Let's get started with our daily standup. Sarah, would you like to go first?", timestamp: 0),
            SegmentData(speaker: "Speaker B", text: "Sure. Yesterday I finished the authentication module and merged it to main. Today I'm going to start working on the user profile page. No blockers for me.", timestamp: 12),
            SegmentData(speaker: "Speaker A", text: "Great progress Sarah. Mike, you're up.", timestamp: 35),
            SegmentData(speaker: "Speaker C", text: "Thanks. So yesterday I was debugging that performance issue in the dashboard. Turns out it was an N+1 query problem. I've got a fix ready for review. Today I'll be working on the notification system. I might need some help from Sarah on the auth integration later.", timestamp: 42),
            SegmentData(speaker: "Speaker B", text: "No problem, just ping me when you're ready.", timestamp: 78),
            SegmentData(speaker: "Speaker A", text: "Perfect. I spent yesterday in meetings mostly, planning the Q2 roadmap with product. Today I'll be reviewing PRs and working on the technical spec for the new analytics feature. Let's make sure we hit our sprint goals this week. Any other blockers or concerns?", timestamp: 85),
            SegmentData(speaker: "Speaker C", text: "Actually, I wanted to mention that the staging server has been a bit slow lately. Might be worth looking into.", timestamp: 128),
            SegmentData(speaker: "Speaker A", text: "Good catch. I'll create a ticket for that. Anything else? Alright, let's have a productive day everyone.", timestamp: 145)
        ]
        standup.speakerNames = ["Speaker A": "Alex", "Speaker B": "Sarah", "Speaker C": "Mike"]
        standup.summaryOneLiner = "Daily standup covering auth completion, dashboard fix, and Q2 planning"
        standup.summaryContext = "The team discussed progress on authentication (completed), a dashboard performance fix (N+1 query resolved), and upcoming work on user profiles, notifications, and analytics. A staging server performance issue was flagged for investigation."
        standup.summaryActions = [
            ActionData(assignee: "Sarah", task: "Work on user profile page", isCompleted: false, timestamp: nil),
            ActionData(assignee: "Mike", task: "Complete notification system and coordinate with Sarah on auth integration", isCompleted: false, timestamp: nil),
            ActionData(assignee: "Alex", task: "Review PRs and write analytics technical spec", isCompleted: false, timestamp: nil),
            ActionData(assignee: "Alex", task: "Create ticket for staging server performance", isCompleted: true, timestamp: nil)
        ]
        modelContext.insert(standup)
        
        // Demo 2: Client call (German)
        let clientCall = Recording(
            title: "Kundengespräch Projekt Alpha",
            date: Date().addingTimeInterval(-3600 * 26), // Yesterday
            duration: 1823,
            amplitudeSamples: (0..<150).map { _ in Float.random(in: 0.1...0.75) }
        )
        clientCall.transcriptLanguage = "de"
        clientCall.wasTranscribedOnDevice = true
        clientCall.wasSummarizedOnDevice = false
        clientCall.transcriptFullText = """
        Guten Tag Herr Schmidt, vielen Dank dass Sie sich die Zeit genommen haben.
        
        Guten Tag, natürlich. Ich freue mich auf unser Gespräch über das Projekt Alpha.
        
        Perfekt. Lassen Sie uns direkt einsteigen. Wir haben die erste Phase der Implementierung abgeschlossen und ich wollte Ihnen einen Überblick geben.
        
        Das klingt gut. Wie ist der aktuelle Stand?
        
        Wir liegen gut im Zeitplan. Die Kernfunktionalität ist zu 80% fertig. Die Benutzeroberfläche wird nächste Woche finalisiert. Wir haben auch einige Performance-Optimierungen vorgenommen, die die Ladezeiten um 40% verbessert haben.
        
        Das sind ausgezeichnete Neuigkeiten. Gibt es irgendwelche Risiken oder Bedenken?
        
        Ein kleines Thema: Die Integration mit Ihrem Legacy-System ist komplexer als erwartet. Wir benötigen möglicherweise eine zusätzliche Woche für diese Komponente.
        
        Das verstehe ich. Qualität geht vor Geschwindigkeit. Halten Sie mich bitte auf dem Laufenden.
        """
        clientCall.transcriptSegments = [
            SegmentData(speaker: "Speaker A", text: "Guten Tag Herr Schmidt, vielen Dank dass Sie sich die Zeit genommen haben.", timestamp: 0),
            SegmentData(speaker: "Speaker B", text: "Guten Tag, natürlich. Ich freue mich auf unser Gespräch über das Projekt Alpha.", timestamp: 8),
            SegmentData(speaker: "Speaker A", text: "Perfekt. Lassen Sie uns direkt einsteigen. Wir haben die erste Phase der Implementierung abgeschlossen und ich wollte Ihnen einen Überblick geben.", timestamp: 18),
            SegmentData(speaker: "Speaker B", text: "Das klingt gut. Wie ist der aktuelle Stand?", timestamp: 35),
            SegmentData(speaker: "Speaker A", text: "Wir liegen gut im Zeitplan. Die Kernfunktionalität ist zu 80% fertig. Die Benutzeroberfläche wird nächste Woche finalisiert. Wir haben auch einige Performance-Optimierungen vorgenommen, die die Ladezeiten um 40% verbessert haben.", timestamp: 42),
            SegmentData(speaker: "Speaker B", text: "Das sind ausgezeichnete Neuigkeiten. Gibt es irgendwelche Risiken oder Bedenken?", timestamp: 75),
            SegmentData(speaker: "Speaker A", text: "Ein kleines Thema: Die Integration mit Ihrem Legacy-System ist komplexer als erwartet. Wir benötigen möglicherweise eine zusätzliche Woche für diese Komponente.", timestamp: 85),
            SegmentData(speaker: "Speaker B", text: "Das verstehe ich. Qualität geht vor Geschwindigkeit. Halten Sie mich bitte auf dem Laufenden.", timestamp: 108)
        ]
        clientCall.speakerNames = ["Speaker A": "Projektleiter", "Speaker B": "Herr Schmidt"]
        clientCall.summaryOneLiner = "Projekt Alpha Status: 80% fertig, Legacy-Integration benötigt mehr Zeit"
        clientCall.summaryContext = "Statusupdate für Projekt Alpha mit dem Kunden. Kernfunktionalität 80% abgeschlossen, UI wird nächste Woche fertig. Performance um 40% verbessert. Legacy-System-Integration benötigt eine zusätzliche Woche."
        clientCall.summaryActions = [
            ActionData(assignee: "Team", task: "UI nächste Woche finalisieren", isCompleted: false, timestamp: nil),
            ActionData(assignee: "Team", task: "Legacy-System Integration abschließen (+ 1 Woche)", isCompleted: false, timestamp: nil),
            ActionData(assignee: "Projektleiter", task: "Herrn Schmidt über Fortschritte informieren", isCompleted: false, timestamp: nil)
        ]
        modelContext.insert(clientCall)
        
        // Demo 3: Lecture notes (transcribed only, no summary yet)
        let lecture = Recording(
            title: "CS 101 - Data Structures",
            date: Date().addingTimeInterval(-3600 * 50),
            duration: 2847,
            amplitudeSamples: (0..<180).map { _ in Float.random(in: 0.2...0.6) }
        )
        lecture.marks = [245, 892, 1456, 2103]
        lecture.transcriptLanguage = "en"
        lecture.wasTranscribedOnDevice = true
        lecture.transcriptFullText = """
        Today we're going to dive deep into binary search trees. This is one of the fundamental data structures you'll use throughout your career. A binary search tree maintains the property that for any node, all values in its left subtree are smaller, and all values in its right subtree are larger.
        
        The beauty of this structure is that it gives us O(log n) search time on average. Let me draw this on the board. If we insert the values 8, 3, 10, 1, 6, 14, 4, 7, 13... you can see how the tree organizes itself.
        
        Now, there's a catch. What happens if we insert already sorted data? Anyone? Right - we get a degenerate tree that's essentially a linked list, and our O(log n) becomes O(n). This is why we need balanced trees like AVL trees and Red-Black trees, which we'll cover next week.
        
        For your homework, implement a BST with insert, search, and delete operations. The delete operation is tricky - think about the three cases: leaf node, one child, and two children. For the two children case, you'll need to find either the in-order predecessor or successor.
        """
        lecture.transcriptSegments = [
            SegmentData(speaker: "", text: "Today we're going to dive deep into binary search trees. This is one of the fundamental data structures you'll use throughout your career. A binary search tree maintains the property that for any node, all values in its left subtree are smaller, and all values in its right subtree are larger.", timestamp: 0),
            SegmentData(speaker: "", text: "The beauty of this structure is that it gives us O(log n) search time on average. Let me draw this on the board. If we insert the values 8, 3, 10, 1, 6, 14, 4, 7, 13... you can see how the tree organizes itself.", timestamp: 45),
            SegmentData(speaker: "", text: "Now, there's a catch. What happens if we insert already sorted data? Anyone? Right - we get a degenerate tree that's essentially a linked list, and our O(log n) becomes O(n). This is why we need balanced trees like AVL trees and Red-Black trees, which we'll cover next week.", timestamp: 98),
            SegmentData(speaker: "", text: "For your homework, implement a BST with insert, search, and delete operations. The delete operation is tricky - think about the three cases: leaf node, one child, and two children. For the two children case, you'll need to find either the in-order predecessor or successor.", timestamp: 156)
        ]
        lecture.notes = "Important: AVL trees next week!\nReview delete operation cases"
        modelContext.insert(lecture)
        
        // Demo 4: Voice memo (raw, no transcript)
        let voiceMemo = Recording(
            title: "Quick idea - app feature",
            date: Date().addingTimeInterval(-3600 * 4),
            duration: 47,
            amplitudeSamples: (0..<30).map { _ in Float.random(in: 0.3...0.9) }
        )
        modelContext.insert(voiceMemo)
        
        // Demo 5: Interview (currently transcribing)
        let interview = Recording(
            title: "Product Manager Interview",
            date: Date().addingTimeInterval(-1800), // 30 min ago
            duration: 1245,
            amplitudeSamples: (0..<100).map { _ in Float.random(in: 0.2...0.8) }
        )
        interview.isTranscribing = true
        modelContext.insert(interview)
        
        // Demo 6: Archived recording
        let archived = Recording(
            title: "Old Planning Session",
            date: Date().addingTimeInterval(-3600 * 24 * 14), // 2 weeks ago
            duration: 3600,
            amplitudeSamples: (0..<200).map { _ in Float.random(in: 0.1...0.7) }
        )
        archived.isArchived = true
        archived.transcriptFullText = "This is an older planning session that has been archived."
        archived.transcriptSegments = [
            SegmentData(speaker: "Speaker A", text: "This is an older planning session that has been archived.", timestamp: 0)
        ]
        modelContext.insert(archived)
        
        try? modelContext.save()
    }
    #endif

    // MARK: - Helpers

    private var storageInfo: (count: Int, size: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Recordings")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return (0, "0 MB")
        }
        var totalSize: Int64 = 0
        for file in files {
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return (files.count, formatter.string(fromByteCount: totalSize))
    }

    private func deleteAllRecordings() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Recordings")
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }

        do {
            try modelContext.delete(model: Recording.self)
            try modelContext.save()
        } catch {
            print("Failed to delete recordings: \(error)")
        }
    }

}

// MARK: - Language Picker View

struct LanguagePickerView: View {
    @Binding var selectedLanguage: String
    @Environment(\.dismiss) private var dismiss
    
    /// Languages loaded on appear to avoid computation during view init
    @State private var availableLanguages: [(code: String, name: String, supportsOnDevice: Bool)] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading languages...")
                            .font(AppFont.mono(size: 12))
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(availableLanguages, id: \.code) { language in
                            Button {
                                selectedLanguage = language.code
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(language.name)
                                            .font(AppFont.mono(size: 14, weight: .medium))
                                            .foregroundStyle(.white)
                                        
                                        HStack(spacing: 4) {
                                            if language.supportsOnDevice {
                                                Image(systemName: "iphone")
                                                    .font(.system(size: 10))
                                                Text("On-device")
                                                    .font(AppFont.mono(size: 10))
                                            } else {
                                                Image(systemName: "cloud")
                                                    .font(.system(size: 10))
                                                Text("Requires network")
                                                    .font(AppFont.mono(size: 10))
                                            }
                                        }
                                        .foregroundStyle(language.supportsOnDevice ? .green : .orange)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedLanguage == language.code {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(AppLayout.cardPadding)
                            }
                            
                            if language.code != availableLanguages.last?.code {
                                Color.divider.frame(height: 0.5)
                            }
                        }
                    }
                    .glassCard()
                    .padding(.horizontal, AppLayout.horizontalPadding)
                    .padding(.vertical, 24)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LANGUAGE")
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(AppFont.mono(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await loadLanguages()
        }
    }
    
    private func loadLanguages() async {
        // Load on background thread to avoid blocking UI
        let commonLangs = OnDeviceTranscriptionService.commonLanguages
        let languages = await Task.detached(priority: .userInitiated) {
            // Get common languages and check support
            commonLangs.compactMap { lang -> (code: String, name: String, supportsOnDevice: Bool)? in
                // Check if language is supported at all
                let supportedLocales = SFSpeechRecognizer.supportedLocales()
                let isSupported = supportedLocales.contains { locale in
                    locale.language.languageCode?.identifier == lang.code
                }
                guard isSupported else { return nil }
                
                // Check on-device support
                let matchingLocale = supportedLocales.first { $0.language.languageCode?.identifier == lang.code }
                var supportsOnDevice = false
                if let locale = matchingLocale, let recognizer = SFSpeechRecognizer(locale: locale) {
                    supportsOnDevice = recognizer.supportsOnDeviceRecognition
                }
                
                return (lang.code, lang.name, supportsOnDevice)
            }
        }.value
        
        await MainActor.run {
            availableLanguages = languages
            isLoading = false
        }
    }
}

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
