import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers
import SwiftData

#if os(macOS)
import AppKit

struct ShareSheet: View {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.share)
                .font(.headline)

            if let url = items.first as? URL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(L10n.showInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.copyToClipboard) {
                    if url.isFileURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([url as NSURL])
                    }
                    dismiss()
                }
                .buttonStyle(.bordered)
            } else if let text = items.first as? String {
                Button(L10n.copyToClipboard) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            Button(L10n.cancel) {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .frame(minWidth: 300)
    }
}

#else

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Process items to ensure files are properly shared
        let processedItems = items.map { item -> Any in
            if let url = item as? URL {
                // For file URLs, ensure we're sharing the file content
                if url.isFileURL {
                    // Check if file exists
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        print("⚠️ ShareSheet: File doesn't exist at \(url.path)")
                        return url
                    }
                    
                    // Return the URL - UIActivityViewController will handle it
                    return url
                }
            }
            return item
        }
        
        let controller = UIActivityViewController(activityItems: processedItems, applicationActivities: nil)
        
        // CRITICAL: Configure popover for iPad/Mac Catalyst
        // Without this, the app will crash on iPad and Mac
        if let popover = controller.popoverPresentationController {
            // Use screen center as default anchor - this prevents crashes
            popover.permittedArrowDirections = []
            popover.sourceView = UIView()
            popover.sourceRect = CGRect(
                x: UIScreen.main.bounds.midX,
                y: UIScreen.main.bounds.midY,
                width: 0,
                height: 0
            )
        }
        
        // Configure for better file sharing
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            if let error = error {
                print("❌ ShareSheet error: \(error.localizedDescription)")
            }
            if completed {
                print("✅ Share completed with activity: \(activityType?.rawValue ?? "unknown")")
            }
        }
        
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#endif

// MARK: - Trace Package Exporter

@MainActor
final class TracePackageExporter {
    static let shared = TracePackageExporter()
    
    private init() {}
    
    /// Create a Trace package (.traceaudio) that includes audio, transcript, and metadata
    /// Returns a directory URL for sharing
    func createTracePackage(recording: Recording) -> URL? {
        // Create temporary directory for package
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create package structure
        let packageName = "\(recording.title).traceaudio"
        let packageURL = tempDir.appendingPathComponent(packageName)
        try? FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        
        // Copy audio file
        if let audioURL = recording.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            let audioDestination = packageURL.appendingPathComponent("audio.m4a")
            try? FileManager.default.copyItem(at: audioURL, to: audioDestination)
        }
        
        // Create metadata JSON
        let metadata: [String: Any] = [
            "title": recording.title,
            "date": recording.date.timeIntervalSince1970,
            "duration": recording.duration,
            "isStarred": recording.isStarred,
            "marks": recording.marks,
            "transcriptFullText": recording.transcriptFullText ?? "",
            "transcriptLanguage": recording.transcriptLanguage ?? "",
            "transcriptSegments": recording.transcriptSegments?.map { segment in
                return [
                    "speaker": segment.speaker,
                    "text": segment.text,
                    "timestamp": segment.timestamp
                ]
            } ?? [],
            "summaryOneLiner": recording.summaryOneLiner ?? "",
            "summaryContext": recording.summaryContext ?? "",
            "summaryActions": recording.summaryActions?.map { action in
                return [
                    "task": action.task,
                    "assignee": action.assignee,
                    "isCompleted": action.isCompleted
                ]
            } ?? [],
            "notes": recording.notes ?? "",
            "speakerNames": recording.speakerNames ?? [:],
            "wasTranscribedOnDevice": recording.wasTranscribedOnDevice ?? false,
            "wasSummarizedOnDevice": recording.wasSummarizedOnDevice ?? false,
            "version": "1.0"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
            let metadataURL = packageURL.appendingPathComponent("metadata.json")
            try? jsonData.write(to: metadataURL)
        }
        
        // Copy note images if any
        if let noteImageNames = recording.noteImageNames, !noteImageNames.isEmpty {
            let imagesDir = packageURL.appendingPathComponent("images")
            try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            
            for imageName in noteImageNames {
                let sourceURL = Recording.notesImageDirectory.appendingPathComponent(imageName)
                let destURL = imagesDir.appendingPathComponent(imageName)
                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }
        
        // Create README
        let readme = """
        # Trace Recording Package
        
        Recording: \(recording.title)
        Date: \(recording.date.formatted())
        Duration: \(recording.duration.durationLabel)
        
        This package contains:
        - audio.m4a: The original audio recording
        - metadata.json: All recording metadata including transcripts and summaries
        - images/: Any attached note images
        
        Import this package into Trace to restore the complete recording with all its data.
        
        Generated by Trace - https://trace.app
        """
        
        let readmeURL = packageURL.appendingPathComponent("README.txt")
        try? readme.write(to: readmeURL, atomically: true, encoding: .utf8)
        
        // Return the .trace directory directly
        // iOS handles sharing directories just fine
        return packageURL
    }
    
    /// Creates a ZIP archive from a directory
    private func createZipArchive(from sourceDir: URL, to destinationURL: URL) -> URL? {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        var resultURL: URL?
        
        coordinator.coordinate(readingItemAt: sourceDir, options: .forUploading, error: &error) { zipURL in
            do {
                // The coordinator gives us a temporary zip, copy it to our destination
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
                resultURL = destinationURL
            } catch {
                print("❌ Failed to create ZIP: \(error)")
            }
        }
        
        if let error = error {
            print("❌ Coordination error: \(error)")
            return nil
        }
        
        return resultURL
    }
    
    /// Clean up temporary package files
    func cleanupPackage(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    
    /// Import a Trace package (.traceaudio or legacy .trace) and restore the recording
    @MainActor
    func importTracePackage(from url: URL, modelContext: ModelContext) async -> Bool {
        print("📦 Starting import from: \(url.path)")

        // Start security-scoped access if needed (for onOpenURL)
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create temp directory: \(error)")
            return false
        }

        var packageDir: URL?

        // Check what we received
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            // It's already a directory — copy it to temp
            do {
                let tempTrace = tempDir.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: tempTrace)
                packageDir = tempTrace
                print("📦 Copied .traceaudio directory to: \(tempTrace.path)")
            } catch {
                print("❌ Failed to copy .traceaudio directory: \(error)")
            }
        } else if exists && !isDirectory.boolValue {
            // It's a flat file — could be a zip or a file-based .traceaudio/.trace package
            // Try to unzip it first
            let ext = url.pathExtension.lowercased()
            if ext == "zip" || ext == "traceaudio" || ext == "trace" {
                // Try NSFileCoordinator to unzip
                let coordinator = NSFileCoordinator()
                var coordError: NSError?
                coordinator.coordinate(readingItemAt: url, options: .forUploading, error: &coordError) { _ in }

                // Try copying as-is first (might be a directory on disk)
                do {
                    let tempTrace = tempDir.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: tempTrace)

                    // Check if it's a directory after copy
                    var copiedIsDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: tempTrace.path, isDirectory: &copiedIsDir)

                    if copiedIsDir.boolValue {
                        packageDir = tempTrace
                        print("📦 Copied as directory: \(tempTrace.path)")
                    } else {
                        // It's a flat file — look for metadata.json inside
                        // Some systems (AirDrop, Files app) wrap .traceaudio as a flat zip
                        // The metadata.json might be directly inside
                        packageDir = tempTrace
                        print("📦 Copied as file, will try to read directly: \(tempTrace.path)")
                    }
                } catch {
                    print("❌ Failed to copy .traceaudio file: \(error)")
                }
            }
        } else {
            print("❌ File does not exist at path: \(url.path)")
        }

        guard let packageDir = packageDir else {
            print("❌ Could not determine package directory")
            try? FileManager.default.removeItem(at: tempDir)
            return false
        }
        
        // Read metadata
        let metadataURL = packageDir.appendingPathComponent("metadata.json")
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] else {
            return false
        }
        
        // Create new recording
        let title = metadata["title"] as? String ?? "Imported Recording"
        let date = metadata["date"] as? TimeInterval != nil ? Date(timeIntervalSince1970: metadata["date"] as! TimeInterval) : Date()
        let recording = Recording(title: title, date: date)
        
        recording.duration = metadata["duration"] as? TimeInterval ?? 0
        recording.isStarred = metadata["isStarred"] as? Bool ?? false
        recording.marks = metadata["marks"] as? [TimeInterval] ?? []
        recording.transcriptFullText = metadata["transcriptFullText"] as? String
        recording.transcriptLanguage = metadata["transcriptLanguage"] as? String
        recording.summaryOneLiner = metadata["summaryOneLiner"] as? String
        recording.summaryContext = metadata["summaryContext"] as? String
        recording.notes = metadata["notes"] as? String
        recording.speakerNames = metadata["speakerNames"] as? [String: String] ?? [:]
        recording.wasTranscribedOnDevice = metadata["wasTranscribedOnDevice"] as? Bool
        recording.wasSummarizedOnDevice = metadata["wasSummarizedOnDevice"] as? Bool
        
        // Import transcript segments
        if let segments = metadata["transcriptSegments"] as? [[String: Any]] {
            recording.transcriptSegments = segments.compactMap { seg -> SegmentData? in
                guard let speaker = seg["speaker"] as? String,
                      let text = seg["text"] as? String,
                      let timestamp = seg["timestamp"] as? TimeInterval else { return nil }
                return SegmentData(speaker: speaker, text: text, timestamp: timestamp)
            }
        }
        
        // Import summary actions
        if let actions = metadata["summaryActions"] as? [[String: Any]] {
            recording.summaryActions = actions.compactMap { act -> ActionData? in
                guard let task = act["task"] as? String,
                      let assignee = act["assignee"] as? String else { return nil }
                return ActionData(
                    assignee: assignee,
                    task: task,
                    isCompleted: act["isCompleted"] as? Bool ?? false,
                    timestamp: act["timestamp"] as? TimeInterval
                )
            }
        }
        
        // Copy audio file
        let audioSource = packageDir.appendingPathComponent("audio.m4a")
        if FileManager.default.fileExists(atPath: audioSource.path) {
            let audioFilename = "trace_\(Int(Date().timeIntervalSince1970)).m4a"
            let recordingsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("Recordings")
            try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
            let audioDestination = recordingsDir.appendingPathComponent(audioFilename)
            try? FileManager.default.copyItem(at: audioSource, to: audioDestination)
            recording.audioFileName = audioFilename
        }
        
        // Copy note images
        let imagesSource = packageDir.appendingPathComponent("images")
        if FileManager.default.fileExists(atPath: imagesSource.path) {
            let imageFiles = try? FileManager.default.contentsOfDirectory(at: imagesSource, includingPropertiesForKeys: nil)
            if let imageFiles = imageFiles {
                var imageNames: [String] = []
                for imageFile in imageFiles {
                    let destURL = Recording.notesImageDirectory.appendingPathComponent(imageFile.lastPathComponent)
                    try? FileManager.default.copyItem(at: imageFile, to: destURL)
                    imageNames.append(imageFile.lastPathComponent)
                }
                recording.noteImageNames = imageNames
            }
        }
        
        // Save to model context
        modelContext.insert(recording)
        try? modelContext.save()
        
        // Clean up temp files
        try? FileManager.default.removeItem(at: tempDir)
        
        return true
    }
}
