import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import Security
import UIKit

@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var user: User?
    @Published private(set) var isSignedIn = false
    @Published private(set) var isAnonymous = true

    private var authListener: AuthStateDidChangeListenerHandle?
    private var appleCoordinator: AppleSignInCoordinator?

    override init() {
        super.init()
        user = Auth.auth().currentUser
        updateState(user)
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.updateState(user)
        }
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    func ensureSignedIn() async {
        if Auth.auth().currentUser == nil {
            _ = try? await signInAnonymously()
        }
    }

    func getIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw AuthManagerError.notSignedIn
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(false) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let token {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: AuthManagerError.missingToken)
                }
            }
        }
    }

    func signInWithApple() async throws {
        let nonce = randomNonceString()
        let coordinator = AppleSignInCoordinator()
        appleCoordinator = coordinator
        defer { appleCoordinator = nil }

        let credential = try await coordinator.signIn(nonce: nonce)

        guard let idTokenData = credential.identityToken,
              let idTokenString = String(data: idTokenData, encoding: .utf8) else {
            throw AuthManagerError.missingAppleToken
        }

        let oauthCredential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idTokenString, rawNonce: nonce)

        if let currentUser = Auth.auth().currentUser, currentUser.isAnonymous {
            _ = try await link(user: currentUser, credential: oauthCredential)
        } else {
            _ = try await signIn(with: oauthCredential)
        }
    }

    private func signInAnonymously() async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signInAnonymously { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AuthManagerError.signInFailed)
                }
            }
        }
    }

    private func signIn(with credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AuthManagerError.signInFailed)
                }
            }
        }
    }

    private func link(user: User, credential: AuthCredential) async throws -> AuthDataResult {
        try await withCheckedThrowingContinuation { continuation in
            user.link(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AuthManagerError.signInFailed)
                }
            }
        }
    }

    private func updateState(_ user: User?) {
        self.user = user
        self.isSignedIn = user != nil
        self.isAnonymous = user?.isAnonymous ?? true
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed.")
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

        func signIn(nonce: String) async throws -> ASAuthorizationAppleIDCredential {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                let provider = ASAuthorizationAppleIDProvider()
                let request = provider.createRequest()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AuthManager.shared.sha256(nonce)

                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                continuation?.resume(returning: credential)
            } else {
                continuation?.resume(throwing: AuthManagerError.invalidAppleCredential)
            }
            continuation = nil
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first(where: { $0.isKeyWindow }) else {
                return UIWindow()
            }
            return window
        }
    }
}

enum AuthManagerError: LocalizedError {
    case notSignedIn
    case missingToken
    case missingAppleToken
    case invalidAppleCredential
    case signInFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in"
        case .missingToken:
            return "Missing auth token"
        case .missingAppleToken:
            return "Missing Apple identity token"
        case .invalidAppleCredential:
            return "Invalid Apple credential"
        case .signInFailed:
            return "Sign in failed"
        }
    }
}
