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
// MARK: - Preview

#if DEBUG
import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
#Preview("Chat Messages") {
    VStack(spacing: 16) {
        ForEach(ChatService.previewMessages) { message in
            HStack {
                if message.role == .user {
                    Spacer()
                }
                
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    Text(message.content)
                        .padding(12)
                        .background(
                            message.role == .user 
                                ? Color.blue.opacity(0.2)
                                : Color.gray.opacity(0.2)
                        )
                        .cornerRadius(12)
                        .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
                    
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if message.role == .model {
                    Spacer()
                }
            }
        }
    }
    .padding()
}

extension ChatService {
    static var previewMessages: [ChatMessage] {
        [
            ChatMessage(role: .user, content: "What were the main topics discussed?"),
            ChatMessage(role: .model, content: "Based on the transcript, the meeting covered **four key areas**:\n\n1. **Q1 Product Launch Timeline** at [2:15] - Sarah outlined the revised schedule with a target launch date of March 15th\n2. **Marketing Budget Reallocation** at [8:42] - Discussion about shifting $50K from print to digital channels\n3. **Engineering Resource Gaps** at [15:30] - James raised concerns about backend infrastructure capacity\n4. **Customer Feedback Integration** at [22:10] - Review of the recent user survey results showing 87% satisfaction\n\nThe team agreed to reconvene next Tuesday to finalize the launch strategy."),
            
            ChatMessage(role: .user, content: "Can you draft an email to the team summarizing the action items?"),
            ChatMessage(role: .model, content: "Here's a summary email you can send:\n\n**To:** team@company.com\n**Subject:** Action Items from Q1 Planning Meeting - Feb 20, 2026\n\n**Hi Team,**\n\nGreat discussion today! Here are our key action items:\n\n**Sarah** - Finalize product launch timeline and share revised milestones by EOD Friday [2:45]\n\n**James** - Conduct infrastructure capacity assessment and propose scaling solutions by Monday [16:15]\n\n**Marketing Team** - Present detailed digital campaign strategy with budget breakdown at Tuesday's follow-up meeting [10:20]\n\n**Everyone** - Review the customer feedback report (link in Slack) before our next session [23:05]\n\n**Next Meeting:** Tuesday, Feb 25 at 2pm\n\nLet me know if I missed anything!\n\nBest,\n[Your name]"),
            
            ChatMessage(role: .user, content: "What reminders should I set?"),
            ChatMessage(role: .model, content: "Based on the meeting, here are the **key reminders** you should set:\n\n**Urgent (This Week):**\n• Review customer feedback report - **Due: Friday, Feb 21** at [23:05]\n• Follow up with Sarah on launch timeline - **Due: Friday, Feb 21** at [2:45]\n• Check James's infrastructure assessment - **Due: Monday, Feb 24** at [16:15]\n\n**Upcoming:**\n• Prepare questions for Tuesday planning meeting - **Due: Monday, Feb 24**\n• Review digital marketing budget proposal - **Due: Tuesday, Feb 25** before 2pm meeting at [10:20]\n\nWould you like me to help you prioritize these?"),
            
            ChatMessage(role: .user, content: "Add the follow-up meeting to my calendar"),
            ChatMessage(role: .model, content: "Here are the **calendar events** from this meeting:\n\n**Primary Event:**\n📅 **Q1 Planning Follow-up Meeting**\n• **Date:** Tuesday, February 25, 2026\n• **Time:** 2:00 PM - 3:30 PM\n• **Location:** Conference Room B / Zoom\n• **Attendees:** Sarah, James, Marketing Team\n• **Agenda:** Finalize product launch strategy, review infrastructure proposal, discuss digital campaign budget\n• **Mentioned at:** [22:45]\n\n**Related Deadline:**\n📅 **Product Launch Date**\n• **Date:** Monday, March 15, 2026\n• **Type:** All-day milestone\n• **Note:** Target release for Q1 product at [2:30]\n\nYou can copy these details to add them to your calendar app!")
        ]
    }
}

#endif

