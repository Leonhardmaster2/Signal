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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { throw TranscriptionError.fileNotFound }

        // Build the request body on a background thread since file I/O can be expensive
        let body = try await Task.detached(priority: .userInitiated) {
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

            let fileData = try Data(contentsOf: fileURL)
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
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
    }
    
    /// Whether to use automatic language detection (from settings)
    var useAutoLanguageDetection: Bool {
        UserDefaults.standard.bool(forKey: "useAutoLanguageDetection")
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
    /// Supports background execution and automatic language detection
    /// - Parameters:
    ///   - fileURL: The audio file to transcribe
    ///   - diarize: Whether to identify speakers (cloud only)
    ///   - forceOnDevice: If true, forces on-device transcription; if false, forces cloud; if nil, uses settings
    ///   - progressHandler: Callback for partial transcription text
    ///   - progressFraction: Callback for progress (0.0 to 1.0)
    func transcribeAuto(fileURL: URL, diarize: Bool = true, forceOnDevice: Bool? = nil, progressHandler: ((String) -> Void)? = nil, progressFraction: ((Double) -> Void)? = nil) async throws -> TranscriptionResult {
        let useOnDeviceForThis = forceOnDevice ?? shouldUseOnDevice
        if useOnDeviceForThis {
            // Use on-device transcription
            let onDeviceService = OnDeviceTranscriptionService.shared
            
            let response: ScribeResponse
            
            if useAutoLanguageDetection {
                // Use automatic language detection
                response = try await onDeviceService.transcribeWithLanguageDetection(
                    fileURL: fileURL,
                    preferredLanguages: [preferredLanguage],
                    progressHandler: progressHandler,
                    progressFraction: progressFraction
                )
            } else {
                // Use preferred language directly
                onDeviceService.setLanguage(preferredLanguage)
                response = try await onDeviceService.transcribe(
                    fileURL: fileURL,
                    progressHandler: progressHandler,
                    progressFraction: progressFraction
                )
            }
            
            let transcript = onDeviceService.buildTranscript(from: response)
            return TranscriptionResult(
                response: response,
                transcript: transcript,
                wasOnDevice: true,
                detectedLanguage: response.language_code
            )
        } else {
            // Use cloud transcription (ElevenLabs) - it has its own language detection
            let response = try await transcribe(fileURL: fileURL, diarize: diarize)
            let transcript = buildTranscript(from: response)
            return TranscriptionResult(
                response: response,
                transcript: transcript,
                wasOnDevice: false,
                detectedLanguage: response.language_code
            )
        }
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
