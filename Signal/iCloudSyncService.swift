// iCloudSyncService.swift
// Manages iCloud Drive backup and restoration of recordings

import Foundation
import Observation
import SwiftData

// MARK: - Manifest (Codable mirror of Recording metadata)

struct RecordingManifest: Codable {
    let version: String
    let uid: String
    let title: String
    let date: TimeInterval          // seconds since 1970
    let duration: TimeInterval
    let isStarred: Bool
    let isArchived: Bool
    let marks: [TimeInterval]
    let audioFileName: String
    let transcriptFullText: String?
    let transcriptLanguage: String?
    let transcriptSegments: [ManifestSegment]?
    let summaryOneLiner: String?
    let summaryContext: String?
    let summaryActions: [ManifestAction]?
    let notes: String?
    let noteImageNames: [String]?
    let speakerNames: [String: String]?
    let wasTranscribedOnDevice: Bool?
    let wasSummarizedOnDevice: Bool?

    struct ManifestSegment: Codable {
        let speaker: String
        let text: String
        let timestamp: TimeInterval
    }

    struct ManifestAction: Codable {
        let assignee: String
        let task: String
        let isCompleted: Bool
        let timestamp: TimeInterval?
    }
}

// MARK: - iCloudSyncService

@Observable
final class iCloudSyncService {
    static let shared = iCloudSyncService()

    // Sync state
    private(set) var isSyncing = false
    private(set) var isRestoring = false
    private(set) var syncProgress: Double = 0.0
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    // iCloud container (resolved on background thread)
    private var ubiquityContainer: URL?

    init() {
        resolveContainer()
        if let ts = UserDefaults.standard.object(forKey: "lastICloudSyncDate") as? TimeInterval {
            lastSyncDate = Date(timeIntervalSince1970: ts)
        }
    }

    /// Whether iCloud Drive is available and user is signed in
    var isAvailable: Bool {
        ubiquityContainer != nil && AppleSignInService.shared.isSignedIn
    }

    // MARK: - Container Resolution

    private func resolveContainer() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let url = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.Proceduralabs.Signal")
            DispatchQueue.main.async {
                self?.ubiquityContainer = url
                if let url {
                    print("\u{2705} iCloud container: \(url.path)")
                } else {
                    print("\u{274C} iCloud container not available")
                }
            }
        }
    }

    // MARK: - Directories

    private var iCloudRecordingsDir: URL? {
        guard let container = ubiquityContainer else { return nil }
        let dir = container.appendingPathComponent("Documents/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var iCloudImagesDir: URL? {
        guard let container = ubiquityContainer else { return nil }
        let dir = container.appendingPathComponent("Documents/NoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var localRecordingsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Backup Single Recording

    func backupRecording(_ recording: Recording) async throws {
        guard let cloudDir = iCloudRecordingsDir else { return }

        // 1. Copy audio file
        if let audioURL = recording.audioURL,
           FileManager.default.fileExists(atPath: audioURL.path) {
            let dest = cloudDir.appendingPathComponent(audioURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.copyItem(at: audioURL, to: dest)
            } else {
                // Replace if local is newer
                let localAttr = try FileManager.default.attributesOfItem(atPath: audioURL.path)
                let cloudAttr = try FileManager.default.attributesOfItem(atPath: dest.path)
                if let localDate = localAttr[.modificationDate] as? Date,
                   let cloudDate = cloudAttr[.modificationDate] as? Date,
                   localDate > cloudDate {
                    try FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: audioURL, to: dest)
                }
            }
        }

        // 2. Copy note images
        if let imageNames = recording.noteImageNames, let imagesDir = iCloudImagesDir {
            for name in imageNames {
                let src = Recording.notesImageDirectory.appendingPathComponent(name)
                let dst = imagesDir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src.path),
                   !FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }

        // 3. Write JSON manifest
        let manifest = buildManifest(from: recording)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)

        let jsonName = (recording.audioFileName ?? recording.uid.uuidString)
            .replacingOccurrences(of: ".m4a", with: ".json")
        let jsonURL = cloudDir.appendingPathComponent(jsonName)
        try data.write(to: jsonURL, options: .atomic)
    }

    // MARK: - Backup All

    @MainActor
    func backupAllRecordings(modelContext: ModelContext) async throws {
        guard isAvailable else { return }

        isSyncing = true
        syncProgress = 0.0
        lastError = nil
        defer {
            isSyncing = false
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate!.timeIntervalSince1970, forKey: "lastICloudSyncDate")
        }

        let recordings = try modelContext.fetch(FetchDescriptor<Recording>())
        let total = max(Double(recordings.count), 1)

        for (i, recording) in recordings.enumerated() {
            do {
                try await backupRecording(recording)
            } catch {
                print("\u{26A0}\u{FE0F} Backup failed for \(recording.title): \(error)")
                lastError = error.localizedDescription
            }
            syncProgress = Double(i + 1) / total
        }
    }

    // MARK: - Restore from iCloud

    @MainActor
    func restoreFromiCloud(modelContext: ModelContext) async throws {
        guard let cloudDir = iCloudRecordingsDir else { return }

        isRestoring = true
        syncProgress = 0.0
        lastError = nil
        defer { isRestoring = false }

        // Scan for JSON manifests
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cloudDir, includingPropertiesForKeys: nil
        )) ?? []
        let manifests = files.filter { $0.pathExtension == "json" }
        let total = max(Double(manifests.count), 1)

        var restoredCount = 0

        for (i, url) in manifests.enumerated() {
            do {
                let restored = try await restoreRecording(from: url, cloudDir: cloudDir, modelContext: modelContext)
                if restored { restoredCount += 1 }
            } catch {
                print("\u{274C} Restore failed for \(url.lastPathComponent): \(error)")
            }
            syncProgress = Double(i + 1) / total
        }

        if restoredCount > 0 {
            try modelContext.save()
        }
        print("\u{2705} Restored \(restoredCount) recordings from iCloud")
    }

    // MARK: - Private Helpers

    private func restoreRecording(from manifestURL: URL, cloudDir: URL, modelContext: ModelContext) async throws -> Bool {
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(RecordingManifest.self, from: data)

        // Skip if already exists
        guard let uid = UUID(uuidString: manifest.uid) else { return false }
        let descriptor = FetchDescriptor<Recording>(predicate: #Predicate { $0.uid == uid })
        if let _ = try? modelContext.fetch(descriptor).first { return false }

        // Create Recording
        let recording = Recording(
            title: manifest.title,
            date: Date(timeIntervalSince1970: manifest.date),
            duration: manifest.duration,
            audioFileName: manifest.audioFileName
        )
        // Overwrite auto-generated UID with the original
        recording.uid = uid
        recording.isStarred = manifest.isStarred
        recording.isArchived = manifest.isArchived
        recording.marks = manifest.marks
        recording.transcriptFullText = manifest.transcriptFullText
        recording.transcriptLanguage = manifest.transcriptLanguage
        recording.summaryOneLiner = manifest.summaryOneLiner
        recording.summaryContext = manifest.summaryContext
        recording.notes = manifest.notes
        recording.noteImageNames = manifest.noteImageNames
        recording.speakerNames = manifest.speakerNames
        recording.wasTranscribedOnDevice = manifest.wasTranscribedOnDevice
        recording.wasSummarizedOnDevice = manifest.wasSummarizedOnDevice

        // Restore segments
        recording.transcriptSegments = manifest.transcriptSegments?.map {
            SegmentData(speaker: $0.speaker, text: $0.text, timestamp: $0.timestamp)
        }

        // Restore actions
        recording.summaryActions = manifest.summaryActions?.map {
            ActionData(assignee: $0.assignee, task: $0.task, isCompleted: $0.isCompleted, timestamp: $0.timestamp)
        }

        // Copy audio from iCloud to local
        let cloudAudio = cloudDir.appendingPathComponent(manifest.audioFileName)
        let localAudio = localRecordingsDir.appendingPathComponent(manifest.audioFileName)
        if FileManager.default.fileExists(atPath: cloudAudio.path),
           !FileManager.default.fileExists(atPath: localAudio.path) {
            try FileManager.default.copyItem(at: cloudAudio, to: localAudio)
        }

        // Copy note images from iCloud to local
        if let imageNames = manifest.noteImageNames, let imagesDir = iCloudImagesDir {
            let localImagesDir = Recording.notesImageDirectory
            for name in imageNames {
                let src = imagesDir.appendingPathComponent(name)
                let dst = localImagesDir.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: src.path),
                   !FileManager.default.fileExists(atPath: dst.path) {
                    try? FileManager.default.copyItem(at: src, to: dst)
                }
            }
        }

        modelContext.insert(recording)
        return true
    }

    private func buildManifest(from r: Recording) -> RecordingManifest {
        RecordingManifest(
            version: "1.0",
            uid: r.uid.uuidString,
            title: r.title,
            date: r.date.timeIntervalSince1970,
            duration: r.duration,
            isStarred: r.isStarred,
            isArchived: r.isArchived,
            marks: r.marks,
            audioFileName: r.audioFileName ?? "",
            transcriptFullText: r.transcriptFullText,
            transcriptLanguage: r.transcriptLanguage,
            transcriptSegments: r.transcriptSegments?.map {
                .init(speaker: $0.speaker, text: $0.text, timestamp: $0.timestamp)
            },
            summaryOneLiner: r.summaryOneLiner,
            summaryContext: r.summaryContext,
            summaryActions: r.summaryActions?.map {
                .init(assignee: $0.assignee, task: $0.task, isCompleted: $0.isCompleted, timestamp: $0.timestamp)
            },
            notes: r.notes,
            noteImageNames: r.noteImageNames,
            speakerNames: r.speakerNames,
            wasTranscribedOnDevice: r.wasTranscribedOnDevice,
            wasSummarizedOnDevice: r.wasSummarizedOnDevice
        )
    }
}
