# Email Onboarding Stepper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold name collection into the email OTP flow as a second step, shown only for email sign-in users.

**Architecture:** A new `EmailOnboardingView` hosts a two-step stepper (OTP → Name). Its `fullScreenCover` is owned by `RootView` so it survives the session-set phase transition that would otherwise dismiss a cover on `SignInView`. `SignInView` fires an `onOTPSent` callback instead of presenting the cover itself. `NameCollectionView` and `OTPVerificationView` are deleted.

**Tech Stack:** SwiftUI, `@Observable` / `@Environment`, `AuthService`, Supabase auth

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Create | `qwip/Views/EmailOnboardingView.swift` | Two-step stepper: OTP step + Name step + OTPCell |
| Modify | `qwip/Views/RootView.swift` | Own the `fullScreenCover`, remove `needsDisplayName` branch |
| Modify | `qwip/Views/SignInView.swift` | Fire `onOTPSent` callback, remove old `fullScreenCover` |
| Modify | `qwip/Services/AuthService.swift` | Remove unused `needsDisplayName` computed property |
| Delete | `qwip/Views/OTPVerificationView.swift` | Absorbed into `EmailOnboardingView` |
| Delete | `qwip/Views/NameCollectionView.swift` | Replaced by name step in `EmailOnboardingView` |

---

### Task 1: Create EmailOnboardingView.swift

**Files:**
- Create: `qwip/Views/EmailOnboardingView.swift`

- [ ] **Step 1: Create the file with the full two-step stepper**

```swift
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

                VStack(spacing: 8) {
                    Text("qwip")
                        .font(.funnelDisplay(56, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)

                    Text("one last thing,")
                        .font(.funnelDisplay(18, weight: .bold))
                        .foregroundColor(Color.brandPrimary.opacity(0.5))
                }
                .padding(.top, 100)
                .padding(.bottom, 44)

                VStack(spacing: 10) {
                    Text("what's your name?")
                        .font(.cormorantGaramond(21))
                        .italic()
                        .foregroundStyle(Color.brandPrimary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)

                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($nameFocused)
                        .font(.dmSans(15, weight: .medium))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.brandPrimary.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.brandPrimary.opacity(nameFocused ? 0.3 : 0.12), lineWidth: 1.5)
                                )
                        )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.dmSans(13))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: { Task { await submit() } }) {
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
                        .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? 0.7 : 1)
                }
                .padding(20)
                .background(glassBackground(cornerRadius: 24))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 24)
            }
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
```

- [ ] **Step 2: Build in Xcode (Cmd+B) and confirm no compile errors**

Expected: build succeeds. `EmailOnboardingView`, `OTPStepView`, `NameStepView`, and `OTPCell` all compile. (The old files still exist so there's no missing symbol yet.)

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/EmailOnboardingView.swift
git commit -m "feat: add EmailOnboardingView two-step stepper (OTP + name)"
```

---

### Task 2: Update RootView.swift

**Files:**
- Modify: `qwip/Views/RootView.swift`

- [ ] **Step 1: Replace the entire file content**

```swift
import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var authService
    @State private var showSplash = true
    @State private var pendingOTPEmail: String? = nil

    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(2)
            } else if authService.needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(1)
            } else if authService.isAuthenticated {
                ContentView()
                    .environment(\.signOut) {
                        Task { try? await authService.signOut() }
                    }
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                SignInView(onOTPSent: { email in
                    pendingOTPEmail = email
                })
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showSplash)
        .animation(.easeInOut(duration: 0.45), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.45), value: authService.needsOnboarding)
        .fullScreenCover(isPresented: Binding(
            get: { pendingOTPEmail != nil },
            set: { if !$0 { pendingOTPEmail = nil } }
        )) {
            if let email = pendingOTPEmail {
                EmailOnboardingView(
                    email: email,
                    onBack: { pendingOTPEmail = nil },
                    onComplete: { pendingOTPEmail = nil }
                )
                .environment(authService)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                showSplash = false
            }
        }
    }
}
```

Key changes from the old file:
- Removed `needsDisplayName → NameCollectionView` branch
- Removed `.animation` for `needsDisplayName`
- Added `@State var pendingOTPEmail: String?`
- Added `.fullScreenCover` for `EmailOnboardingView`
- `SignInView()` now takes `onOTPSent:` callback

- [ ] **Step 2: Build in Xcode (Cmd+B)**

Expected: compiler error on `SignInView(onOTPSent:)` — `SignInView` doesn't have that parameter yet. This is expected; Task 3 fixes it.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/RootView.swift
git commit -m "feat: move email onboarding fullScreenCover to RootView"
```

---

### Task 3: Update SignInView.swift

**Files:**
- Modify: `qwip/Views/SignInView.swift`

- [ ] **Step 1: Add `onOTPSent` parameter and remove the old fullScreenCover**

Replace the entire `SignInView` struct definition (lines 3–225 of the current file) with:

```swift
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
                        Text("qwip")
                            .font(.funnelDisplay(56, weight: .bold))
                            .foregroundStyle(Color.brandPrimary)

                        VStack(spacing: 2) {
                            Text("work your way,")
                                .font(.funnelDisplay(18, weight: .bold))
                            Text("anywhere")
                                .font(.cormorantGaramond(21))
                                .italic()
                        }
                        .foregroundColor(Color.brandPrimary.opacity(0.5))
                        .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .padding(.bottom, 44)

                    // Sign-in form card
                    VStack(spacing: 0) {
                        VStack(spacing: 10) {
                            GlassSocialButton(
                                icon: "apple.logo",
                                label: "Continue with Apple",
                                filled: true,
                                isLoading: false,
                                action: { }
                            )
                            .opacity(0.4)

                            Button {
                                Task { await signInWithGoogle() }
                            } label: {
                                HStack(spacing: 10) {
                                    Text("G")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(Color(hex: "4285F4"))
                                    Text("Continue with Google")
                                        .font(.dmSans(15, weight: .bold))
                                        .foregroundStyle(Color(hex: "3c4043"))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                            }
                            .disabled(isLoading)
                            .opacity(isLoading ? 0.5 : 1)
                        }

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
```

Also update the `#Preview` at the bottom of the file:

```swift
#Preview {
    SignInView(onOTPSent: { _ in })
        .environment(AuthService())
}
```

- [ ] **Step 2: Build in Xcode (Cmd+B)**

Expected: clean build. All three new/modified files compile together. The `onOTPSent` callback wires up correctly from `RootView → SignInView`.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/SignInView.swift
git commit -m "feat: wire SignInView to fire onOTPSent callback for email flow"
```

---

### Task 4: Remove old files and clean up AuthService

**Files:**
- Delete: `qwip/Views/OTPVerificationView.swift`
- Delete: `qwip/Views/NameCollectionView.swift`
- Modify: `qwip/Services/AuthService.swift`

- [ ] **Step 1: Delete `OTPVerificationView.swift`**

```bash
rm qwip/Views/OTPVerificationView.swift
```

- [ ] **Step 2: Delete `NameCollectionView.swift`**

```bash
rm qwip/Views/NameCollectionView.swift
```

- [ ] **Step 3: Remove `needsDisplayName` from AuthService**

In `qwip/Services/AuthService.swift`, remove this computed property (currently around lines 26–29):

```swift
// REMOVE this entire property:
var needsDisplayName: Bool {
    guard isAuthenticated else { return false }
    guard session?.user.appMetadata["provider"]?.stringValue == "email" else { return false }
    return displayName == nil || displayName!.isEmpty
}
```

- [ ] **Step 4: Build in Xcode (Cmd+B)**

Expected: clean build. No references to `OTPVerificationView`, `NameCollectionView`, or `needsDisplayName` remain.

- [ ] **Step 5: Commit**

```bash
git add qwip/Services/AuthService.swift
git rm qwip/Views/OTPVerificationView.swift qwip/Views/NameCollectionView.swift
git commit -m "chore: remove OTPVerificationView, NameCollectionView, needsDisplayName"
```

---

### Task 5: Manual verification

- [ ] **Step 1: Run the app on simulator (Cmd+R)**

Sign in with email:
1. Enter a valid email address → tap Continue
2. Verify the `fullScreenCover` slides up showing the OTP step
3. Enter the 6-digit code → confirm the name step slides in from the right
4. Enter a name → tap Continue → confirm the app transitions to `ContentView`
5. Check the "← Back to sign in" button on the OTP step dismisses the cover and returns to `SignInView`

- [ ] **Step 2: Verify Google sign-in is unaffected**

Tap "Continue with Google" → complete Google auth → confirm the app goes directly to `ContentView` with no name step.

- [ ] **Step 3: Commit if any fixes were needed; otherwise done**
