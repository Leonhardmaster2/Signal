import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

// MARK: - Signal Package Exporter

@MainActor
final class SignalPackageExporter {
    static let shared = SignalPackageExporter()
    
    private init() {}
    
    /// Create a Signal package (.signal) that includes audio, transcript, and metadata
    func createSignalPackage(recording: Recording) -> URL? {
        // Create temporary directory for package
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create package structure
        let packageName = "\(recording.title).signal"
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
        # Signal Recording Package
        
        Recording: \(recording.title)
        Date: \(recording.date.formatted())
        Duration: \(recording.duration.durationLabel)
        
        This package contains:
        - audio.m4a: The original audio recording
        - metadata.json: All recording metadata including transcripts and summaries
        - images/: Any attached note images
        
        Import this package into Signal to restore the complete recording with all its data.
        
        Generated by Signal - https://signal.app
        """
        
        let readmeURL = packageURL.appendingPathComponent("README.txt")
        try? readme.write(to: readmeURL, atomically: true, encoding: .utf8)
        
        return packageURL
    }
    
    /// Clean up temporary package files
    func cleanupPackage(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
