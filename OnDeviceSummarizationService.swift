import Foundation
import FoundationModels

// MARK: - On-Device Summarization Errors

enum OnDeviceSummarizationError: LocalizedError {
    case modelNotAvailable
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case generationFailed(String)
    case noTranscript
    
    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Apple Intelligence is not available on this device."
        case .appleIntelligenceNotEnabled:
            return "Please enable Apple Intelligence in Settings to use on-device summarization."
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence."
        case .modelNotReady:
            return "Apple Intelligence model is still downloading. Please try again later."
        case .generationFailed(let message):
            return "Summarization failed: \(message)"
        case .noTranscript:
            return "No transcript available to summarize."
        }
    }
}

// MARK: - Generable Summary Types

@Generable(description: "A structured summary of a meeting or conversation")
struct GeneratedSummary {
    @Guide(description: "A single concise sentence (max 20 words) capturing the core outcome or decision")
    var oneLiner: String
    
    @Guide(description: "2-4 sentences providing essential background, key discussion points, and conclusions")
    var context: String
    
    @Guide(description: "Key source moments from the conversation with timestamps (3-5 items)")
    var sources: [GeneratedSource]
    
    @Guide(description: "List of action items extracted from the conversation")
    var actions: [GeneratedAction]
}

@Generable(description: "A source citation from the conversation")
struct GeneratedSource {
    @Guide(description: "Timestamp in seconds where this was discussed")
    var timestamp: Double
    
    @Guide(description: "Brief description of what was discussed at this moment")
    var description: String
}

@Generable(description: "An action item from a meeting")
struct GeneratedAction {
    @Guide(description: "The person or team responsible for this task")
    var assignee: String
    
    @Guide(description: "A clear, actionable description of what needs to be done")
    var task: String
    
    @Guide(description: "Optional timestamp in seconds where this action was mentioned")
    var timestamp: Double?
}

// MARK: - On-Device Summarization Service

final class OnDeviceSummarizationService {
    static let shared = OnDeviceSummarizationService()
    
    private var model: SystemLanguageModel {
        SystemLanguageModel.default
    }
    
    /// Check if Apple Intelligence is available
    var isAvailable: Bool {
        if case .available = model.availability {
            return true
        }
        return false
    }
    
    /// Get the specific unavailability reason
    var unavailabilityReason: OnDeviceSummarizationError? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .modelNotAvailable
        }
    }
    
    /// Summarize a transcript using Apple Intelligence (on-device)
    func summarize(transcript: String, meetingNotes: String? = nil) async throws -> (oneLiner: String, context: String, actions: [ActionData], sources: [SourceData]?) {
        // Check availability
        guard isAvailable else {
            throw unavailabilityReason ?? .modelNotAvailable
        }
        
        // Validate transcript
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OnDeviceSummarizationError.noTranscript
        }
        
        // Create session with instructions
        let session = LanguageModelSession(instructions: """
            You are a precise meeting summarizer. Analyze transcripts and produce structured summaries.
            
            Rules:
            - The oneLiner should be a single concise sentence (max 20 words) capturing the core outcome or decision.
            - The context should be 2-4 sentences providing essential background, key discussion points, and conclusions.
            - Actions should be clear, actionable items with the assignee (speaker name or "Team") and task description.
            - If no clear action items exist, return an empty actions array.
            - Use speaker names as they appear in the transcript.
            - Be concise and factual. No filler.
            """)
        
        // Build the prompt
        var prompt = "Please summarize the following transcript:\n\n\(transcript)"
        
        if let notes = meetingNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nMEETING NOTES (provided for additional context):\n\(notes)"
        }
        
        do {
            // Use guided generation to get structured output
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedSummary.self
            )
            
            let summary = response.content
            
            // Convert to ActionData format
            let actions = summary.actions.map { action in
                ActionData(
                    assignee: action.assignee,
                    task: action.task,
                    isCompleted: false,
                    timestamp: action.timestamp
                )
            }
            
            // Convert to SourceData format
            let sources = summary.sources.map { source in
                SourceData(
                    timestamp: source.timestamp,
                    description: source.description
                )
            }
            
            return (summary.oneLiner, summary.context, actions, sources)
            
        } catch {
            throw OnDeviceSummarizationError.generationFailed(error.localizedDescription)
        }
    }
}
