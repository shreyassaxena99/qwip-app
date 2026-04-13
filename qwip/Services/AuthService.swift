import Foundation
import Supabase
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import PostHog

@Observable
@MainActor
final class AuthService {

    // MARK: - State

    private(set) var session: Session?
    private var _displayName: String? = nil
    var emailOptIn: Bool = false
    private(set) var needsOnboarding: Bool = false

    var isAuthenticated: Bool {
        session != nil
    }

    var displayName: String? {
        _displayName ?? session?.user.userMetadata["name"]?.stringValue
    }

    // MARK: - Init

    init() {
        // Subscribe to Supabase auth state changes.
        // Fires on sign-in, sign-out, token refresh, and session restore.
        // @MainActor is explicit on the Task to make actor inheritance clear —
        // AuthService is @MainActor, so writes to self.session are safe.
        Task { @MainActor in
            for await (event, session) in supabase.auth.authStateChanges {
                self.session = session
                if session == nil {
                    needsOnboarding = false
                } else if event == .signedIn || event == .initialSession, let session {
                    await checkOnboardingStatus(session: session)
                    identify(userId: session.user.id.uuidString)
                }
            }
        }
    }

    // MARK: - Session Restore

    /// Called once on launch as a belt-and-suspenders guard.
    /// supabase.auth.authStateChanges already emits an INITIAL_SESSION event
    /// on subscribe (which restores the Keychain session automatically).
    /// This explicit call ensures the session is eagerly checked even if the
    /// stream hasn't fired yet by the time the first view renders.
    func restoreSession() async {
        _ = try? await supabase.auth.session
    }

    // MARK: - Apple Sign In

    /// Called by SignInView after SignInWithAppleButton completes its flow.
    /// The view owns nonce generation so it can set the hashed nonce on the request.
    func completeAppleSignIn(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) async throws {
        guard
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            throw AuthError.missingIDToken
        }

        try await supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .apple,
            idToken: idToken,
            nonce: rawNonce
        ))

        // Apple only provides the full name on the very first sign-in.
        // Persist it immediately before the credential is invalidated.
        if let name = credential.fullName,
           let given = name.givenName, !given.isEmpty {
            let full = [given, name.familyName].compactMap { $0 }.joined(separator: " ")
            try? await updateProfile(displayName: full)
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async throws {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
            let rootViewController = windowScene.windows.first?.rootViewController
        else {
            throw AuthError.noPresentingViewController
        }

        let rawNonce = randomNonceString()
        let hashedNonce = sha256(rawNonce)

        let result: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            ) { signInResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let signInResult {
                    continuation.resume(returning: signInResult)
                } else {
                    continuation.resume(throwing: AuthError.missingIDToken)
                }
            }
        }

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }

        try await supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .google,
            idToken: idToken,
            accessToken: result.user.accessToken.tokenString,
            nonce: rawNonce
        ))
        // session is updated automatically via authStateChanges
    }

    // MARK: - Email OTP

    func sendOTP(email: String) async throws {
        try await supabase.auth.signInWithOTP(email: email)
    }

    func verifyOTP(email: String, token: String) async throws {
        try await supabase.auth.verifyOTP(email: email, token: token, type: .email)
        // session is updated automatically via authStateChanges
    }

    // MARK: - Profile

    func updateProfile(displayName: String? = nil, emailOptIn: Bool? = nil) async throws {
        guard let token = supabase.auth.currentSession?.accessToken else {
            throw AuthError.notAuthenticated
        }
        let url = URL(string: "https://spotsvc.up.railway.app/me")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(PatchMeBody(displayName: displayName, emailOptIn: emailOptIn))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw AuthError.updateProfileFailed(status) }
        let me = try JSONDecoder().decode(MeResponse.self, from: data)
        _displayName = me.displayName
        self.emailOptIn = me.emailOptIn
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await supabase.auth.signOut()
        // session is set to nil automatically via authStateChanges
    }

    // MARK: - Onboarding

    private func checkOnboardingStatus(session: Session) async {
        let exists = await UserProfileAPIClient.fetchExists(
            userId: session.user.id.uuidString,
            token: session.accessToken
        )
        needsOnboarding = !exists
    }

    func completeOnboarding() {
        needsOnboarding = false
    }

    // MARK: - Analytics

    func identify(userId: String) {
        PostHogSDK.shared.identify(userId, userProperties: [:])
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let token = supabase.auth.currentSession?.accessToken else {
            throw AuthError.notAuthenticated
        }
        let url = URL(string: "https://spotsvc.up.railway.app/me")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw AuthError.deleteAccountFailed(status) }
        try await supabase.auth.signOut()
    }
}

// MARK: - Profile request/response

private struct PatchMeBody: Encodable {
    let displayName: String?
    let emailOptIn: Bool?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = displayName { try c.encode(v, forKey: .displayName) }
        if let v = emailOptIn  { try c.encode(v, forKey: .emailOptIn) }
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case emailOptIn  = "email_opt_in"
    }
}

private struct MeResponse: Decodable {
    let displayName: String
    let emailOptIn: Bool

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case emailOptIn  = "email_opt_in"
    }
}

// MARK: - Nonce Helpers

func randomNonceString(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length
    while remainingLength > 0 {
        let randoms: [UInt8] = (0..<16).map { _ in
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            return random
        }
        for random in randoms {
            if remainingLength == 0 { break }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }
    return result
}

func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case noPresentingViewController
    case missingIDToken
    case cancelledByUser
    case notAuthenticated
    case deleteAccountFailed(Int)
    case updateProfileFailed(Int)

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Could not find a view controller to present sign-in."
        case .missingIDToken:
            return "Sign-in did not return an ID token."
        case .cancelledByUser:
            return nil
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .deleteAccountFailed(let code):
            return "Account deletion failed (server error \(code)). Please try again."
        case .updateProfileFailed(let code):
            return "Couldn't save your changes (server error \(code)). Please try again."
        }
    }
}

