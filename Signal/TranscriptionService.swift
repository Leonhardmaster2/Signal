import Foundation

struct ScribeResponse: Codable {
    let language_code: String?
    let language_probability: Double?
    let text: String
    let words: [ScribeWord]?
}

struct ScribeWord: Codable {
    let text: String
    let start: Double
    let end: Double
    let type: String
    let speaker_id: String?
}

enum TranscriptionError: LocalizedError, Equatable {
    case noAPIKey
    case fileNotFound
    case uploadFailed(Int, String)
    case decodingFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key found. Add your ElevenLabs key in Settings."
        case .fileNotFound: return "Audio file not found."
        case .uploadFailed(let code, let msg): return "Transcription failed (\(code)): \(msg)"
        case .decodingFailed: return "Failed to decode transcription response."
        case .cancelled: return "Transcription was cancelled."
        }
    }
}

final class TranscriptionService {
    static let shared = TranscriptionService()

    /// Active cloud URLSession task for cancellation
    private var activeURLTask: URLSessionTask?

    /// Whether a transcription is currently in progress
    var isTranscribing: Bool {
        activeURLTask != nil || OnDeviceTranscriptionService.shared.isTranscribing
    }

    /// Whether to use on-device transcription (from settings)
    var useOnDevice: Bool {
        UserDefaults.standard.bool(forKey: "useOnDeviceTranscription")
    }

    /// Check if on-device transcription is available and enabled
    var shouldUseOnDevice: Bool {
        useOnDevice && OnDeviceTranscriptionService.shared.isOnDeviceAvailable
    }

    /// Cancel any in-progress transcription (cloud or on-device)
    func cancelTranscription() {
        activeURLTask?.cancel()
        activeURLTask = nil
        OnDeviceTranscriptionService.shared.cancelTranscription()
    }

    private var apiKey: String? {
        // Check UserDefaults first (set from Settings)
        let stored = UserDefaults.standard.string(forKey: "elevenLabsAPIKey")
        if let stored, !stored.isEmpty, stored != "YOUR_API_KEY_HERE" {
            return stored
        }
        // Fall back to Secrets.plist
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["ELEVENLABS_API_KEY"] as? String,
              key != "YOUR_API_KEY_HERE"
        else { return nil }
        return key
    }

    func transcribe(fileURL: URL, diarize: Bool = true) async throws -> ScribeResponse {
        guard let apiKey else { throw TranscriptionError.noAPIKey }
        
        // Use standardized path for reliable file checking
        let standardURL = fileURL.standardizedFileURL
        let filePath = standardURL.path(percentEncoded: false)
        
        print("☁️ [Transcribe] Checking file at: \(filePath)")
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("☁️ [Transcribe] ERROR: File not found at: \(filePath)")
            throw TranscriptionError.fileNotFound
        }
        
        print("☁️ [Transcribe] File exists, preparing upload...")

        // Build the request body on a background thread since file I/O can be expensive
        let body = try await Task.detached(priority: .userInitiated) { [standardURL] in
            let boundary = UUID().uuidString
            var data = Data()

            func appendField(_ name: String, _ value: String) {
                data.append("--\(boundary)\r\n".data(using: .utf8)!)
                data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                data.append("\(value)\r\n".data(using: .utf8)!)
            }

            appendField("model_id", "scribe_v2")
            appendField("diarize", diarize ? "true" : "false")
            appendField("timestamps_granularity", "word")
            appendField("tag_audio_events", "false")

            let fileData = try Data(contentsOf: standardURL)
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(standardURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
            data.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
            data.append(fileData)
            data.append("\r\n".data(using: .utf8)!)
            data.append("--\(boundary)--\r\n".data(using: .utf8)!)

            return (data, boundary)
        }.value

        let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(body.1)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.0

        // Use delegate-based task so we can cancel it
        let (data, response): (Data, URLResponse)
        do {
            let task = URLSession.shared.dataTask(with: request)
            activeURLTask = task
            (data, response) = try await URLSession.shared.data(for: request)
            activeURLTask = nil
        } catch {
            activeURLTask = nil
            if (error as NSError).code == NSURLErrorCancelled {
                throw TranscriptionError.cancelled
            }
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.uploadFailed(0, "No HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TranscriptionError.uploadFailed(httpResponse.statusCode, errorBody)
        }

        do {
            return try JSONDecoder().decode(ScribeResponse.self, from: data)
        } catch {
            throw TranscriptionError.decodingFailed
        }
    }

    func buildTranscript(from response: ScribeResponse) -> Transcript {
        var segments: [TranscriptSegment] = []
        var currentSpeaker: String? = nil
        var currentText = ""
        var currentTimestamp: TimeInterval = 0

        for word in response.words ?? [] {
            let speaker = word.speaker_id ?? "Unknown"

            if speaker != currentSpeaker {
                if !currentText.isEmpty, let spk = currentSpeaker {
                    segments.append(TranscriptSegment(
                        speaker: formatSpeaker(spk),
                        text: currentText.trimmingCharacters(in: .whitespaces),
                        timestamp: currentTimestamp
                    ))
                }
                currentSpeaker = speaker
                currentText = word.text
                currentTimestamp = word.start
            } else {
                currentText += word.text
            }
        }

        if !currentText.isEmpty, let spk = currentSpeaker {
            segments.append(TranscriptSegment(
                speaker: formatSpeaker(spk),
                text: currentText.trimmingCharacters(in: .whitespaces),
                timestamp: currentTimestamp
            ))
        }

        return Transcript(
            segments: segments,
            fullText: response.text
        )
    }

    private func formatSpeaker(_ id: String) -> String {
        if id.hasPrefix("speaker_") {
            let letter = id.replacingOccurrences(of: "speaker_", with: "")
            if let num = Int(letter) {
                let char = Character(UnicodeScalar(65 + num)!)
                return "Speaker \(char)"
            }
        }
        return id
    }
    
    // MARK: - Unified Transcription (Routes to On-Device or Cloud)
    
    /// Result type that includes whether transcription was done on-device
    struct TranscriptionResult {
        let response: ScribeResponse
        let transcript: Transcript
        let wasOnDevice: Bool
        let detectedLanguage: String?
        let wasSilenceTrimmed: Bool
        let silenceTrimmedSeconds: TimeInterval? // How much silence was removed
    }
    
    /// Whether to use automatic language detection (from settings)
    var useAutoLanguageDetection: Bool {
        UserDefaults.standard.bool(forKey: "useAutoLanguageDetection")
    }
    
    /// Whether silence trimming is available for the current user (Standard+ only)
    /// Always enabled automatically - no user toggle needed
    var shouldUseSilenceTrimming: Bool {
        let tier = SubscriptionManager.shared.currentTier.baseLevel
        return tier == .standard || tier == .pro
    }
    
    /// Get/set the preferred transcription language
    var preferredLanguage: String {
        get {
            UserDefaults.standard.string(forKey: "preferredTranscriptionLanguage") ?? Locale.current.language.languageCode?.identifier ?? "en"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "preferredTranscriptionLanguage")
        }
    }
    
    /// Unified transcription method that automatically routes based on settings
    /// Supports background execution, automatic language detection, and silence trimming
    /// - Parameters:
    ///   - fileURL: The audio file to transcribe
    ///   - diarize: Whether to identify speakers (cloud only)
    ///   - forceOnDevice: If true, forces on-device transcription; if false, forces cloud; if nil, uses settings
    ///   - progressHandler: Callback for partial transcription text
    ///   - progressFraction: Callback for progress (0.0 to 1.0)
    func transcribeAuto(fileURL: URL, diarize: Bool = true, forceOnDevice: Bool? = nil, progressHandler: ((String) -> Void)? = nil, progressFraction: ((Double) -> Void)? = nil) async throws -> TranscriptionResult {
        let useOnDeviceForThis = forceOnDevice ?? shouldUseOnDevice
        
        print("🎯 [TranscriptionService] transcribeAuto called")
        print("🎯 [TranscriptionService] forceOnDevice: \(String(describing: forceOnDevice))")
        print("🎯 [TranscriptionService] shouldUseOnDevice: \(shouldUseOnDevice)")
        print("🎯 [TranscriptionService] useOnDeviceForThis: \(useOnDeviceForThis)")
        print("🎯 [TranscriptionService] useOnDevice setting: \(useOnDevice)")
        print("🎯 [TranscriptionService] isOnDeviceAvailable: \(OnDeviceTranscriptionService.shared.isOnDeviceAvailable)")
        print("🎯 [TranscriptionService] shouldUseSilenceTrimming: \(shouldUseSilenceTrimming)")
        
        // Apply silence trimming for cloud transcription if enabled (Standard+ only)
        var audioURLToTranscribe = fileURL
        var segmentMap: SegmentMap? = nil
        var trimmedURL: URL? = nil
        var silenceTrimmedSeconds: TimeInterval? = nil
        
        // Only apply silence trimming/speed-up for cloud transcription (saves API costs)
        if !useOnDeviceForThis && shouldUseSilenceTrimming {
            print("✂️ [TranscriptionService] Applying audio processing (silence trim + speed-up)...")
            do {
                let trimResult = try await SilenceTrimmingService.shared.trimSilence(from: fileURL)
                segmentMap = trimResult.segmentMap
                
                // Always use the processed URL (it's either trimmed+sped or just sped)
                audioURLToTranscribe = trimResult.trimmedURL
                trimmedURL = trimResult.trimmedURL
                
                if trimResult.segmentMap.hasTrimming {
                    silenceTrimmedSeconds = trimResult.segmentMap.originalDuration - trimResult.segmentMap.trimmedDuration
                    print("✂️ [TranscriptionService] Silence trimmed: \(String(format: "%.1f", silenceTrimmedSeconds ?? 0))s removed")
                }
                print("✂️ [TranscriptionService] Using processed audio: \(trimResult.trimmedURL.lastPathComponent)")
            } catch {
                print("⚠️ [TranscriptionService] Audio processing failed, continuing with original audio: \(error.localizedDescription)")
                // Continue with original audio if processing fails
            }
        }
        
        defer {
            // Cleanup temporary trimmed file
            if let url = trimmedURL {
                SilenceTrimmingService.shared.cleanupTrimmedFile(at: url)
            }
        }
        
        if useOnDeviceForThis {
            print("✅ [TranscriptionService] Using ON-DEVICE transcription")
            // Use on-device transcription (no silence trimming needed - it's free)
            let onDeviceService = OnDeviceTranscriptionService.shared
            
            let response: ScribeResponse
            
            if useAutoLanguageDetection {
                print("🌍 [TranscriptionService] Using automatic language detection")
                response = try await onDeviceService.transcribeWithLanguageDetection(
                    fileURL: fileURL,
                    preferredLanguages: [preferredLanguage],
                    progressHandler: progressHandler,
                    progressFraction: progressFraction
                )
            } else {
                print("🗣️ [TranscriptionService] Using preferred language: \(preferredLanguage)")
                onDeviceService.setLanguage(preferredLanguage)
                response = try await onDeviceService.transcribe(
                    fileURL: fileURL,
                    progressHandler: progressHandler,
                    progressFraction: progressFraction
                )
            }
            
            let transcript = onDeviceService.buildTranscript(from: response)
            print("✅ [TranscriptionService] On-device transcription completed")
            return TranscriptionResult(
                response: response,
                transcript: transcript,
                wasOnDevice: true,
                detectedLanguage: response.language_code,
                wasSilenceTrimmed: false,
                silenceTrimmedSeconds: nil
            )
        } else {
            print("☁️ [TranscriptionService] Using CLOUD transcription (ElevenLabs)")
            // Use cloud transcription (ElevenLabs)
            let response = try await transcribe(fileURL: audioURLToTranscribe, diarize: diarize)
            
            // Remap timestamps if audio was processed (sped up and/or silence trimmed)
            let remappedResponse: ScribeResponse
            if let map = segmentMap {
                print("🔄 [TranscriptionService] Remapping timestamps to original audio timeline (speed: \(map.speedMultiplier)x, trimming: \(map.hasTrimming))")
                remappedResponse = remapTimestamps(response: response, segmentMap: map)
            } else {
                remappedResponse = response
            }
            
            let transcript = buildTranscript(from: remappedResponse)
            print("✅ [TranscriptionService] Cloud transcription completed")
            return TranscriptionResult(
                response: remappedResponse,
                transcript: transcript,
                wasOnDevice: false,
                detectedLanguage: remappedResponse.language_code,
                wasSilenceTrimmed: segmentMap?.hasTrimming ?? false,
                silenceTrimmedSeconds: silenceTrimmedSeconds
            )
        }
    }
    
    /// Remap timestamps from trimmed audio back to original audio timeline
    private func remapTimestamps(response: ScribeResponse, segmentMap: SegmentMap) -> ScribeResponse {
        guard let words = response.words else {
            return response
        }
        
        let remappedWords = words.map { word in
            ScribeWord(
                text: word.text,
                start: segmentMap.remapToOriginal(word.start),
                end: segmentMap.remapToOriginal(word.end),
                type: word.type,
                speaker_id: word.speaker_id
            )
        }
        
        return ScribeResponse(
            language_code: response.language_code,
            language_probability: response.language_probability,
            text: response.text,
            words: remappedWords
        )
    }
    
    // MARK: - Language Support Info
    
    /// Get supported languages for on-device transcription
    static var supportedLanguages: [(code: String, name: String)] {
        OnDeviceTranscriptionService.commonLanguages.filter { lang in
            OnDeviceTranscriptionService.isLanguageSupported(lang.code)
        }
    }
    
    /// Check if a language supports on-device recognition
    static func supportsOnDevice(languageCode: String) -> Bool {
        OnDeviceTranscriptionService.onDeviceSupportedLocales.contains {
            $0.language.languageCode?.identifier == languageCode
        }
    }
}
