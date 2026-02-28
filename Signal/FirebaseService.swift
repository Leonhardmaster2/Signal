import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFunctions
import UIKit

/// Secure Firebase backend service for proxying ElevenLabs and Gemini API calls
final class FirebaseService {
    static let shared = FirebaseService()
    
    private let functions: Functions
    private var currentUser: User? {
        Auth.auth().currentUser
    }
    
    private init() {
        // Configure Firebase
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        // Initialize Functions with US Central region
        self.functions = Functions.functions(region: "us-central1")
        
        // Enable emulator for local testing (comment out for production)
        #if DEBUG
        // functions.useEmulator(withHost: "localhost", port: 5001)
        #endif
    }
    
    // MARK: - Authentication
    
    /// Check if user is authenticated
    var isAuthenticated: Bool {
        currentUser != nil
    }
    
    /// Get current user ID
    var userId: String? {
        currentUser?.uid
    }
    
    /// Sign in with Apple credential and authenticate with Firebase
    /// - Parameter credential: Apple ID credential from Sign in with Apple
    func signInWithApple(idToken: String, rawNonce: String) async throws {
        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: idToken,
            rawNonce: rawNonce
        )
        
        let result = try await Auth.auth().signIn(with: credential)
        print("✅ [Firebase] Signed in as: \(result.user.uid)")
    }
    
    /// Sign out from Firebase
    func signOut() throws {
        try Auth.auth().signOut()
        print("✅ [Firebase] Signed out")
    }
    
    // MARK: - Device Metadata
    
    /// Get device model (e.g., "iPhone 15 Pro")
    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        return identifier
    }
    
    /// Get iOS version (e.g., "18.2")
    private var iosVersion: String {
        UIDevice.current.systemVersion
    }
    
    /// Get app version (e.g., "1.0.0")
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    // MARK: - STT (ElevenLabs Scribe)
    
    /// Process audio file using ElevenLabs Scribe API via Firebase Cloud Function
    /// - Parameters:
    ///   - fileURL: Local audio file URL
    ///   - diarize: Whether to enable speaker diarization
    /// - Returns: Scribe response with transcription and word-level timestamps
    func processAudio(fileURL: URL, diarize: Bool) async throws -> ScribeResponse {
        guard isAuthenticated else {
            throw FirebaseServiceError.notAuthenticated
        }
        
        print("☁️ [Firebase] Starting audio processing...")
        
        // Read audio file
        let audioData = try Data(contentsOf: fileURL)
        let base64Audio = audioData.base64EncodedString()
        
        // Build request payload
        let payload: [String: Any] = [
            "audioBase64": base64Audio,
            "fileName": fileURL.lastPathComponent,
            "diarize": diarize,
            "deviceModel": deviceModel,
            "appVersion": appVersion,
            "iosVersion": iosVersion
        ]
        
        // Call Cloud Function
        let callable = functions.httpsCallable("processAudio")
        
        do {
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any] else {
                throw FirebaseServiceError.invalidResponse
            }
            
            // Parse response
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let response = try JSONDecoder().decode(ScribeResponse.self, from: jsonData)
            
            print("✅ [Firebase] Audio processing completed")
            return response
        } catch let error as NSError {
            // Handle Firebase Functions errors
            if let code = FunctionsErrorCode(rawValue: error.code) {
                throw FirebaseServiceError.functionsError(code, error.localizedDescription)
            }
            throw error
        }
    }
    
    // MARK: - Gemini API
    
    /// Generate text using Gemini API via Firebase Cloud Function
    /// - Parameters:
    ///   - prompt: The prompt text
    ///   - temperature: Sampling temperature (default: 0.3)
    ///   - maxOutputTokens: Maximum tokens to generate (default: 2048)
    ///   - responseMimeType: Response format (default: "application/json")
    /// - Returns: Generated text from Gemini
    func generateText(
        prompt: String,
        temperature: Double = 0.3,
        maxOutputTokens: Int = 2048,
        responseMimeType: String = "application/json"
    ) async throws -> String {
        guard isAuthenticated else {
            throw FirebaseServiceError.notAuthenticated
        }
        
        print("☁️ [Firebase] Starting text generation...")
        
        // Build request payload
        let payload: [String: Any] = [
            "prompt": prompt,
            "temperature": temperature,
            "maxOutputTokens": maxOutputTokens,
            "responseMimeType": responseMimeType,
            "deviceModel": deviceModel,
            "appVersion": appVersion,
            "iosVersion": iosVersion
        ]
        
        // Call Cloud Function
        let callable = functions.httpsCallable("generateText")
        
        do {
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any] else {
                throw FirebaseServiceError.invalidResponse
            }
            
            // Parse Gemini response structure
            guard let candidates = data["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                throw FirebaseServiceError.emptyResponse
            }
            
            print("✅ [Firebase] Text generation completed")
            return text
        } catch let error as NSError {
            // Handle Firebase Functions errors
            if let code = FunctionsErrorCode(rawValue: error.code) {
                throw FirebaseServiceError.functionsError(code, error.localizedDescription)
            }
            throw error
        }
    }
}

// MARK: - Errors

enum FirebaseServiceError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case emptyResponse
    case functionsError(FunctionsErrorCode, String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use this feature."
        case .invalidResponse:
            return "Received invalid response from server."
        case .emptyResponse:
            return "Server returned an empty response."
        case .functionsError(let code, let message):
            switch code {
            case .unauthenticated:
                return "Authentication required. Please sign in again."
            case .permissionDenied:
                return "You don't have permission to perform this action."
            case .unavailable:
                return "Service temporarily unavailable. Please try again."
            case .deadlineExceeded:
                return "Request timed out. Please try again."
            default:
                return "Server error: \(message)"
            }
        }
    }
}
