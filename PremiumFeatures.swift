import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Audio File Importer

struct AudioFileImporter: ViewModifier {
    @Binding var isPresented: Bool
    let onImport: (URL) -> Void
    
    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav, .aiff],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        // Need to start accessing security-scoped resource
                        guard url.startAccessingSecurityScopedResource() else { return }
                        defer { url.stopAccessingSecurityScopedResource() }
                        
                        // Copy to app's documents directory
                        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let recordingsDir = documentsDir.appendingPathComponent("Recordings", isDirectory: true)
                        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                        
                        let fileName = "imported_\(UUID().uuidString).\(url.pathExtension)"
                        let destinationURL = recordingsDir.appendingPathComponent(fileName)
                        
                        do {
                            try FileManager.default.copyItem(at: url, to: destinationURL)
                            onImport(destinationURL)
                        } catch {
                            print("Failed to copy imported file: \(error)")
                        }
                    }
                case .failure(let error):
                    print("File import failed: \(error)")
                }
            }
    }
}

extension View {
    func audioFileImporter(isPresented: Binding<Bool>, onImport: @escaping (URL) -> Void) -> some View {
        modifier(AudioFileImporter(isPresented: isPresented, onImport: onImport))
    }
}

// MARK: - Export Service

@MainActor
final class ExportService {
    static let shared = ExportService()
    
    private init() {}
    
    /// Export transcript as Markdown
    func exportAsMarkdown(recording: Recording) -> String {
        var markdown = "# \(recording.title)\n\n"
        markdown += "**Date:** \(formatDate(recording.date))\n"
        markdown += "**Duration:** \(recording.duration.durationLabel)\n"
        
        if let language = recording.transcriptLanguage {
            markdown += "**Language:** \(language.uppercased())\n"
        }
        
        markdown += "\n---\n\n"
        
        // Summary section
        if let summary = recording.summary {
            markdown += "## Summary\n\n"
            markdown += "### One-Liner\n\n"
            markdown += "> \(summary.oneLiner)\n\n"
            
            if !summary.actionVectors.isEmpty {
                markdown += "### Action Items\n\n"
                for action in summary.actionVectors {
                    let checkbox = action.isCompleted ? "[x]" : "[ ]"
                    markdown += "- \(checkbox) **\(action.assignee):** \(action.task)\n"
                }
                markdown += "\n"
            }
            
            markdown += "### Context\n\n"
            markdown += "\(summary.context)\n\n"
        }
        
        // Transcript section
        if let segments = recording.transcriptSegments, !segments.isEmpty {
            markdown += "## Transcript\n\n"
            
            let speakerNames = recording.speakerNames ?? [:]
            
            for segment in segments {
                let speaker = speakerNames[segment.speaker] ?? segment.speaker
                let timestamp = segment.timestamp.formatted
                markdown += "**[\(timestamp)] \(speaker):**\n"
                markdown += "\(segment.text)\n\n"
            }
        }
        
        // Notes section
        if let notes = recording.notes, !notes.isEmpty {
            markdown += "## Notes\n\n"
            markdown += notes
            markdown += "\n"
        }
        
        markdown += "\n---\n*Exported from Signal*\n"
        
        return markdown
    }
    
    /// Export transcript as PDF
    func exportAsPDF(recording: Recording) -> Data? {
        // Create PDF using UIKit/AppKit
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let data = renderer.pdfData { context in
            context.beginPage()
            
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            
            var yPosition: CGFloat = 50
            let margin: CGFloat = 50
            let maxWidth = pageRect.width - (margin * 2)
            
            // Title
            let title = recording.title as NSString
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            // Metadata
            let dateStr = "Date: \(formatDate(recording.date))" as NSString
            dateStr.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 20
            
            let durationStr = "Duration: \(recording.duration.durationLabel)" as NSString
            durationStr.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 40
            
            // Summary
            if let summary = recording.summary {
                ("Summary" as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                yPosition += 25
                
                let oneLiner = summary.oneLiner as NSString
                let oneLinerRect = CGRect(x: margin, y: yPosition, width: maxWidth, height: 100)
                oneLiner.draw(in: oneLinerRect, withAttributes: bodyAttributes)
                yPosition += 60
            }
            
            // Transcript preview
            if let segments = recording.transcriptSegments, !segments.isEmpty {
                // Check if we need a new page
                if yPosition > pageRect.height - 200 {
                    context.beginPage()
                    yPosition = 50
                }
                
                ("Transcript" as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                yPosition += 25
                
                let speakerNames = recording.speakerNames ?? [:]
                
                for segment in segments.prefix(20) { // Limit for PDF
                    if yPosition > pageRect.height - 100 {
                        context.beginPage()
                        yPosition = 50
                    }
                    
                    let speaker = speakerNames[segment.speaker] ?? segment.speaker
                    let line = "[\(segment.timestamp.formatted)] \(speaker): \(segment.text)" as NSString
                    let lineRect = CGRect(x: margin, y: yPosition, width: maxWidth, height: 60)
                    line.draw(in: lineRect, withAttributes: bodyAttributes)
                    yPosition += 50
                }
            }
        }
        
        return data
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Ask Your Audio (Chat with Transcript)

struct AskYourAudioView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Initial context message
                            ChatBubble(
                                message: ChatMessage(
                                    role: .assistant,
                                    content: "I've analyzed the transcript for \"\(recording.title)\". Ask me anything about what was discussed!"
                                ),
                                isUser: false
                            )
                            
                            ForEach(messages) { message in
                                ChatBubble(message: message, isUser: message.role == .user)
                                    .id(message.id)
                            }
                            
                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Thinking...")
                                        .font(AppFont.mono(size: 12))
                                        .foregroundStyle(.gray)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                // Input area
                HStack(spacing: 12) {
                    TextField("Ask about this recording...", text: $inputText)
                        .font(AppFont.mono(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(inputText.isEmpty ? .gray : .white)
                    }
                    .disabled(inputText.isEmpty || isLoading)
                }
                .padding()
                .background(Color.black)
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ASK YOUR AUDIO")
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(AppFont.mono(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    private func sendMessage() {
        let userMessage = ChatMessage(role: .user, content: inputText)
        messages.append(userMessage)
        let question = inputText
        inputText = ""
        isLoading = true
        
        Task {
            do {
                let response = try await askAboutTranscript(question: question)
                let assistantMessage = ChatMessage(role: .assistant, content: response)
                await MainActor.run {
                    messages.append(assistantMessage)
                    isLoading = false
                }
            } catch {
                let errorMessage = ChatMessage(role: .assistant, content: "Sorry, I couldn't process that question. Please try again.")
                await MainActor.run {
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }
    
    private func askAboutTranscript(question: String) async throws -> String {
        // This would call the AI service with the transcript context
        // For now, we'll use a simulated response based on the transcript
        
        guard let transcript = recording.transcriptFullText else {
            return "No transcript available for this recording."
        }
        
        // In production, this would call Gemini/OpenAI API
        // For demo purposes, provide context-aware responses
        try await Task.sleep(for: .seconds(1.5))
        
        let lowercaseQuestion = question.lowercased()
        
        if lowercaseQuestion.contains("summary") || lowercaseQuestion.contains("about") {
            if let summary = recording.summary {
                return "Based on the recording: \(summary.oneLiner)\n\n\(summary.context)"
            } else {
                return "This recording discusses: \(String(transcript.prefix(200)))..."
            }
        }
        
        if lowercaseQuestion.contains("action") || lowercaseQuestion.contains("todo") || lowercaseQuestion.contains("task") {
            if let actions = recording.summaryActions, !actions.isEmpty {
                var response = "Here are the action items from this recording:\n\n"
                for (index, action) in actions.enumerated() {
                    response += "\(index + 1). \(action.task) (assigned to \(action.assignee))\n"
                }
                return response
            } else {
                return "I didn't find any specific action items in this recording."
            }
        }
        
        if lowercaseQuestion.contains("speaker") || lowercaseQuestion.contains("who") {
            let speakers = recording.uniqueSpeakers
            if speakers.isEmpty {
                return "Speaker identification is not available for this recording."
            }
            let speakerNames = recording.speakerNames ?? [:]
            let speakerList = speakers.map { speakerNames[$0] ?? $0 }.joined(separator: ", ")
            return "The speakers in this recording are: \(speakerList)"
        }
        
        if lowercaseQuestion.contains("long") || lowercaseQuestion.contains("duration") {
            return "This recording is \(recording.duration.durationLabel) long."
        }
        
        // Generic response with transcript context
        return "Based on the transcript, here's what I found relevant to your question:\n\n\(String(transcript.prefix(500)))...\n\nWould you like me to look for something more specific?"
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp = Date()
}

enum ChatRole {
    case user
    case assistant
}

struct ChatBubble: View {
    let message: ChatMessage
    let isUser: Bool
    
    var body: some View {
        HStack {
            if isUser { Spacer() }
            
            Text(message.content)
                .font(AppFont.mono(size: 13, weight: .regular))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isUser ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            
            if !isUser { Spacer() }
        }
    }
}

// MARK: - Audio Search

struct AudioSearchView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchQuery = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                    
                    TextField("Search in transcript...", text: $searchQuery)
                        .font(AppFont.mono(size: 14))
                        .foregroundStyle(.white)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.08))
                
                // Results
                if isSearching {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Text("Searching...")
                        .font(AppFont.mono(size: 12))
                        .foregroundStyle(.gray)
                        .padding(.top, 8)
                    Spacer()
                } else if searchResults.isEmpty && !searchQuery.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(Color.muted)
                        Text("No results found")
                            .font(AppFont.mono(size: 14, weight: .medium))
                            .foregroundStyle(.gray)
                        Text("Try different keywords")
                            .font(AppFont.mono(size: 12, weight: .regular))
                            .foregroundStyle(.gray.opacity(0.7))
                    }
                    Spacer()
                } else if searchResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(Color.muted)
                        Text("Search your audio")
                            .font(AppFont.mono(size: 14, weight: .medium))
                            .foregroundStyle(.gray)
                        Text("Find specific moments by searching\nfor words or phrases")
                            .font(AppFont.mono(size: 12, weight: .regular))
                            .foregroundStyle(.gray.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(searchResults) { result in
                                SearchResultRow(result: result, recording: recording)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AUDIO SEARCH")
                        .font(AppFont.mono(size: 13, weight: .semibold))
                        .kerning(2.0)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .font(AppFont.mono(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty, let segments = recording.transcriptSegments else { return }
        
        isSearching = true
        searchResults = []
        
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            
            let query = searchQuery.lowercased()
            var results: [SearchResult] = []
            
            let speakerNames = recording.speakerNames ?? [:]
            
            for (index, segment) in segments.enumerated() {
                if segment.text.lowercased().contains(query) {
                    let speaker = speakerNames[segment.speaker] ?? segment.speaker
                    results.append(SearchResult(
                        segmentIndex: index,
                        speaker: speaker,
                        text: segment.text,
                        timestamp: segment.timestamp,
                        matchedQuery: searchQuery
                    ))
                }
            }
            
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let segmentIndex: Int
    let speaker: String
    let text: String
    let timestamp: TimeInterval
    let matchedQuery: String
}

struct SearchResultRow: View {
    let result: SearchResult
    let recording: Recording
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.timestamp.formatted)
                    .font(AppFont.mono(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("•")
                    .foregroundStyle(.gray)
                
                Text(result.speaker)
                    .font(AppFont.mono(size: 11, weight: .medium))
                    .foregroundStyle(.gray)
                
                Spacer()
                
                Image(systemName: "play.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            // Highlighted text
            highlightedText
        }
        .padding(12)
        .glassCard(radius: 10)
    }
    
    private var highlightedText: some View {
        let text = result.text
        let query = result.matchedQuery.lowercased()
        
        if let range = text.lowercased().range(of: query) {
            let before = String(text[..<range.lowerBound])
            let match = String(text[range])
            let after = String(text[range.upperBound...])
            
            var attributed = AttributedString(before)
            attributed.font = .system(size: 13, weight: .regular, design: .monospaced)
            attributed.foregroundColor = .gray
            
            var matchAttr = AttributedString(match)
            matchAttr.font = .system(size: 13, weight: .bold, design: .monospaced)
            matchAttr.foregroundColor = .white
            
            var afterAttr = AttributedString(after)
            afterAttr.font = .system(size: 13, weight: .regular, design: .monospaced)
            afterAttr.foregroundColor = .gray
            
            return Text(attributed + matchAttr + afterAttr)
        } else {
            return Text(text)
                .font(AppFont.mono(size: 13, weight: .regular))
                .foregroundStyle(.gray)
        }
    }
}

// MARK: - Feature Gate Helper

struct FeatureGate {
    static func canAccess(_ feature: PremiumFeature) -> Bool {
        let tier = SubscriptionManager.shared.currentTier
        switch feature {
        case .transcription:
            return tier == .standard || tier == .pro
        case .audioUpload:
            return tier == .standard || tier == .pro
        case .exportPDF, .exportMarkdown:
            return tier == .standard || tier == .pro
        case .speakerIdentification:
            return tier == .standard || tier == .pro
        case .askYourAudio:
            return tier == .pro
        case .audioSearch:
            return tier == .pro
        case .priorityProcessing:
            return tier == .pro
        case .longFileUpload:
            return tier == .pro
        case .unlimitedHistory:
            return tier == .standard || tier == .pro
        }
    }
    
    static func requiredTier(for feature: PremiumFeature) -> SubscriptionTier {
        switch feature {
        case .transcription, .audioUpload, .exportPDF, .exportMarkdown, .speakerIdentification, .unlimitedHistory:
            return .standard
        case .askYourAudio, .audioSearch, .priorityProcessing, .longFileUpload:
            return .pro
        }
    }
}

enum PremiumFeature {
    case transcription
    case audioUpload
    case exportPDF
    case exportMarkdown
    case speakerIdentification
    case askYourAudio
    case audioSearch
    case priorityProcessing
    case longFileUpload
    case unlimitedHistory
    
    var displayName: String {
        switch self {
        case .transcription: return "AI Transcription"
        case .audioUpload: return "Audio Upload"
        case .exportPDF: return "Export to PDF"
        case .exportMarkdown: return "Export to Markdown"
        case .speakerIdentification: return "Speaker Identification"
        case .askYourAudio: return "Ask Your Audio"
        case .audioSearch: return "Audio Search"
        case .priorityProcessing: return "Priority Processing"
        case .longFileUpload: return "Long File Upload"
        case .unlimitedHistory: return "Unlimited History"
        }
    }
}
