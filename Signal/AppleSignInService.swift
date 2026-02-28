// AppleSignInService.swift
// Handles Sign in with Apple authentication and Firebase integration

import AuthenticationServices
import Foundation
import Observation
import UIKit
import CryptoKit

@Observable
final class AppleSignInService: NSObject {
    static let shared = AppleSignInService()

    // User state
    private(set) var isSignedIn: Bool = false
    private(set) var userID: String?
    private(set) var email: String?
    private(set) var givenName: String?
    private(set) var familyName: String?

    // Continuation for bridging delegate → async
    private var signInContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    
    // Nonce for Firebase Auth security
    private var currentNonce: String?

    override init() {
        super.init()
        restoreState()
    }

    // MARK: - Public API

    /// Present Sign in with Apple and authenticate with Firebase
    @MainActor
    func signIn() async throws {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        // Generate nonce for Firebase Auth security
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        let credential = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) in
            self.signInContinuation = continuation
            controller.performRequests()
        }
        
        // Authenticate with Firebase using the Apple ID credential
        guard let idToken = credential.identityToken,
              let idTokenString = String(data: idToken, encoding: .utf8),
              let nonce = currentNonce else {
            throw NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"])
        }
        
        try await FirebaseService.shared.signInWithApple(idToken: idTokenString, rawNonce: nonce)
        print("✅ [AppleSignIn] Successfully signed in with Firebase")
    }

    /// Sign out and clear persisted state
    func signOut() {
        isSignedIn = false
        userID = nil
        email = nil
        givenName = nil
        familyName = nil

        let keys = ["appleUserID", "appleUserEmail", "appleUserGivenName", "appleUserFamilyName"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        
        // Also sign out from Firebase
        try? FirebaseService.shared.signOut()
        print("✅ [AppleSignIn] Signed out")
    }

    /// Check if the stored credential is still valid with Apple
    func validateCredential() {
        guard let userID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            DispatchQueue.main.async {
                if state != .authorized {
                    self?.signOut()
                }
            }
        }
    }

    /// Display name for UI
    var displayName: String {
        if let given = givenName, let family = familyName {
            return "\(given) \(family)"
        }
        if let given = givenName { return given }
        if let email { return email }
        return L10n.signedIn
    }

    // MARK: - Persistence

    private func restoreState() {
        guard let storedID = UserDefaults.standard.string(forKey: "appleUserID") else { return }
        userID = storedID
        email = UserDefaults.standard.string(forKey: "appleUserEmail")
        givenName = UserDefaults.standard.string(forKey: "appleUserGivenName")
        familyName = UserDefaults.standard.string(forKey: "appleUserFamilyName")
        isSignedIn = true
    }

    private func persistState() {
        UserDefaults.standard.set(userID, forKey: "appleUserID")
        if let email { UserDefaults.standard.set(email, forKey: "appleUserEmail") }
        if let givenName { UserDefaults.standard.set(givenName, forKey: "appleUserGivenName") }
        if let familyName { UserDefaults.standard.set(familyName, forKey: "appleUserFamilyName") }
    }
    
    // MARK: - Nonce Generation for Firebase Auth
    
    /// Generate a random nonce for Firebase Auth security
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }
    
    /// SHA256 hash for nonce
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { 
            signInContinuation?.resume(throwing: NSError(domain: "AppleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid credential"]))
            signInContinuation = nil
            return 
        }

        userID = credential.user
        // Apple only provides email/name on FIRST sign-in — persist immediately
        if let e = credential.email { email = e }
        if let g = credential.fullName?.givenName { givenName = g }
        if let f = credential.fullName?.familyName { familyName = f }
        isSignedIn = true

        persistState()
        
        // Return credential to signIn() for Firebase authentication
        signInContinuation?.resume(returning: credential)
        signInContinuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        signInContinuation?.resume(throwing: error)
        signInContinuation = nil
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
