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
                        let hasAccess = url.startAccessingSecurityScopedResource()
                        print("📁 [Import] Security-scoped access: \(hasAccess)")
                        defer { 
                            if hasAccess { url.stopAccessingSecurityScopedResource() }
                        }
                        
                        // Copy to app's documents directory
                        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let recordingsDir = documentsDir.appendingPathComponent("Recordings", isDirectory: true)
                        
                        do {
                            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                        } catch {
                            print("📁 [Import] Failed to create Recordings directory: \(error)")
                        }
                        
                        let fileName = "imported_\(UUID().uuidString).\(url.pathExtension)"
                        let destinationURL = recordingsDir.appendingPathComponent(fileName)
                        
                        print("📁 [Import] Source: \(url.path)")
                        print("📁 [Import] Destination: \(destinationURL.path)")
                        
                        do {
                            // Check if source exists and is readable
                            guard FileManager.default.isReadableFile(atPath: url.path) else {
                                print("📁 [Import] ERROR: Source file is not readable")
                                return
                            }
                            
                            // Remove existing file if present
                            if FileManager.default.fileExists(atPath: destinationURL.path) {
                                try FileManager.default.removeItem(at: destinationURL)
                            }
                            
                            try FileManager.default.copyItem(at: url, to: destinationURL)
                            
                            // Verify the copy succeeded
                            if FileManager.default.fileExists(atPath: destinationURL.path) {
                                let attrs = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                                let size = attrs[.size] as? Int64 ?? 0
                                print("📁 [Import] SUCCESS: Copied \(size) bytes to \(destinationURL.lastPathComponent)")
                                onImport(destinationURL)
                            } else {
                                print("📁 [Import] ERROR: File copy succeeded but file doesn't exist at destination")
                            }
                        } catch {
                            print("📁 [Import] Failed to copy imported file: \(error)")
                        }
                    }
                case .failure(let error):
                    print("📁 [Import] File import failed: \(error)")
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
            
            let brandingAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            
            var yPosition: CGFloat = 40
            let margin: CGFloat = 50
            let maxWidth = pageRect.width - (margin * 2)
            
            // Signal Logo at top
            if let logoImage = UIImage(named: "SignalLogoBlackNoBG") {
                let logoHeight: CGFloat = 30
                let logoAspectRatio = logoImage.size.width / logoImage.size.height
                let logoWidth = logoHeight * logoAspectRatio
                let logoRect = CGRect(x: margin, y: yPosition, width: logoWidth, height: logoHeight)
                logoImage.draw(in: logoRect)
                
                // "Transcribed with Signal" text next to logo
                let brandingText = "Transcribed with Signal" as NSString
                let brandingX = margin + logoWidth + 12
                brandingText.draw(at: CGPoint(x: brandingX, y: yPosition + 10), withAttributes: brandingAttributes)
            }
            
            yPosition += 50
            
            // Separator line
            context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
            context.cgContext.setLineWidth(0.5)
            context.cgContext.move(to: CGPoint(x: margin, y: yPosition))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition))
            context.cgContext.strokePath()
            yPosition += 20
            
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
                var previousSpeaker: String? = nil
                
                for segment in segments.prefix(20) { // Limit for PDF
                    if yPosition > pageRect.height - 100 {
                        context.beginPage()
                        yPosition = 50
                    }
                    
                    let speaker = speakerNames[segment.speaker] ?? segment.speaker
                    
                    // Add extra spacing when speaker changes
                    if let prev = previousSpeaker, prev != speaker {
                        yPosition += 15
                    }
                    
                    let line = "[\(segment.timestamp.formatted)] \(speaker): \(segment.text)" as NSString
                    let lineRect = CGRect(x: margin, y: yPosition, width: maxWidth, height: 60)
                    line.draw(in: lineRect, withAttributes: bodyAttributes)
                    yPosition += 50
                    
                    previousSpeaker = speaker
                }
            }
            
            // Footer with branding at bottom of last page
            let footerY = pageRect.height - 60
            context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
            context.cgContext.setLineWidth(0.5)
            context.cgContext.move(to: CGPoint(x: margin, y: footerY))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: footerY))
            context.cgContext.strokePath()
            
            let footerText = "Transcribed with Signal • signal.app" as NSString
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: UIColor.lightGray
            ]
            let footerSize = footerText.size(withAttributes: footerAttributes)
            let footerX = (pageRect.width - footerSize.width) / 2
            footerText.draw(at: CGPoint(x: footerX, y: footerY + 8), withAttributes: footerAttributes)
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
        let tier = SubscriptionManager.shared.currentTier.baseLevel
        let subscription = SubscriptionManager.shared
        
        switch feature {
        case .transcription:
            return true  // Everyone can transcribe (free: 15min, paid: more)
        case .aiSummarization:
            return tier == .standard || tier == .pro  // Free tier: no AI analysis
        case .onDeviceTranscription:
            return subscription.hasOnDeviceAccess  // Privacy pack or Standard+
        case .onDeviceSummarization:
            return subscription.hasOnDeviceAccess  // Privacy pack or Standard+
        case .audioUpload:
            return tier == .standard || tier == .pro
        case .exportPDF, .exportMarkdown:
            return tier == .standard || tier == .pro
        case .speakerIdentification:
            return tier == .standard || tier == .pro
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
        case .transcription:
            return .free  // Everyone can transcribe
        case .aiSummarization, .onDeviceTranscription, .onDeviceSummarization, .audioUpload, .exportPDF, .exportMarkdown, .speakerIdentification, .unlimitedHistory:
            return .standardMonthly
        case .audioSearch, .priorityProcessing, .longFileUpload:
            return .proMonthly
        }
    }
}

enum PremiumFeature {
    case transcription
    case aiSummarization
    case onDeviceTranscription
    case onDeviceSummarization
    case audioUpload
    case exportPDF
    case exportMarkdown
    case speakerIdentification
    case audioSearch
    case priorityProcessing
    case longFileUpload
    case unlimitedHistory
    
    var displayName: String {
        switch self {
        case .transcription: return "AI Transcription"
        case .aiSummarization: return "AI Summarization"
        case .onDeviceTranscription: return "On-Device Transcription"
        case .onDeviceSummarization: return "On-Device Summarization"
        case .audioUpload: return "Audio Upload"
        case .exportPDF: return "Export to PDF"
        case .exportMarkdown: return "Export to Markdown"
        case .speakerIdentification: return "Speaker Identification"
        case .audioSearch: return "Audio Search"
        case .priorityProcessing: return "Priority Processing"
        case .longFileUpload: return "Long File Upload"
        case .unlimitedHistory: return "Unlimited History"
        }
    }
}
