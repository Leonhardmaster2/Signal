import Foundation

// MARK: - Chat Message (Persisted)

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    enum ChatRole: String, Equatable, Codable {
        case user
        case model
    }

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

// MARK: - Chat Persistence

/// Persists chat messages per recording as JSON files on disk.
/// Avoids SwiftData schema migrations and keeps chat data separate from core recording data.
enum ChatPersistence {
    private static var chatDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("ChatHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(for recordingUID: UUID) -> URL {
        chatDirectory.appendingPathComponent("\(recordingUID.uuidString).json")
    }

    static func load(for recordingUID: UUID) -> [ChatMessage] {
        let url = fileURL(for: recordingUID)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return [] }
        return messages
    }

    static func save(_ messages: [ChatMessage], for recordingUID: UUID) {
        let url = fileURL(for: recordingUID)
        guard let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func delete(for recordingUID: UUID) {
        let url = fileURL(for: recordingUID)
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Timestamp Citation

struct TimestampCitation: Identifiable {
    let id = UUID()
    let text: String             // "2:34"
    let range: Range<String.Index>
    let timeInterval: TimeInterval
}

// MARK: - Gemini Chat API Types

private struct GeminiChatRequest: Encodable {
    let contents: [GeminiChatContent]
    let systemInstruction: GeminiChatContent?
    let generationConfig: GeminiChatGenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
        case generationConfig
    }
}

private struct GeminiChatContent: Encodable {
    let role: String?
    let parts: [GeminiChatPart]
}

private struct GeminiChatPart: Encodable {
    let text: String
}

private struct GeminiChatGenerationConfig: Encodable {
    let temperature: Double
    let maxOutputTokens: Int
}

private struct GeminiChatResponse: Decodable {
    let candidates: [GeminiChatCandidate]?
}

private struct GeminiChatCandidate: Decodable {
    let content: GeminiChatResponseContent?
}

private struct GeminiChatResponseContent: Decodable {
    let parts: [GeminiChatResponsePart]?
}

private struct GeminiChatResponsePart: Decodable {
    let text: String?
}

// MARK: - Errors

enum ChatServiceError: LocalizedError {
    case noAPIKey
    case noTranscript
    case requestFailed(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Gemini API key found."
        case .noTranscript: return "No transcript available."
        case .requestFailed(let code, let msg): return "API error (\(code)): \(msg)"
        case .emptyResponse: return "No response from Gemini."
        }
    }
}

// MARK: - Service

final class ChatService {
    static let shared = ChatService()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"

    private var apiKey: String? {
        let stored = UserDefaults.standard.string(forKey: "geminiAPIKey")
        if let stored, !stored.isEmpty, stored != "YOUR_API_KEY_HERE" {
            return stored
        }
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["GEMINI_API_KEY"] as? String,
              key != "YOUR_API_KEY_HERE"
        else { return nil }
        return key
    }

    /// Send a message and get a response, including full conversation history for context.
    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        transcript: String,
        segments: [SegmentData],
        speakerNames: [String: String]?
    ) async throws -> String {
        guard let apiKey else { throw ChatServiceError.noAPIKey }
        guard !transcript.isEmpty else { throw ChatServiceError.noTranscript }

        // Build system instruction with formatted transcript
        let formattedTranscript = formatTranscript(segments: segments, speakerNames: speakerNames)
        let userLanguage = LocalizationManager.shared.currentLanguage.englishName
        let currentDate = Date().formatted(date: .long, time: .omitted)
        let usageContext = UserUsageType.saved?.promptContext ?? ""
        let systemPrompt = """
        You are a helpful assistant that answers questions about a recorded audio transcript.
        The full transcript is provided below with timestamps and speaker labels.

        Today's date is \(currentDate). Always use this as your reference for the current date and year.
        \(usageContext.isEmpty ? "" : "\n\(usageContext)\n")
        IMPORTANT: Always respond in \(userLanguage). The user's app language is set to \(userLanguage).

        When referencing specific parts of the transcript, ALWAYS cite the timestamp in the format [MM:SS].
        These timestamps will become tappable links for the user, so use them whenever you reference a specific part.

        Use markdown formatting to improve readability:
        - Use **bold** for key terms, names, and important conclusions.
        - Use bullet points for lists.
        - Use numbered lists for sequential steps or ranked items.
        - Keep paragraphs short and well-structured.

        Be concise, factual, and directly reference the transcript.

        TRANSCRIPT:
        \(formattedTranscript)
        """

        let systemInstruction = GeminiChatContent(role: nil, parts: [GeminiChatPart(text: systemPrompt)])

        // Build conversation contents (alternating user/model)
        var contents: [GeminiChatContent] = []
        for message in conversationHistory {
            let role = message.role == .user ? "user" : "model"
            contents.append(GeminiChatContent(role: role, parts: [GeminiChatPart(text: message.content)]))
        }
        // Add current user message
        contents.append(GeminiChatContent(role: "user", parts: [GeminiChatPart(text: userMessage)]))

        let request = GeminiChatRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: GeminiChatGenerationConfig(
                temperature: 0.4,
                maxOutputTokens: 2048
            )
        )

        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw ChatServiceError.requestFailed(0, "Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatServiceError.requestFailed(0, "No HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatServiceError.requestFailed(httpResponse.statusCode, errorBody)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiChatResponse.self, from: data)

        guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text,
              !text.isEmpty else {
            throw ChatServiceError.emptyResponse
        }

        return text
    }

    // MARK: - Helpers

    private func formatTranscript(segments: [SegmentData], speakerNames: [String: String]?) -> String {
        let names = speakerNames ?? [:]
        return segments.map { seg in
            let speaker = names[seg.speaker] ?? seg.speaker
            let ts = formatTimestamp(seg.timestamp)
            return "[\(speaker) at \(ts)] \(seg.text)"
        }.joined(separator: "\n")
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Citation Parsing

    /// Parse [MM:SS] or [H:MM:SS] citations from response text
    static func parseCitations(from text: String) -> [TimestampCitation] {
        let pattern = #"\[(\d{1,2}:\d{2}(?::\d{2})?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        return matches.compactMap { match in
            guard let fullRange = Range(match.range, in: text),
                  let innerRange = Range(match.range(at: 1), in: text) else { return nil }

            let timeString = String(text[innerRange])
            guard let interval = parseTimeString(timeString) else { return nil }

            return TimestampCitation(text: timeString, range: fullRange, timeInterval: interval)
        }
    }

    private static func parseTimeString(_ time: String) -> TimeInterval? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return TimeInterval(parts[0] * 60 + parts[1])
        case 3: return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        default: return nil
        }
    }

    /// Convert seconds back to a display timestamp string (e.g. 90 → "1:30")
    static func formatSecondsToTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
