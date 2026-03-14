import SwiftUI

struct OTPVerificationView: View {
    let email: String
    var onBack: () -> Void

    @Environment(AuthService.self) private var authService

    @State private var otpCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resendCooldown = 0

    var body: some View {
        ZStack {
            Color.brandSecondary.ignoresSafeArea()

            Circle()
                .fill(Color.brandPrimary.opacity(0.07))
                .frame(width: 320)
                .offset(x: -80, y: -340)
                .blur(radius: 40)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1.5))
                                .frame(width: 72, height: 72)
                            Image(systemName: "envelope.badge.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Color.brandPrimary)
                        }
                        .padding(.bottom, 4)

                        Text("Check your email")
                            .font(.funnelDisplay(32, weight: .bold))
                            .foregroundStyle(Color.brandPrimary)

                        Text("We sent a 6-digit code to\n\(email)")
                            .font(.dmSans(15))
                            .foregroundStyle(Color.brandPrimary.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .padding(.bottom, 44)

                    // Code input card
                    VStack(spacing: 20) {
                        TextField("000000", text: $otpCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.brandPrimary)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.brandPrimary.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(Color.brandPrimary.opacity(0.15), lineWidth: 1.5)
                                    )
                            )
                            .onChange(of: otpCode) { _, newValue in
                                if newValue.count > 6 {
                                    otpCode = String(newValue.prefix(6))
                                }
                                if otpCode.count == 6 {
                                    Task { await verify() }
                                }
                            }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.dmSans(13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        // Verify button
                        Button {
                            Task { await verify() }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.brandPrimary)
                                    .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
                                if isLoading {
                                    ProgressView().tint(Color.brandSecondary)
                                } else {
                                    HStack(spacing: 8) {
                                        Text("Verify Code")
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
                        }
                        .disabled(otpCode.count < 6 || isLoading)
                        .opacity(otpCode.count < 6 ? 0.5 : 1)

                        // Resend
                        Button {
                            Task { await resend() }
                        } label: {
                            Text(resendCooldown > 0 ? "Resend in \(resendCooldown)s" : "Resend code")
                                .font(.dmSans(14))
                                .foregroundStyle(Color.brandPrimary.opacity(resendCooldown > 0 ? 0.35 : 0.6))
                        }
                        .disabled(resendCooldown > 0)
                    }
                    .padding(20)
                    .background(glassBackground(cornerRadius: 24))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                    .padding(.horizontal, 24)

                    // Back
                    Button(action: onBack) {
                        Text("← Back to sign in")
                            .font(.dmSans(13))
                            .foregroundStyle(Color.brandPrimary.opacity(0.45))
                    }
                    .padding(.top, 24)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func verify() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.verifyOTP(email: email, token: otpCode)
            // RootView observes authService.isAuthenticated and transitions automatically
        } catch {
            errorMessage = error.localizedDescription
            otpCode = ""
        }
        isLoading = false
    }

    private func resend() async {
        errorMessage = nil
        do {
            try await authService.sendOTP(email: email)
            startResendCooldown()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startResendCooldown() {
        resendCooldown = 60
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            Task { @MainActor in
                resendCooldown -= 1
                if resendCooldown <= 0 { timer.invalidate() }
            }
        }
    }
}
