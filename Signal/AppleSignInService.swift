// AppleSignInService.swift
// Handles Sign in with Apple authentication

import AuthenticationServices
import Foundation
import Observation
import UIKit

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
    private var signInContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        restoreState()
    }

    // MARK: - Public API

    /// Present Sign in with Apple and await result
    @MainActor
    func signIn() async throws {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.signInContinuation = continuation
            controller.performRequests()
        }
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
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

        userID = credential.user
        // Apple only provides email/name on FIRST sign-in — persist immediately
        if let e = credential.email { email = e }
        if let g = credential.fullName?.givenName { givenName = g }
        if let f = credential.fullName?.familyName { familyName = f }
        isSignedIn = true

        persistState()
        signInContinuation?.resume()
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
