import Foundation
import Supabase
import GoogleSignIn

@Observable
@MainActor
final class AuthService {

    // MARK: - State

    private(set) var session: Session?

    var isAuthenticated: Bool {
        session != nil
    }

    var displayName: String? {
        session?.user.userMetadata["name"]?.stringValue
    }

    var needsDisplayName: Bool {
        isAuthenticated && (displayName == nil || displayName!.isEmpty)
    }

    // MARK: - Init

    init() {
        // Subscribe to Supabase auth state changes.
        // Fires on sign-in, sign-out, token refresh, and session restore.
        // @MainActor is explicit on the Task to make actor inheritance clear —
        // AuthService is @MainActor, so writes to self.session are safe.
        Task { @MainActor in
            for await (_, session) in supabase.auth.authStateChanges {
                self.session = session
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

    // MARK: - Google Sign In

    func signInWithGoogle() async throws {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
            let rootViewController = windowScene.windows.first?.rootViewController
        else {
            throw AuthError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }

        try await supabase.auth.signInWithIdToken(credentials: OpenIDConnectCredentials(
            provider: .google,
            idToken: idToken,
            accessToken: result.user.accessToken.tokenString
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

    // MARK: - Display Name

    func updateDisplayName(_ name: String) async throws {
        try await supabase.auth.update(user: UserAttributes(data: ["name": .string(name)]))
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await supabase.auth.signOut()
        // session is set to nil automatically via authStateChanges
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case noPresentingViewController
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Could not find a view controller to present sign-in."
        case .missingIDToken:
            return "Google sign-in did not return an ID token."
        }
    }
}
