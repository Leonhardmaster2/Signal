import Foundation

// MARK: - Gemini API Response Types

private struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig
}

private struct GeminiContent: Encodable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Encodable {
    let text: String
}

private struct GeminiGenerationConfig: Encodable {
    let temperature: Double
    let maxOutputTokens: Int
    let responseMimeType: String
}

private struct GeminiResponse: Decodable {
    let candidates: [GeminiCandidate]?
}

private struct GeminiCandidate: Decodable {
    let content: GeminiResponseContent?
}

private struct GeminiResponseContent: Decodable {
    let parts: [GeminiResponsePart]?
}

private struct GeminiResponsePart: Decodable {
    let text: String?
}

// MARK: - Parsed Summary from Gemini

private struct GeminiSummaryJSON: Decodable {
    let oneLiner: String
    let context: String
    let sources: [GeminiSource]?
    let actions: [GeminiAction]
    let emails: [GeminiEmail]?
    let reminders: [GeminiReminder]?
    let calendarEvents: [GeminiCalendarEvent]?
}

private struct GeminiSource: Decodable {
    let timestamp: Double
    let description: String
}

private struct GeminiAction: Decodable {
    let assignee: String
    let task: String
    let timestamp: Double?
}

private struct GeminiEmail: Decodable {
    let recipient: String
    let subject: String
    let body: String
    let timestamp: Double?
}

private struct GeminiReminder: Decodable {
    let title: String
    let dueDescription: String
    let dueDate: String?
    let timestamp: Double?
}

private struct GeminiCalendarEvent: Decodable {
    let title: String
    let dateDescription: String
    let eventDate: String?
    let duration: Double?
    let timestamp: Double?
}

// MARK: - Errors

enum SummarizationError: LocalizedError {
    case noAPIKey
    case noTranscript
    case requestFailed(Int, String)
    case emptyResponse
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Gemini API key found. Add your key in Secrets.plist."
        case .noTranscript: return "No transcript available to summarize."
        case .requestFailed(let code, let msg): return "Gemini API error (\(code)): \(msg)"
        case .emptyResponse: return "Gemini returned an empty response."
        case .decodingFailed(let msg): return "Failed to parse summary: \(msg)"
        }
    }
}

// MARK: - Service

final class SummarizationService {
    static let shared = SummarizationService()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
    
    /// Whether to use on-device summarization (from settings)
    var useOnDevice: Bool {
        UserDefaults.standard.bool(forKey: "useOnDeviceSummarization")
    }
    
    /// Check if on-device summarization is available and enabled
    var shouldUseOnDevice: Bool {
        useOnDevice && OnDeviceSummarizationService.shared.isAvailable
    }

    private var apiKey: String? {
        // Check UserDefaults first (set from Settings)
        let stored = UserDefaults.standard.string(forKey: "geminiAPIKey")
        if let stored, !stored.isEmpty, stored != "YOUR_API_KEY_HERE" {
            return stored
        }
        // Fall back to Secrets.plist
        guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let key = dict["GEMINI_API_KEY"] as? String,
              key != "YOUR_API_KEY_HERE"
        else { return nil }
        return key
    }

    /// Summarize a transcript into a one-liner, context paragraph, sources, and action items.
    /// - Parameters:
    ///   - transcript: The transcript text to summarize
    ///   - meetingNotes: Optional user-provided meeting notes
    ///   - language: Optional language code (e.g., "en", "de", "es") - summary will be in this language
    func summarize(transcript: String, meetingNotes: String? = nil, language: String? = nil) async throws -> (oneLiner: String, context: String, actions: [ActionData], sources: [SourceData], emails: [EmailActionData], reminders: [ReminderActionData], calendarEvents: [CalendarEventData]) {
        guard let apiKey else { throw SummarizationError.noAPIKey }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationError.noTranscript
        }

        let prompt = buildPrompt(transcript: transcript, meetingNotes: meetingNotes, language: language)

        let request = GeminiRequest(
            contents: [GeminiContent(parts: [GeminiPart(text: prompt)])],
            generationConfig: GeminiGenerationConfig(
                temperature: 0.3,
                maxOutputTokens: 2048,
                responseMimeType: "application/json"
            )
        )

        let urlString = "\(baseURL)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw SummarizationError.requestFailed(0, "Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizationError.requestFailed(0, "No HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummarizationError.requestFailed(httpResponse.statusCode, errorBody)
        }

        // Parse the Gemini response envelope
        let geminiResponse: GeminiResponse
        do {
            geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
        } catch {
            throw SummarizationError.decodingFailed("Could not parse Gemini response: \(error.localizedDescription)")
        }

        guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text,
              !text.isEmpty else {
            throw SummarizationError.emptyResponse
        }

        // Parse the JSON summary from Gemini's output
        return try parseSummaryJSON(text)
    }

    // MARK: - Prompt

    private func buildPrompt(transcript: String, meetingNotes: String?, language: String?) -> String {
        // Determine language instruction — use transcript language if available, otherwise app language
        let languageInstruction: String
        let effectiveLang = language ?? LocalizationManager.shared.currentLanguage.rawValue
        if !effectiveLang.isEmpty && effectiveLang != "en" {
            let languageName = Locale.current.localizedString(forLanguageCode: effectiveLang) ?? effectiveLang
            languageInstruction = "\n- IMPORTANT: Write your entire response (oneLiner, context, sources descriptions, and action tasks) in \(languageName). The transcript is in \(languageName), so respond in the same language."
        } else {
            languageInstruction = ""
        }
        
        let currentDate = Date().formatted(date: .long, time: .omitted)
        let usageContext = UserUsageType.saved?.promptContext ?? ""
        var prompt = """
        You are a precise meeting summarizer. Analyze the following meeting transcript and produce a JSON summary with source citations.

        Today's date is \(currentDate). Use this as your reference for the current date and year when interpreting relative dates (e.g. "tomorrow", "next Friday", "by end of month").
        \(usageContext.isEmpty ? "" : "\n\(usageContext)\n")
        Rules:
        - "oneLiner": A single concise sentence (max 20 words) capturing the core outcome or decision.
        - "context": 2-4 sentences providing essential background, key discussion points, and conclusions. When making claims, cite the source timestamp in square brackets [MM:SS].
        - "sources": An array of key moments with "timestamp" (in seconds as a number) and "description" (brief summary of what was discussed at that point).
        - "actions": An array of action items with "assignee" (speaker name or "Team"), "task" (clear, actionable description), and optional "timestamp" (in seconds, where this action was mentioned).
        - "emails": An array of email-sending references. Include when someone says things like "email John about X", "send the report to Y", "I'll write them an email". Each has "recipient" (person/group name), "subject" (inferred subject line), "body" (suggested brief email body), and optional "timestamp" (seconds). If none found, return an empty array.
        - "reminders": An array of deadlines or tasks with due dates. Include when someone mentions things like "finish by tonight", "submit the report by Friday", "don't forget to call them tomorrow". Each has "title" (what needs to be done), "dueDescription" (natural language date like "by Friday"), "dueDate" (ISO 8601 format with Z suffix like "2026-02-15T18:00:00Z" if parseable, otherwise null), and optional "timestamp" (seconds). If none found, return an empty array.
        - "calendarEvents": An array of meetings or events to schedule. Include when someone says things like "let's meet Tuesday at 3pm", "schedule a call for next week", "the presentation is on March 5th". Each has "title" (event name), "dateDescription" (natural language like "Tuesday at 3pm"), "eventDate" (ISO 8601 format with Z suffix like "2026-03-05T15:00:00Z" if parseable, otherwise null), "duration" (in seconds, default 3600), and optional "timestamp" (seconds). If none found, return an empty array.
        - If no clear action items exist, return an empty actions array.
        - Use speaker names as they appear in the transcript.
        - Be concise and factual. No filler.
        - Extract 3-5 key source timestamps that support your summary.\(languageInstruction)

        Respond ONLY with valid JSON matching this schema:
        {
          "oneLiner": "string",
          "context": "string",
          "sources": [{"timestamp": number, "description": "string"}],
          "actions": [{"assignee": "string", "task": "string", "timestamp": number}],
          "emails": [{"recipient": "string", "subject": "string", "body": "string", "timestamp": number}],
          "reminders": [{"title": "string", "dueDescription": "string", "dueDate": "string or null", "timestamp": number}],
          "calendarEvents": [{"title": "string", "dateDescription": "string", "eventDate": "string or null", "duration": number, "timestamp": number}]
        }

        TRANSCRIPT:
        \(transcript)
        """

        if let notes = meetingNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += """

            MEETING NOTES (provided by the user for additional context):
            \(notes)
            """
        }

        return prompt
    }

    // MARK: - Parsing

    private func parseSummaryJSON(_ text: String) throws -> (oneLiner: String, context: String, actions: [ActionData], sources: [SourceData], emails: [EmailActionData], reminders: [ReminderActionData], calendarEvents: [CalendarEventData]) {
        // Clean up potential markdown code fences
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw SummarizationError.decodingFailed("Could not convert response to data")
        }

        let parsed: GeminiSummaryJSON
        do {
            parsed = try JSONDecoder().decode(GeminiSummaryJSON.self, from: jsonData)
        } catch {
            throw SummarizationError.decodingFailed(error.localizedDescription)
        }

        let actions = parsed.actions.map {
            ActionData(assignee: $0.assignee, task: $0.task, isCompleted: false, timestamp: $0.timestamp)
        }

        let sources = (parsed.sources ?? []).map {
            SourceData(timestamp: $0.timestamp, description: $0.description)
        }

        // ISO 8601 with fractional seconds: "2026-02-15T18:00:00.000Z"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // ISO 8601 with Z suffix: "2026-02-15T18:00:00Z"
        let isoFormatterBasic = ISO8601DateFormatter()
        // Fallback: ISO 8601 without timezone: "2026-02-15T18:00:00"
        let isoNoTZ = DateFormatter()
        isoNoTZ.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        isoNoTZ.locale = Locale(identifier: "en_US_POSIX")
        // Fallback: date-only: "2026-02-15"
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")

        func parseDate(_ str: String) -> Date? {
            isoFormatter.date(from: str)
            ?? isoFormatterBasic.date(from: str)
            ?? isoNoTZ.date(from: str)
            ?? dateOnly.date(from: str)
        }

        let emails = (parsed.emails ?? []).map {
            EmailActionData(recipient: $0.recipient, subject: $0.subject, body: $0.body, timestamp: $0.timestamp)
        }

        let reminders = (parsed.reminders ?? []).map { r in
            let date = r.dueDate.flatMap { parseDate($0) }
            return ReminderActionData(title: r.title, dueDescription: r.dueDescription, dueDate: date, timestamp: r.timestamp)
        }

        let calendarEvents = (parsed.calendarEvents ?? []).map { e in
            let date = e.eventDate.flatMap { parseDate($0) }
            return CalendarEventData(title: e.title, dateDescription: e.dateDescription, eventDate: date, duration: e.duration, timestamp: e.timestamp)
        }

        return (parsed.oneLiner, parsed.context, actions, sources, emails, reminders, calendarEvents)
    }
    
    // MARK: - Unified Summarization (Routes to On-Device or Cloud)
    
    /// Result type that includes whether summarization was done on-device
    struct SummarizationResult {
        let oneLiner: String
        let context: String
        let actions: [ActionData]
        let sources: [SourceData]
        let emails: [EmailActionData]
        let reminders: [ReminderActionData]
        let calendarEvents: [CalendarEventData]
        let wasOnDevice: Bool
    }
    
    /// Unified summarization method that automatically routes based on settings
    /// - Parameters:
    ///   - transcript: The transcript text to summarize
    ///   - meetingNotes: Optional user-provided meeting notes
    ///   - language: Optional language code from transcription (e.g., "en", "de") - summary will match this language
    func summarizeAuto(transcript: String, meetingNotes: String? = nil, language: String? = nil) async throws -> SummarizationResult {
        print("📝 [Summarization] Starting with language: \(language ?? "default")")
        
        if shouldUseOnDevice {
            // Use on-device summarization (Apple Intelligence)
            let result = try await OnDeviceSummarizationService.shared.summarize(
                transcript: transcript,
                meetingNotes: meetingNotes
            )
            return SummarizationResult(
                oneLiner: result.oneLiner,
                context: result.context,
                actions: result.actions,
                sources: result.sources ?? [],
                emails: [],
                reminders: [],
                calendarEvents: [],
                wasOnDevice: true
            )
        } else {
            // Use cloud summarization (Gemini) with language matching
            let result = try await summarize(transcript: transcript, meetingNotes: meetingNotes, language: language)
            return SummarizationResult(
                oneLiner: result.oneLiner,
                context: result.context,
                actions: result.actions,
                sources: result.sources,
                emails: result.emails,
                reminders: result.reminders,
                calendarEvents: result.calendarEvents,
                wasOnDevice: false
            )
        }
    }
}
