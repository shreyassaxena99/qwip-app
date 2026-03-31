import SwiftUI

struct SignInView: View {

    var onOTPSent: (String) -> Void

    @Environment(AuthService.self) private var authService

    @State private var email: String = ""
    @State private var isLoading: Bool = false
    @State private var contentOpacity: Double = 0
    @State private var contentOffset: CGFloat = 28
    @State private var errorMessage: String?
    @FocusState private var emailFocused: Bool

    var body: some View {
        ZStack {
            Color.brandSecondary.ignoresSafeArea()

            // Background decoration orbs
            Circle()
                .fill(Color.brandPrimary.opacity(0.07))
                .frame(width: 320)
                .offset(x: -80, y: -340)
                .blur(radius: 40)
                .ignoresSafeArea()

            Circle()
                .fill(Color.brandPrimary.opacity(0.04))
                .frame(width: 200)
                .offset(x: 150, y: 300)
                .blur(radius: 30)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
                                        .stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1.5)
                                )
                                .frame(width: 72, height: 72)
                                .shadow(color: Color.brandPrimary.opacity(0.08), radius: 16, x: 0, y: 4)
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Color.brandPrimary)
                        }
                        .padding(.bottom, 4)

                        Text("qwip")
                            .font(.funnelDisplay(56, weight: .bold))
                            .foregroundStyle(Color.brandPrimary)

                        (
                            Text("work your way, ")
                                .font(.funnelDisplay(18, weight: .bold))
                            +
                            Text("anywhere")
                                .font(.cormorantGaramond(21))
                                .italic()
                        )
                        .foregroundColor(Color.brandPrimary.opacity(0.5))
                    }
                    .padding(.top, 80)
                    .padding(.bottom, 44)

                    // Sign-in form card
                    VStack(spacing: 0) {
                        VStack(spacing: 10) {
                            // Apple — stays visible, no action until Developer Program enrolled
                            GlassSocialButton(
                                icon: "apple.logo",
                                label: "Continue with Apple",
                                filled: true,
                                isLoading: false,
                                action: { }
                            )
                            .opacity(0.4)

                            GlassSocialButton(
                                icon: "globe",
                                label: "Continue with Google",
                                filled: false,
                                isLoading: isLoading,
                                action: { Task { await signInWithGoogle() } }
                            )
                        }

                        // Divider
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.brandPrimary.opacity(0.1))
                                .frame(height: 1)
                            Text("or")
                                .font(.dmSans(11, weight: .bold))
                                .tracking(0.3)
                                .foregroundStyle(Color.brandPrimary.opacity(0.4))
                            Rectangle()
                                .fill(Color.brandPrimary.opacity(0.1))
                                .frame(height: 1)
                        }
                        .padding(.vertical, 20)

                        // Email field
                        VStack(spacing: 10) {
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

                            Button(action: { Task { await sendOTP() } }) {
                                ZStack {
                                    if isLoading {
                                        ProgressView()
                                            .tint(Color.brandSecondary)
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
                                .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
                            }
                            .disabled(email.isEmpty || isLoading)
                            .opacity(email.isEmpty || isLoading ? 0.7 : 1)
                        }
                    }
                    .padding(20)
                    .background(glassBackground(cornerRadius: 24))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                    .padding(.horizontal, 24)

                    // Footer
                    Text("By continuing you agree to our Terms & Privacy Policy.")
                        .font(.dmSans(10, weight: .medium))
                        .foregroundStyle(Color.brandPrimary.opacity(0.35))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .opacity(contentOpacity)
        .offset(y: contentOffset)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                contentOpacity = 1
                contentOffset = 0
            }
        }
    }

    private func signInWithGoogle() async {
        emailFocused = false
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signInWithGoogle()
            // RootView transitions automatically when isAuthenticated becomes true
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

// MARK: - Glass Social Button

struct GlassSocialButton: View {
    let icon: String
    let label: String
    let filled: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.dmSans(15, weight: .bold))
            }
            .foregroundStyle(filled ? Color.brandSecondary : Color.brandPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Group {
                    if filled {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.brandPrimary.opacity(0.2), lineWidth: 1.5)
                            )
                    }
                }
            )
            .shadow(
                color: filled ? Color.brandPrimary.opacity(0.35) : Color.brandPrimary.opacity(0.05),
                radius: filled ? 10 : 4, x: 0, y: 3
            )
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.5 : 1)
    }
}

#Preview {
    SignInView(onOTPSent: { _ in })
        .environment(AuthService())
}
