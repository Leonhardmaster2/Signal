import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import CoreText

// MARK: - Audio File Importer

struct AudioFileImporter: ViewModifier {
    @Binding var isPresented: Bool
    let onImport: (URL) -> Void
    
    // Define the trace package UTType using exportedAs (our app owns this type)
    private var tracePackageType: UTType {
        UTType(exportedAs: "com.proceduralabs.trace.package")
    }
    
    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [
                    .audio, .mpeg4Audio, .mp3, .wav, .aiff,
                    tracePackageType, .zip
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        // Need to start accessing security-scoped resource
                        let hasAccess = url.startAccessingSecurityScopedResource()
                        print("📁 [Import] Security-scoped access: \(hasAccess)")

                        // Check if it's a .traceaudio package (or legacy .trace)
                        let ext = url.pathExtension.lowercased()
                        if ext == "traceaudio" || ext == "trace" ||
                           (ext == "zip" && url.lastPathComponent.contains(".traceaudio.")) {
                            print("📁 [Import] Detected Trace package, copying while access is active")

                            // Copy the .traceaudio package to temp while we still have security-scoped access
                            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            do {
                                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                                let tempCopy = tempDir.appendingPathComponent(url.lastPathComponent)
                                try FileManager.default.copyItem(at: url, to: tempCopy)

                                // Release security-scoped access now that we've copied
                                if hasAccess { url.stopAccessingSecurityScopedResource() }

                                print("📁 [Import] Copied .traceaudio package to temp: \(tempCopy.path)")
                                onImport(tempCopy)
                            } catch {
                                print("❌ [Import] Failed to copy .traceaudio package: \(error)")
                                if hasAccess { url.stopAccessingSecurityScopedResource() }
                            }
                            return
                        }

                        // Copy audio files to app's documents directory
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
                                if hasAccess { url.stopAccessingSecurityScopedResource() }
                                return
                            }

                            // Remove existing file if present
                            if FileManager.default.fileExists(atPath: destinationURL.path) {
                                try FileManager.default.removeItem(at: destinationURL)
                            }

                            try FileManager.default.copyItem(at: url, to: destinationURL)

                            // Release security-scoped access after copy
                            if hasAccess { url.stopAccessingSecurityScopedResource() }

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
                            if hasAccess { url.stopAccessingSecurityScopedResource() }
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
        
        markdown += "\n---\n*Exported from Trace*\n"
        
        return markdown
    }
    
    /// Export transcript as PDF
    func exportAsPDF(recording: Recording) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let margin: CGFloat = 50
        let maxWidth = pageRect.width - (margin * 2)
        let bottomMargin: CGFloat = 80 // Space reserved for footer

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

        let speakerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.black
        ]

        let brandingAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]

        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: UIColor.lightGray
        ]

        let data = renderer.pdfData { context in
            var yPosition: CGFloat = 0

            /// Measure how tall a string will be when drawn in a rect of given width
            func textHeight(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
                let nsText = text as NSString
                let rect = nsText.boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                return ceil(rect.height)
            }

            /// Start a new page and draw header/footer
            func newPage() {
                context.beginPage()
                yPosition = 40

                // Header branding on every page
                if let logoImage = UIImage(named: "TraceLogoBlackNoBG") {
                    let logoHeight: CGFloat = 20
                    let logoAspectRatio = logoImage.size.width / logoImage.size.height
                    let logoWidth = logoHeight * logoAspectRatio
                    logoImage.draw(in: CGRect(x: margin, y: yPosition, width: logoWidth, height: logoHeight))

                    let brandingText = "Transcribed with Trace" as NSString
                    brandingText.draw(at: CGPoint(x: margin + logoWidth + 8, y: yPosition + 4), withAttributes: brandingAttributes)
                }
                yPosition += 30

                // Separator
                context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
                context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: margin, y: yPosition))
                context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: yPosition))
                context.cgContext.strokePath()
                yPosition += 15
            }

            /// Draw footer on the current page
            func drawFooter() {
                let footerY = pageRect.height - 40
                context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
                context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: margin, y: footerY))
                context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: footerY))
                context.cgContext.strokePath()

                let footerText = "Transcribed with Trace \u{2022} trace.app" as NSString
                let footerSize = footerText.size(withAttributes: footerAttributes)
                let footerX = (pageRect.width - footerSize.width) / 2
                footerText.draw(at: CGPoint(x: footerX, y: footerY + 6), withAttributes: footerAttributes)
            }

            /// Ensure there's enough space; start a new page if not
            func ensureSpace(_ needed: CGFloat) {
                if yPosition + needed > pageRect.height - bottomMargin {
                    drawFooter()
                    newPage()
                }
            }

            /// Available space remaining on the current page
            func availableSpace() -> CGFloat {
                pageRect.height - bottomMargin - yPosition
            }

            /// Draw a text block that may be split across pages if it's too tall.
            /// Uses CoreText (CTFramesetter) to determine natural line-break points.
            func drawTextBlock(_ text: String, attributes: [NSAttributedString.Key: Any], xOffset: CGFloat = 0, width: CGFloat? = nil) {
                let drawWidth = (width ?? maxWidth) - xOffset
                let fullHeight = textHeight(text, attributes: attributes, width: drawWidth)
                let remaining = availableSpace()

                // If it fits on the current page, draw normally
                if fullHeight <= remaining {
                    (text as NSString).draw(
                        in: CGRect(x: margin + xOffset, y: yPosition, width: drawWidth, height: fullHeight),
                        withAttributes: attributes
                    )
                    yPosition += fullHeight
                    return
                }

                // Split across pages using CTFramesetter
                let attrString = NSAttributedString(string: text, attributes: attributes)
                let framesetter = CTFramesetterCreateWithAttributedString(attrString)
                var startIndex = 0
                let totalLength = attrString.length

                while startIndex < totalLength {
                    let space = availableSpace()

                    // If barely any space left, start a new page
                    if space < 30 {
                        drawFooter()
                        newPage()
                        continue
                    }

                    // Ask CoreText how many characters fit in the remaining space
                    let constraintSize = CGSize(width: drawWidth, height: space)
                    var fitRange = CFRange(location: 0, length: 0)
                    CTFramesetterSuggestFrameSizeWithConstraints(
                        framesetter,
                        CFRange(location: startIndex, length: totalLength - startIndex),
                        nil,
                        constraintSize,
                        &fitRange
                    )

                    if fitRange.length <= 0 {
                        // Safety: if CoreText says nothing fits, force a new page
                        drawFooter()
                        newPage()
                        continue
                    }

                    // Extract the substring that fits and draw it
                    let nsText = text as NSString
                    let endIndex = startIndex + fitRange.length
                    let chunk = nsText.substring(with: NSRange(location: startIndex, length: fitRange.length))
                    let chunkHeight = textHeight(chunk, attributes: attributes, width: drawWidth)

                    (chunk as NSString).draw(
                        in: CGRect(x: margin + xOffset, y: yPosition, width: drawWidth, height: chunkHeight),
                        withAttributes: attributes
                    )
                    yPosition += chunkHeight

                    startIndex = endIndex

                    // If there's more text, start a new page
                    if startIndex < totalLength {
                        drawFooter()
                        newPage()
                    }
                }
            }

            // --- First page ---
            newPage()

            // Title
            let titleHeight = textHeight(recording.title, attributes: titleAttributes, width: maxWidth)
            (recording.title as NSString).draw(
                in: CGRect(x: margin, y: yPosition, width: maxWidth, height: titleHeight),
                withAttributes: titleAttributes
            )
            yPosition += titleHeight + 12

            // Metadata
            let dateStr = "Date: \(formatDate(recording.date))"
            (dateStr as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 18

            let durationStr = "Duration: \(recording.duration.durationLabel)"
            (durationStr as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
            yPosition += 30

            // Summary
            if let summary = recording.summary {
                ensureSpace(80)
                ("Summary" as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                yPosition += 22

                // One-liner
                drawTextBlock(summary.oneLiner, attributes: bodyAttributes)
                yPosition += 15

                // Context
                if !summary.context.isEmpty {
                    ensureSpace(30)
                    ("Context" as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                    yPosition += 22

                    drawTextBlock(summary.context, attributes: bodyAttributes)
                    yPosition += 15
                }

                // Action items
                if !summary.actionVectors.isEmpty {
                    ensureSpace(30)
                    ("Action Items" as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                    yPosition += 22

                    for action in summary.actionVectors {
                        let checkbox = action.isCompleted ? "\u{2611}" : "\u{2610}"
                        let actionText = "\(checkbox) \(action.assignee): \(action.task)"
                        drawTextBlock(actionText, attributes: bodyAttributes, xOffset: 10)
                        yPosition += 6
                    }
                    yPosition += 10
                }
            }

            // Transcript — ALL segments, no limit
            if let segments = recording.transcriptSegments, !segments.isEmpty {
                ensureSpace(40)
                ("Transcript" as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                yPosition += 25

                let speakerNames = recording.speakerNames ?? [:]
                var previousSpeaker: String? = nil

                for segment in segments {
                    let speaker = speakerNames[segment.speaker] ?? segment.speaker
                    let timestamp = segment.timestamp.formatted

                    // Extra spacing on speaker change
                    if let prev = previousSpeaker, prev != speaker {
                        yPosition += 10
                    }

                    // Speaker + timestamp header
                    let speakerLine = "[\(timestamp)] \(speaker)"
                    let speakerHeight = textHeight(speakerLine, attributes: speakerAttributes, width: maxWidth)
                    ensureSpace(speakerHeight + 20) // at least room for header + some text
                    (speakerLine as NSString).draw(
                        in: CGRect(x: margin, y: yPosition, width: maxWidth, height: speakerHeight),
                        withAttributes: speakerAttributes
                    )
                    yPosition += speakerHeight + 3

                    // Segment text (splits across pages if needed)
                    drawTextBlock(segment.text, attributes: bodyAttributes, xOffset: 10)
                    yPosition += 8

                    previousSpeaker = speaker
                }
            }

            // Notes
            if let notes = recording.notes, !notes.isEmpty {
                ensureSpace(40)
                ("Notes" as NSString).draw(at: CGPoint(x: margin, y: yPosition), withAttributes: headerAttributes)
                yPosition += 22

                drawTextBlock(notes, attributes: bodyAttributes)
                yPosition += 10
            }

            // Final footer
            drawFooter()
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
        case .audioSearch: return "Ask Your Audio"
        case .priorityProcessing: return "Priority Processing"
        case .longFileUpload: return "Long File Upload"
        case .unlimitedHistory: return "Unlimited History"
        }
    }
}
