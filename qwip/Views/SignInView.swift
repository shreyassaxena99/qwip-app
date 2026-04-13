import SwiftUI
import AuthenticationServices

struct SignInView: View {

    var onOTPSent: (String) -> Void

    @Environment(AuthService.self) private var authService

    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 28
    @State private var errorMessage: String?
    @State private var appleCoordinator = AppleSignInCoordinator()
    @FocusState private var emailFocused: Bool

    var body: some View {
        ZStack {
            Color.brandSecondary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // Header — logo only
                    Text("qwip")
                        .font(.funnelDisplay(56, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.top, 80)
                        .padding(.bottom, 52)

                    // Form — flat, no card
                    VStack(spacing: 12) {

                        // Email field
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($emailFocused)
                            .font(.dmSans(15, weight: .medium))
                            .foregroundStyle(Color.brandPrimary)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.brandPrimary.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.brandPrimary.opacity(emailFocused ? 0.3 : 0.12), lineWidth: 1.5)
                                    )
                            )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.dmSans(13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Continue button
                        Button(action: { Task { await sendOTP() } }) {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(Color.brandSecondary)
                                } else {
                                    HStack(spacing: 8) {
                                        Text("Continue")
                                            .font(.dmSans(15, weight: .black))
                                            .tracking(0.3)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 13, weight: .bold))
                                    }
                                    .foregroundStyle(Color.brandSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.brandPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(email.isEmpty || isLoading)
                        .opacity(email.isEmpty || isLoading ? 0.7 : 1)
                    }
                    .padding(.horizontal, 24)

                    // Divider
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color.brandBorder)
                            .frame(height: 1)
                        Text("or")
                            .font(.dmSans(11, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(Color.brandPrimary.opacity(0.4))
                        Rectangle()
                            .fill(Color.brandBorder)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)

                    // Social buttons — small squares, centered
                    HStack(spacing: 12) {
                        // Apple
                        socialTile(color: .black) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white)
                        } action: {
                            triggerAppleSignIn()
                        }

                        // Google
                        socialTile(color: Color.brandPrimary.opacity(0.05), stroke: Color.brandBorder) {
                            Image("neutral_google_logo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                        } action: {
                            Task { await signInWithGoogle() }
                        }
                    }
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.7 : 1)

                    // Footer
                    Group {
                        Text("By continuing you agree to our ") +
                        Text("[Terms & Privacy Policy](https://qwip.co.uk/privacy-policy)")
                            .underline()
                    }
                    .font(.dmSans(10, weight: .medium))
                    .foregroundStyle(Color.brandPrimary.opacity(0.35))
                    .tint(Color.brandPrimary.opacity(0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .environment(\.colorScheme, .light)
        .opacity(contentOpacity)
        .offset(y: contentOffset)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                contentOpacity = 1
                contentOffset = 0
            }
            appleCoordinator.onComplete = { result in
                Task { await handleAppleResult(result) }
            }
        }
    }

    // MARK: - Social tile builder

    @ViewBuilder
    private func socialTile<Icon: View>(
        color: Color,
        stroke: Color = .clear,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
                .frame(width: 64, height: 52)
                .overlay(icon())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Auth actions

    private func triggerAppleSignIn() {
        let raw = randomNonceString()
        appleCoordinator.rawNonce = raw

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(raw)

        // Store controller on coordinator so it isn't deallocated before auth completes
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = appleCoordinator
        controller.presentationContextProvider = appleCoordinator
        appleCoordinator.activeController = controller
        controller.performRequests()
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        do {
            let auth = try result.get()
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                throw AuthError.missingIDToken
            }
            try await authService.completeAppleSignIn(credential: credential, rawNonce: appleCoordinator.rawNonce)
        } catch AuthError.cancelledByUser {
            // sheet dismissed — no error
        } catch let error as ASAuthorizationError where error.code == .canceled {
            // sheet dismissed — no error
        } catch let error as ASAuthorizationError where error.code == .unknown {
            errorMessage = "Sign in with Apple isn't available on this device. Try other methods."
        } catch {
            errorMessage = "Sign in with Apple failed. Try other methods."
        }
        isLoading = false
    }

    private func signInWithGoogle() async {
        emailFocused = false
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sendOTP() async {
        emailFocused = false
        isLoading = true
        errorMessage = nil
        do {
            try await authService.sendOTP(email: email)
            onOTPSent(email)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Apple Sign-In Coordinator

@MainActor
private final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    var rawNonce: String = ""
    var onComplete: ((Result<ASAuthorization, Error>) -> Void)?
    var activeController: ASAuthorizationController?  // retain until auth completes

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        activeController = nil
        onComplete?(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        activeController = nil
        onComplete?(.failure(error))
    }
}

#Preview {
    SignInView(onOTPSent: { _ in })
        .environment(AuthService())
}
