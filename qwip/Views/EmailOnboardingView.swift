import SwiftUI

struct EmailOnboardingView: View {
    let email: String
    var onBack: () -> Void
    var onComplete: () -> Void

    @Environment(AuthService.self) private var authService
    @State private var step: Step = .otp

    private enum Step { case otp, name }

    var body: some View {
        ZStack {
            Color.brandSecondary.ignoresSafeArea()

            Circle()
                .fill(Color.brandPrimary.opacity(0.07))
                .frame(width: 320)
                .offset(x: -80, y: -340)
                .blur(radius: 40)
                .ignoresSafeArea()

            if step == .otp {
                OTPStepView(email: email, onBack: onBack, onVerified: {
                    withAnimation(.easeInOut(duration: 0.35)) { step = .name }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                NameStepView(onComplete: onComplete)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: step)
    }
}

// MARK: - OTP Step

private struct OTPStepView: View {
    let email: String
    var onBack: () -> Void
    var onVerified: () -> Void

    @Environment(AuthService.self) private var authService

    @State private var otpCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resendCooldown = 0
    @FocusState private var isOTPFocused: Bool
    @State private var cursorVisible = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(Circle().stroke(Color.brandBorder, lineWidth: 1.5))
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

                VStack(spacing: 20) {

                    ZStack {
                        TextField("", text: $otpCode)
                            .keyboardType(.numberPad)
                            .focused($isOTPFocused)
                            .opacity(0.001)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onChange(of: otpCode) { _, newValue in
                                errorMessage = nil
                                let filtered = newValue.filter(\.isNumber)
                                let clamped = String(filtered.prefix(6))
                                if clamped != newValue { otpCode = clamped }
                                if clamped.count == 6 {
                                    Task { await verify() }
                                }
                            }

                        HStack(spacing: 8) {
                            ForEach(0..<6, id: \.self) { index in
                                OTPCell(
                                    digit: index < otpCode.count
                                        ? String(otpCode[otpCode.index(otpCode.startIndex, offsetBy: index)])
                                        : "",
                                    isActive: index == otpCode.count && isOTPFocused,
                                    cursorVisible: cursorVisible
                                )
                            }
                        }
                    }
                    .frame(height: 56)
                    .onTapGesture { isOTPFocused = true }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.dmSans(13))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

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

                Button(action: onBack) {
                    Text("← Back to sign in")
                        .font(.dmSans(13))
                        .foregroundStyle(Color.brandPrimary.opacity(0.45))
                }
                .padding(.top, 24)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            isOTPFocused = true
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                cursorVisible.toggle()
            }
        }
    }

    private func verify() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.verifyOTP(email: email, token: otpCode)
            onVerified()
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

// MARK: - Name Step

private struct NameStepView: View {
    var onComplete: () -> Void

    @Environment(AuthService.self) private var authService

    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // Header — matches OnboardingView style
                VStack(alignment: .leading, spacing: 6) {
                    Text("WELCOME")
                        .font(.dmSans(10, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.brandPrimary.opacity(0.4))
                    Text("What's your name?")
                        .font(.dmSans(26, weight: .heavy))
                        .foregroundStyle(Color.brandPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 80)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // Name field card
                VStack(spacing: 0) {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .font(.dmSans(15, weight: .medium))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(16)
                }
                .background(glassBackground(cornerRadius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.dmSans(13))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

                // Continue button
                Button(action: { Task { await submit() } }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.brandPrimary)
                            .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
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
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? 0.7 : 1)
                .padding(.top, 16)
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { nameFocused = true }
    }

    private func submit() async {
        nameFocused = false
        isLoading = true
        errorMessage = nil
        do {
            try await authService.updateProfile(displayName: name.trimmingCharacters(in: .whitespaces))
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - OTP Cell

private struct OTPCell: View {
    let digit: String
    let isActive: Bool
    let cursorVisible: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.brandPrimary.opacity(isActive ? 0.07 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isActive ? Color.brandPrimary : Color.brandPrimary.opacity(0.15),
                            lineWidth: isActive ? 2 : 1.5
                        )
                )

            if digit.isEmpty && isActive {
                Rectangle()
                    .fill(Color.brandPrimary.opacity(cursorVisible ? 0.65 : 0))
                    .frame(width: 2, height: 22)
            } else if !digit.isEmpty {
                Text(digit)
                    .font(.dmSans(22, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
            }
        }
        .frame(width: 44, height: 56)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}
