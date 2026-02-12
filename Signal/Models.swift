import Foundation
import SwiftData

// MARK: - Recording (Persisted)

@Model
final class Recording {
    @Attribute(.unique) var uid: UUID
    var title: String
    var date: Date
    var duration: TimeInterval
    var amplitudeSamples: [Float]
    var isStarred: Bool
    var isArchived: Bool
    var marks: [TimeInterval]
    var audioFileName: String?

    // Transcript data (flattened for SwiftData)
    var transcriptFullText: String?
    var transcriptSegments: [SegmentData]?
    var transcriptLanguage: String?

    // Summary data (flattened)
    var summaryOneLiner: String?
    var summaryContext: String?
    var summaryActions: [ActionData]?
    var summarySources: [SourceData]?

    // Meeting notes
    var notes: String?

    // Note images (stored as file names in the Notes directory)
    var noteImageNames: [String]?

    // Speaker name mapping (e.g. "speaker_0" -> "John")
    var speakerNames: [String: String]?

    // Processing state
    var isTranscribing: Bool
    var transcriptionError: String?
    var transcriptionProgress: Double?  // 0.0 to 1.0, optional for migration
    var isSummarizing: Bool
    var summarizationError: String?
    
    // On-device processing flags (optional for migration compatibility)
    var wasTranscribedOnDevice: Bool?
    var wasSummarizedOnDevice: Bool?

    init(
        title: String,
        date: Date = Date(),
        duration: TimeInterval = 0,
        amplitudeSamples: [Float] = [],
        audioFileName: String? = nil
    ) {
        self.uid = UUID()
        self.title = title
        self.date = date
        self.duration = duration
        self.amplitudeSamples = amplitudeSamples
        self.isStarred = false
        self.isArchived = false
        self.marks = []
        self.audioFileName = audioFileName
        self.isTranscribing = false
        self.transcriptionProgress = nil
        self.isSummarizing = false
        self.wasTranscribedOnDevice = nil
        self.wasSummarizedOnDevice = nil
    }

    var audioURL: URL? {
        guard let name = audioFileName else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Recordings").appendingPathComponent(name)
    }

    /// Directory for storing note images
    static var notesImageDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("NoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// URLs for all attached note images
    var noteImageURLs: [URL] {
        (noteImageNames ?? []).map { Self.notesImageDirectory.appendingPathComponent($0) }
    }

    var hasTranscript: Bool { transcriptFullText != nil }
    var hasSummary: Bool { summaryOneLiner != nil }

    var transcript: Transcript? {
        guard let fullText = transcriptFullText, let segs = transcriptSegments else { return nil }
        let names = speakerNames ?? [:]
        return Transcript(
            segments: segs.map {
                let displayName = names[$0.speaker] ?? $0.speaker
                return TranscriptSegment(speaker: displayName, text: $0.text, timestamp: $0.timestamp)
            },
            fullText: fullText
        )
    }

    var summary: Summary? {
        guard let oneLiner = summaryOneLiner, let context = summaryContext else { return nil }
        return Summary(
            oneLiner: oneLiner,
            actionVectors: (summaryActions ?? []).map { ActionVector(assignee: $0.assignee, task: $0.task, isCompleted: $0.isCompleted, timestamp: $0.timestamp) },
            context: context,
            sources: (summarySources ?? []).map { Source(timestamp: $0.timestamp, description: $0.description) }
        )
    }

    /// Unique raw speaker IDs from transcript segments (for renaming UI)
    /// Filters out empty speaker strings (e.g. from on-device transcription)
    var uniqueSpeakers: [String] {
        guard let segs = transcriptSegments else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for seg in segs {
            let speaker = seg.speaker.trimmingCharacters(in: .whitespaces)
            if !speaker.isEmpty && !seen.contains(seg.speaker) {
                seen.insert(seg.speaker)
                result.append(seg.speaker)
            }
        }
        return result
    }

    /// Display name for a raw speaker ID
    func displayName(for speaker: String) -> String {
        speakerNames?[speaker] ?? speaker
    }

    /// Update a segment's text at the given index
    func updateSegmentText(at index: Int, newText: String) {
        guard var segments = transcriptSegments, index >= 0, index < segments.count else { return }
        segments[index].text = newText
        transcriptSegments = segments
        // Also update the full text
        transcriptFullText = segments.map { $0.text }.joined(separator: " ")
    }

    /// Get the index of the segment that contains the given timestamp
    func segmentIndex(at time: TimeInterval) -> Int? {
        guard let segments = transcriptSegments, !segments.isEmpty else { return nil }
        
        // Find the segment where time falls between this segment's start and the next segment's start
        for i in 0..<segments.count {
            let segmentStart = segments[i].timestamp
            let segmentEnd: TimeInterval
            
            if i + 1 < segments.count {
                segmentEnd = segments[i + 1].timestamp
            } else {
                // Last segment - extends to end of recording
                segmentEnd = duration
            }
            
            if time >= segmentStart && time < segmentEnd {
                return i
            }
        }
        
        // If past all segments, return last one
        if time >= (segments.last?.timestamp ?? 0) {
            return segments.count - 1
        }
        
        return nil
    }

    var statusLabel: String {
        if isTranscribing { return "TRANSCRIBING" }
        if isSummarizing { return "SUMMARIZING" }
        if hasSummary { return "DECODED" }
        if hasTranscript { return "TRANSCRIBED" }
        return "RAW"
    }

    var formattedDuration: String {
        let mins = Int(duration) / 60
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins)m"
    }
}

// MARK: - Codable data for SwiftData storage

struct SegmentData: Codable, Equatable {
    var speaker: String
    var text: String
    var timestamp: TimeInterval
}

struct ActionData: Codable {
    let assignee: String
    let task: String
    var isCompleted: Bool
    let timestamp: TimeInterval?
}

struct SourceData: Codable {
    let timestamp: TimeInterval
    let description: String
}

// MARK: - View-layer types (not persisted)

struct Transcript {
    let segments: [TranscriptSegment]
    let fullText: String
}

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let speaker: String
    let text: String
    let timestamp: TimeInterval
}

struct Summary {
    let oneLiner: String
    let actionVectors: [ActionVector]
    let context: String
    let sources: [Source]
}

struct ActionVector: Identifiable {
    let id = UUID()
    let assignee: String
    let task: String
    var isCompleted: Bool
    let timestamp: TimeInterval?

    init(assignee: String, task: String, isCompleted: Bool = false, timestamp: TimeInterval? = nil) {
        self.assignee = assignee
        self.task = task
        self.isCompleted = isCompleted
        self.timestamp = timestamp
    }
}

struct Source: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let description: String
}
