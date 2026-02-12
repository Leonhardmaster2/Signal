import Foundation
import Speech
import AVFoundation
import BackgroundTasks
import UIKit

// MARK: - On-Device Transcription Errors

enum OnDeviceTranscriptionError: LocalizedError, Equatable {
    case notAuthorized
    case notAvailable
    case onDeviceNotSupported
    case languageNotSupported(String)
    case recognitionFailed(String)
    case fileNotFound
    case audioProcessingFailed
    case cancelled
    case backgroundTaskFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable in Settings."
        case .notAvailable:
            return "Speech recognition is not available."
        case .onDeviceNotSupported:
            return "On-device speech recognition is not supported for this language."
        case .languageNotSupported(let lang):
            return "Language '\(lang)' is not supported for speech recognition."
        case .recognitionFailed(let message):
            return "Recognition failed: \(message)"
        case .fileNotFound:
            return "Audio file not found."
        case .audioProcessingFailed:
            return "Failed to process audio file."
        case .cancelled:
            return "Transcription was cancelled."
        case .backgroundTaskFailed:
            return "Background transcription was interrupted by the system."
        }
    }
}

// MARK: - On-Device Transcription Service

final class OnDeviceTranscriptionService {
    static let shared = OnDeviceTranscriptionService()

    /// The speech recognizer - can be recreated with different locales
    private var speechRecognizer: SFSpeechRecognizer?
    
    /// Current locale being used for recognition
    private var currentLocale: Locale

    /// The active recognition task, used for cancellation
    private var activeTask: SFSpeechRecognitionTask?

    /// Flag to indicate user-requested cancellation
    private var isCancelled = false

    /// Whether a transcription is currently in progress
    var isTranscribing: Bool { activeTask != nil }

    /// Maximum chunk duration in seconds — Apple caps recognition at ~60s
    private let maxChunkDuration: TimeInterval = 55.0

    /// Overlap between chunks to avoid cutting words mid-sentence
    private let chunkOverlap: TimeInterval = 2.0
    
    /// Background task identifier for continued processing
    static let backgroundTaskIdentifier = "com.signal.transcription"
    
    /// Current background task (for iOS 18+ BGContinuedProcessingTask)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    /// Progress object for background task reporting
    private var transcriptionProgress: Progress?

    private init() {
        currentLocale = Locale.current
        speechRecognizer = SFSpeechRecognizer(locale: currentLocale)
    }

    /// Check if on-device recognition is available for current locale
    var isOnDeviceAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }
    
    /// Check if on-device recognition is available for the user's preferred language (from settings)
    var isOnDeviceAvailableForPreferredLanguage: Bool {
        let preferredLanguage = UserDefaults.standard.string(forKey: "preferredTranscriptionLanguage") 
            ?? Locale.current.language.languageCode?.identifier 
            ?? "en"
        return isOnDeviceAvailable(forLanguage: preferredLanguage)
    }
    
    /// Check if on-device recognition is available for a specific language code
    func isOnDeviceAvailable(forLanguage languageCode: String) -> Bool {
        // Find a locale that matches this language code
        guard let locale = Self.supportedLocales.first(where: {
            $0.language.languageCode?.identifier == languageCode
        }) else { return false }
        
        return isOnDeviceAvailable(for: locale)
    }
    
    /// Check if on-device recognition is available for a specific locale
    func isOnDeviceAvailable(for locale: Locale) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
    }
    
    // MARK: - Supported Languages
    
    /// Get all supported locales for speech recognition
    static var supportedLocales: Set<Locale> {
        SFSpeechRecognizer.supportedLocales()
    }
    
    /// Check if a specific language code is supported (e.g., "de", "en", "fr")
    static func isLanguageSupported(_ languageCode: String) -> Bool {
        supportedLocales.contains { locale in
            locale.language.languageCode?.identifier == languageCode
        }
    }
    
    /// Get locales that support on-device recognition
    static var onDeviceSupportedLocales: [Locale] {
        supportedLocales.filter { locale in
            guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
            return recognizer.supportsOnDeviceRecognition
        }
    }
    
    /// Common language display names for UI
    static let commonLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("ru", "Russian"),
        ("ar", "Arabic"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("no", "Norwegian"),
        ("fi", "Finnish")
    ]
    
    /// Set the locale for speech recognition
    func setLocale(_ locale: Locale) {
        guard locale != currentLocale else { return }
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: locale)
    }
    
    /// Set the locale by language code (e.g., "de" for German)
    func setLanguage(_ languageCode: String) {
        // Find the best matching locale for this language
        let matchingLocales = Self.supportedLocales.filter {
            $0.language.languageCode?.identifier == languageCode
        }
        
        // Prefer the user's region variant if available, otherwise use first match
        let userRegion = Locale.current.region?.identifier
        let bestMatch = matchingLocales.first { locale in
            locale.region?.identifier == userRegion
        } ?? matchingLocales.first
        
        if let locale = bestMatch {
            setLocale(locale)
        }
    }
    
    /// Get the current language code
    var currentLanguageCode: String {
        currentLocale.language.languageCode?.identifier ?? "en"
    }

    /// Request speech recognition authorization
    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Cancel the current transcription task
    func cancelTranscription() {
        isCancelled = true
        activeTask?.cancel()
        activeTask = nil
        endBackgroundTask()
    }
    
    // MARK: - Background Task Management
    
    /// Begin a background task to allow transcription to continue when app is backgrounded
    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else { return }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "TranscriptionTask") { [weak self] in
            // Expiration handler - system is about to suspend us
            // Don't cancel the task, just end the background task identifier
            // The transcription will pause and resume when app comes back
            self?.endBackgroundTask()
        }
    }
    
    /// End the background task
    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    // MARK: - Public Transcription Entry Point

    /// Transcribe an audio file using on-device recognition
    /// Automatically chunks long audio files to work around Apple's ~60s limit
    /// Supports background execution - transcription continues even when app is backgrounded
    func transcribe(fileURL: URL, progressHandler: ((String) -> Void)? = nil, progressFraction: ((Double) -> Void)? = nil) async throws -> ScribeResponse {
        print("📱 [OnDeviceTranscription] transcribe() called")
        print("📱 [OnDeviceTranscription] File URL: \(fileURL.path)")
        
        // Reset cancellation flag
        isCancelled = false

        // Cancel any existing task first
        activeTask?.cancel()
        activeTask = nil
        
        // Begin background task to ensure transcription continues in background
        beginBackgroundTask()
        
        // Setup progress tracking
        transcriptionProgress = Progress(totalUnitCount: 100)

        // Check authorization
        let status = await requestAuthorization()
        print("📱 [OnDeviceTranscription] Authorization status: \(status.rawValue)")
        guard status == .authorized else {
            endBackgroundTask()
            throw OnDeviceTranscriptionError.notAuthorized
        }

        // Check recognizer availability
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ [OnDeviceTranscription] Recognizer not available")
            endBackgroundTask()
            throw OnDeviceTranscriptionError.notAvailable
        }
        print("📱 [OnDeviceTranscription] Recognizer available: \(recognizer.locale.identifier)")

        // Check on-device support
        guard recognizer.supportsOnDeviceRecognition else {
            print("❌ [OnDeviceTranscription] On-device not supported for locale")
            endBackgroundTask()
            throw OnDeviceTranscriptionError.onDeviceNotSupported
        }
        print("📱 [OnDeviceTranscription] On-device supported: ✅")

        // Check file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("❌ [OnDeviceTranscription] File not found")
            endBackgroundTask()
            throw OnDeviceTranscriptionError.fileNotFound
        }

        // Get audio duration
        let asset = AVURLAsset(url: fileURL)
        let audioDuration: Double
        if let dur = try? await asset.load(.duration) {
            audioDuration = dur.seconds
        } else {
            audioDuration = 0
        }
        print("📱 [OnDeviceTranscription] Audio duration: \(audioDuration)s")
        
        do {
            let result: ScribeResponse
            
            // If short enough, transcribe directly (no chunking needed)
            if audioDuration > 0 && audioDuration <= maxChunkDuration {
                print("📱 [OnDeviceTranscription] Audio ≤ \(maxChunkDuration)s, using single chunk")
                result = try await transcribeSingleChunk(
                    fileURL: fileURL,
                    recognizer: recognizer,
                    timeOffset: 0,
                    audioDuration: audioDuration,
                    progressHandler: progressHandler,
                    progressFraction: { [weak self] fraction in
                        self?.transcriptionProgress?.completedUnitCount = Int64(fraction * 100)
                        progressFraction?(fraction)
                    }
                )
            } else {
                // For longer files, chunk and transcribe sequentially
                print("📱 [OnDeviceTranscription] Audio > \(maxChunkDuration)s (\(audioDuration)s), using chunked transcription")
                result = try await transcribeChunked(
                    fileURL: fileURL,
                    recognizer: recognizer,
                    audioDuration: audioDuration,
                    progressHandler: progressHandler,
                    progressFraction: { [weak self] fraction in
                        self?.transcriptionProgress?.completedUnitCount = Int64(fraction * 100)
                        progressFraction?(fraction)
                    }
                )
            }
            
            print("✅ [OnDeviceTranscription] Transcription complete!")
            print("📊 [OnDeviceTranscription] Text length: \(result.text.count) characters")
            print("📊 [OnDeviceTranscription] Word count: \(result.words?.count ?? 0) words")
            print("📊 [OnDeviceTranscription] First 200 chars: \(String(result.text.prefix(200)))")
            
            endBackgroundTask()
            return result
        } catch {
            print("❌ [OnDeviceTranscription] Error: \(error)")
            endBackgroundTask()
            throw error
        }
    }
    
    /// Transcribe with automatic language detection
    /// First detects the language, then transcribes in that language
    func transcribeWithLanguageDetection(fileURL: URL, preferredLanguages: [String]? = nil, progressHandler: ((String) -> Void)? = nil, progressFraction: ((Double) -> Void)? = nil) async throws -> ScribeResponse {
        // Begin background task
        beginBackgroundTask()
        
        do {
            // Detect language from first few seconds of audio
            let detectedLanguage = try await detectLanguage(fileURL: fileURL, preferredLanguages: preferredLanguages)
            
            // Set the recognizer to use detected language
            setLanguage(detectedLanguage)
            
            // Transcribe with the detected language
            let result = try await transcribe(fileURL: fileURL, progressHandler: progressHandler, progressFraction: progressFraction)
            
            // Return result with detected language code
            return ScribeResponse(
                language_code: detectedLanguage,
                language_probability: result.language_probability,
                text: result.text,
                words: result.words
            )
        } catch {
            endBackgroundTask()
            throw error
        }
    }
    
    /// Detect the language of an audio file by transcribing a short sample
    private func detectLanguage(fileURL: URL, preferredLanguages: [String]? = nil) async throws -> String {
        // Languages to try for detection (user's preferred + common languages)
        var languagesToTry = preferredLanguages ?? []
        
        // Add device language if not already included
        let deviceLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        if !languagesToTry.contains(deviceLanguage) {
            languagesToTry.insert(deviceLanguage, at: 0)
        }
        
        // Add common languages
        let commonCodes = ["en", "de", "fr", "es", "it", "pt", "zh", "ja"]
        for code in commonCodes where !languagesToTry.contains(code) {
            languagesToTry.append(code)
        }
        
        // Filter to only supported languages with on-device support
        languagesToTry = languagesToTry.filter { code in
            Self.supportedLocales.contains { locale in
                guard locale.language.languageCode?.identifier == code else { return false }
                if let recognizer = SFSpeechRecognizer(locale: locale) {
                    return recognizer.supportsOnDeviceRecognition
                }
                return false
            }
        }
        
        // Extract a short sample (first 10 seconds) for language detection
        let sampleURL = FileManager.default.temporaryDirectory.appendingPathComponent("lang_detect_\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        
        let asset = AVURLAsset(url: fileURL)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let sampleDuration = min(10.0, duration)
        
        if sampleDuration > 0 {
            try await exportAudioChunk(from: fileURL, to: sampleURL, startTime: 0, endTime: sampleDuration)
        }
        
        let testURL = sampleDuration > 0 ? sampleURL : fileURL
        
        // Try each language and see which gives the best confidence
        var bestLanguage = deviceLanguage
        var bestConfidence: Float = 0
        
        for languageCode in languagesToTry.prefix(5) { // Limit to 5 languages for speed
            guard !isCancelled else { throw OnDeviceTranscriptionError.cancelled }
            
            // Find locale for this language
            guard let locale = Self.supportedLocales.first(where: {
                $0.language.languageCode?.identifier == languageCode
            }) else { continue }
            
            guard let recognizer = SFSpeechRecognizer(locale: locale),
                  recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else { continue }
            
            // Try to transcribe and get confidence
            do {
                let request = SFSpeechURLRecognitionRequest(url: testURL)
                request.requiresOnDeviceRecognition = true
                request.shouldReportPartialResults = false
                
                let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult?, Error>) in
                    var hasResumed = false
                    let task = recognizer.recognitionTask(with: request) { result, error in
                        guard !hasResumed else { return }
                        if let error = error {
                            hasResumed = true
                            continuation.resume(throwing: error)
                        } else if let result = result, result.isFinal {
                            hasResumed = true
                            continuation.resume(returning: result)
                        }
                    }
                    
                    // Timeout after 5 seconds
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        if !hasResumed {
                            hasResumed = true
                            task.cancel()
                            continuation.resume(returning: nil)
                        }
                    }
                }
                
                if let result = result {
                    let confidence = result.bestTranscription.segments.map { $0.confidence }.reduce(0, +) / Float(max(1, result.bestTranscription.segments.count))
                    
                    if confidence > bestConfidence {
                        bestConfidence = confidence
                        bestLanguage = languageCode
                    }
                }
            } catch {
                // Continue to next language
                continue
            }
        }
        
        return bestLanguage
    }

    // MARK: - Chunked Transcription

    /// Split long audio into chunks and transcribe each sequentially
    private func transcribeChunked(
        fileURL: URL,
        recognizer: SFSpeechRecognizer,
        audioDuration: Double,
        progressHandler: ((String) -> Void)?,
        progressFraction: ((Double) -> Void)?
    ) async throws -> ScribeResponse {
        guard audioDuration > 0 else {
            throw OnDeviceTranscriptionError.audioProcessingFailed
        }

        // Calculate chunk boundaries
        var chunks: [(start: TimeInterval, end: TimeInterval)] = []
        var currentStart: TimeInterval = 0
        while currentStart < audioDuration {
            let chunkEnd = min(currentStart + maxChunkDuration, audioDuration)
            chunks.append((start: currentStart, end: chunkEnd))
            // Advance by (maxChunkDuration - overlap) to create overlap
            currentStart += maxChunkDuration - chunkOverlap
            if currentStart >= audioDuration { break }
        }
        
        print("🔪 [Chunking] Total chunks: \(chunks.count)")
        for (i, chunk) in chunks.enumerated() {
            print("🔪 [Chunking] Chunk \(i): \(chunk.start)s - \(chunk.end)s (\(chunk.end - chunk.start)s)")
        }

        // Create temp directory for chunk files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("signal_chunks_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        var allWords: [ScribeWord] = []
        var allText = ""
        var languageCode: String?
        var languageProb: Double?

        for (index, chunk) in chunks.enumerated() {
            print("🔄 [Chunk \(index+1)/\(chunks.count)] Processing \(chunk.start)s - \(chunk.end)s")
            
            // Check cancellation
            guard !isCancelled else {
                print("❌ [Chunk \(index+1)/\(chunks.count)] Cancelled")
                throw OnDeviceTranscriptionError.cancelled
            }

            // Export this chunk to a temporary file
            let chunkURL = tempDir.appendingPathComponent("chunk_\(index).m4a")
            print("📝 [Chunk \(index+1)/\(chunks.count)] Exporting audio chunk...")
            try await exportAudioChunk(from: fileURL, to: chunkURL, startTime: chunk.start, endTime: chunk.end)
            print("✅ [Chunk \(index+1)/\(chunks.count)] Audio chunk exported")

            // Check cancellation after export
            guard !isCancelled else {
                print("❌ [Chunk \(index+1)/\(chunks.count)] Cancelled after export")
                throw OnDeviceTranscriptionError.cancelled
            }

            // Transcribe this chunk
            let chunkDuration = chunk.end - chunk.start
            print("🎤 [Chunk \(index+1)/\(chunks.count)] Starting transcription...")
            let chunkResponse = try await transcribeSingleChunk(
                fileURL: chunkURL,
                recognizer: recognizer,
                timeOffset: chunk.start,
                audioDuration: chunkDuration,
                progressHandler: { partialText in
                    // Show accumulated text + partial for this chunk
                    let combined = allText.isEmpty ? partialText : allText + " " + partialText
                    progressHandler?(combined)
                },
                progressFraction: { chunkFraction in
                    // Calculate overall progress
                    let chunkWeight = chunkDuration / audioDuration
                    let chunkBase = chunk.start / audioDuration
                    let overall = chunkBase + (chunkFraction * chunkWeight)
                    progressFraction?(min(1.0, overall))
                }
            )
            print("✅ [Chunk \(index+1)/\(chunks.count)] Transcribed: \(chunkResponse.text.count) chars, \(chunkResponse.words?.count ?? 0) words")

            // Merge results — offset word timestamps by chunk start time
            if let words = chunkResponse.words {
                // Adjust timestamps to be relative to the full audio
                let adjustedWords = words.map { word in
                    ScribeWord(
                        text: word.text,
                        start: word.start + chunk.start,
                        end: word.end + chunk.start,
                        type: word.type,
                        speaker_id: nil
                    )
                }

                // If there's overlap with previous chunk, deduplicate
                if index > 0 && !allWords.isEmpty && !adjustedWords.isEmpty {
                    let overlapWords = deduplicateOverlap(existing: allWords, incoming: adjustedWords, overlapStart: chunk.start)
                    print("🔀 [Chunk \(index+1)/\(chunks.count)] Deduplicated overlap: \(allWords.count) + \(adjustedWords.count) → \(overlapWords.count) words")
                    allWords = overlapWords
                } else {
                    print("➕ [Chunk \(index+1)/\(chunks.count)] Adding \(adjustedWords.count) words")
                    allWords.append(contentsOf: adjustedWords)
                }
            }

            // Build full text from all words so far
            allText = allWords.map { $0.text }.joined().trimmingCharacters(in: .whitespaces)
            print("📊 [Chunk \(index+1)/\(chunks.count)] Total so far: \(allText.count) chars, \(allWords.count) words")

            if languageCode == nil { languageCode = chunkResponse.language_code }
            if languageProb == nil { languageProb = chunkResponse.language_probability }

            // Clean up chunk file
            try? FileManager.default.removeItem(at: chunkURL)
        }

        progressFraction?(1.0)

        return ScribeResponse(
            language_code: languageCode,
            language_probability: languageProb,
            text: allText,
            words: allWords
        )
    }

    // MARK: - Single Chunk Transcription

    /// Transcribe a single audio file/chunk using SFSpeechRecognizer
    private func transcribeSingleChunk(
        fileURL: URL,
        recognizer: SFSpeechRecognizer,
        timeOffset: TimeInterval,
        audioDuration: Double,
        progressHandler: ((String) -> Void)?,
        progressFraction: ((Double) -> Void)?
    ) async throws -> ScribeResponse {
        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            var words: [ScribeWord] = []
            var hasResumed = false
            var lastResult: SFSpeechRecognitionResult?
            var bestResult: SFSpeechRecognitionResult? // Track the longest result we've seen
            var maxSegmentCount = 0
            
            // Timeout mechanism: if we don't get isFinal within reasonable time, use last result
            // This works around a bug where some audio files never get marked as final
            let timeoutDuration = max(audioDuration + 5.0, 70.0) // Audio duration + 5s buffer, minimum 70s
            print("⏱️ [SingleChunk] Timeout set to \(timeoutDuration)s")
            
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeoutDuration))
                guard !hasResumed else { return }
                
                print("⏱️ [SingleChunk] TIMEOUT reached! Using last result")
                
                // If we have partial results but never got isFinal, use the best result we saw
                // Prefer bestResult (longest) over lastResult if available
                let resultToUse = bestResult ?? lastResult
                if let result = resultToUse {
                    hasResumed = true
                    self.activeTask?.cancel()
                    self.activeTask = nil
                    
                    print("⏱️ [SingleChunk] Using \(bestResult != nil ? "best" : "last") result with \(result.bestTranscription.segments.count) segments (max seen: \(maxSegmentCount))")
                    
                    var finalWords: [ScribeWord] = []
                    for segment in result.bestTranscription.segments {
                        let word = ScribeWord(
                            text: segment.substring + " ",
                            start: segment.timestamp,
                            end: segment.timestamp + segment.duration,
                            type: "word",
                            speaker_id: nil
                        )
                        finalWords.append(word)
                    }
                    
                    let response = ScribeResponse(
                        language_code: Locale.current.language.languageCode?.identifier,
                        language_probability: Double(result.bestTranscription.segments.first?.confidence ?? 0),
                        text: result.bestTranscription.formattedString,
                        words: finalWords
                    )
                    
                    print("⏱️ [SingleChunk] Returning \(response.text.count) chars via timeout")
                    continuation.resume(returning: response)
                } else {
                    print("❌ [SingleChunk] Timeout but no result available!")
                }
            }

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                guard !hasResumed else { return }

                if let error = error {
                    hasResumed = true
                    timeoutTask.cancel()
                    self.activeTask = nil
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        continuation.resume(throwing: OnDeviceTranscriptionError.cancelled)
                    } else if self.isCancelled {
                        continuation.resume(throwing: OnDeviceTranscriptionError.cancelled)
                    } else {
                        continuation.resume(throwing: OnDeviceTranscriptionError.recognitionFailed(error.localizedDescription))
                    }
                    return
                }

                if let result = result {
                    // Store the latest result for timeout fallback
                    lastResult = result
                    
                    // Track the best (longest) result we've seen
                    let segmentCount = result.bestTranscription.segments.count
                    if segmentCount > maxSegmentCount {
                        maxSegmentCount = segmentCount
                        bestResult = result
                        print("🔝 [SingleChunk] New best result: \(segmentCount) segments")
                    }
                    
                    progressHandler?(result.bestTranscription.formattedString)

                    if audioDuration > 0, let lastSegment = result.bestTranscription.segments.last {
                        let fraction = min(1.0, lastSegment.timestamp / audioDuration)
                        progressFraction?(fraction)
                    }

                    if result.isFinal {
                        print("✅ [SingleChunk] Got isFinal! Current result: \(result.bestTranscription.segments.count) segments")
                        hasResumed = true
                        timeoutTask.cancel()
                        self.activeTask = nil

                        // Use the best result we've seen, not the potentially incomplete final result
                        let resultToUse = bestResult ?? result
                        print("🎯 [SingleChunk] Using result with \(resultToUse.bestTranscription.segments.count) segments (best: \(maxSegmentCount))")

                        for segment in resultToUse.bestTranscription.segments {
                            let word = ScribeWord(
                                text: segment.substring + " ",
                                start: segment.timestamp,
                                end: segment.timestamp + segment.duration,
                                type: "word",
                                speaker_id: nil
                            )
                            words.append(word)
                        }

                        let response = ScribeResponse(
                            language_code: Locale.current.language.languageCode?.identifier,
                            language_probability: Double(resultToUse.bestTranscription.segments.first?.confidence ?? 0),
                            text: resultToUse.bestTranscription.formattedString,
                            words: words
                        )

                        print("✅ [SingleChunk] Returning \(response.text.count) chars via isFinal")
                        continuation.resume(returning: response)
                    } else {
                        print("⏳ [SingleChunk] Partial result: \(result.bestTranscription.segments.count) segments so far")
                    }
                }
            }

            self.activeTask = task
        }
    }

    // MARK: - Audio Chunk Export

    /// Export a time range from an audio file to a new file
    private func exportAudioChunk(from sourceURL: URL, to destinationURL: URL, startTime: TimeInterval, endTime: TimeInterval) async throws {
        let asset = AVURLAsset(url: sourceURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw OnDeviceTranscriptionError.audioProcessingFailed
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .m4a

        let start = CMTime(seconds: startTime, preferredTimescale: 44100)
        let end = CMTime(seconds: endTime, preferredTimescale: 44100)
        exportSession.timeRange = CMTimeRange(start: start, end: end)

        await exportSession.export()

        guard exportSession.status == .completed else {
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown export error"
            throw OnDeviceTranscriptionError.recognitionFailed("Audio chunk export failed: \(errorMsg)")
        }
    }

    // MARK: - Overlap Deduplication

    /// Remove duplicate words from the overlap region between chunks
    private func deduplicateOverlap(existing: [ScribeWord], incoming: [ScribeWord], overlapStart: TimeInterval) -> [ScribeWord] {
        // Keep all existing words that are before the overlap region
        // For words in the overlap, prefer the incoming chunk (it may have better context)
        let overlapThreshold = overlapStart + 0.5 // Small buffer to avoid edge issues

        // Find where existing words end before overlap
        var trimmedExisting = existing
        while let last = trimmedExisting.last, last.start >= overlapThreshold {
            trimmedExisting.removeLast()
        }

        // Find where incoming words start after overlap begins
        let newWords = incoming.filter { $0.start >= overlapThreshold - 0.5 }

        // If we have a gap, keep all existing and add non-overlapping incoming
        if trimmedExisting.isEmpty {
            return incoming
        }

        guard let lastExistingEnd = trimmedExisting.last?.end else {
            return incoming
        }

        // Add incoming words that start after the last existing word ends
        let filteredIncoming = newWords.filter { $0.start >= lastExistingEnd - 0.3 }
        return trimmedExisting + filteredIncoming
    }

    // MARK: - Build Transcript

    /// Build transcript from response — no speaker attribution for on-device
    func buildTranscript(from response: ScribeResponse) -> Transcript {
        // On-device transcription does not provide speaker diarization
        // Return a single segment with the full text and no speaker label
        let segments = [
            TranscriptSegment(
                speaker: "",
                text: response.text,
                timestamp: 0
            )
        ]

        return Transcript(
            segments: segments,
            fullText: response.text
        )
    }
}
