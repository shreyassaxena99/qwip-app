# Supabase Auth Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace simulated auth in qwip with real Supabase auth — email OTP and Google Sign In — wiring up the existing UI and app-phase transitions to live auth state.

**Architecture:** A single `AuthService` (@Observable singleton) wraps all Supabase calls and publishes a `session` property. `RootView` reads `authService.isAuthenticated` to drive splash → signIn → main transitions. `ProfileView`'s existing `signOut` environment action is wired to call `authService.signOut()`. The Supabase SDK persists sessions automatically in Keychain.

**Tech Stack:** supabase-swift (v2), GoogleSignIn-iOS (v7+), SwiftUI, iOS 17+

**Apple Sign In:** Skipped — requires Apple Developer Program enrollment. The Apple button stays in the UI but does nothing for now.

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `qwip/Services/Config.swift` | Credentials constants — gitignored, never committed |
| Create | `qwip/Services/Config.example.swift` | Template for Config.swift — committed to git |
| Create | `qwip/Services/SupabaseClient.swift` | Shared `SupabaseClient` instance |
| Create | `qwip/Services/AuthService.swift` | @Observable auth singleton — session state + all auth calls |
| Create | `qwip/Views/OTPVerificationView.swift` | 6-digit OTP entry screen, auto-verifies on 6th digit |
| Modify | `qwip/qwipApp.swift` | Create AuthService, inject into env, handle Google URL, call restoreSession |
| Modify | `qwip/Views/RootView.swift` | Read AuthService from env instead of local AppPhase state |
| Modify | `qwip/Views/SignInView.swift` | Wire Google + email buttons to AuthService; show OTPVerificationView |
| Modify | `qwip/ContentView.swift` | Remove no-op `.environment(\.signOut)` that would shadow RootView's real action |
| Modify | `.gitignore` | Exclude Config.swift |

---

## Chunk 0: Supabase Dashboard Prerequisites

These manual steps must be completed before any code will work. If you followed `markdown/supabase-auth-setup.md` already, confirm each item is done.

### Task 0: Verify Supabase + Google provider config

- [ ] **Email OTP** — Supabase Dashboard → Authentication → Providers → Email:
  - Enabled: ✓
  - "Confirm email" (magic link): OFF
  - OTP: ON
  - Refresh token expiry: `2592000`

- [ ] **Google provider** — Supabase Dashboard → Authentication → Providers → Google:
  - Enabled: ✓
  - Client ID: your **Web** OAuth Client ID from Google Cloud Console
  - Client Secret: your **Web** OAuth Client Secret from Google Cloud Console

- [ ] **Google Cloud Console** — Credentials → Web OAuth Client:
  - Authorised redirect URIs includes: `https://YOUR_PROJECT_REF.supabase.co/auth/v1/callback`

No code will be written in this chunk — these are prerequisites. If any item is missing, complete it before proceeding.

---

## Chunk 1: Dependencies + Credentials

### Task 1: Add SPM Packages

**Files:** `qwip.xcodeproj` (modified via Xcode)

These must be added through Xcode — there is no CLI alternative.

- [ ] **Step 1: Add supabase-swift**

  In Xcode: File → Add Package Dependencies → paste:
  ```
  https://github.com/supabase/supabase-swift
  ```
  Version rule: **Up to Next Major** from `2.0.0`
  Add to target: `qwip`
  Product to add: `Supabase`

- [ ] **Step 2: Add GoogleSignIn-iOS**

  File → Add Package Dependencies → paste:
  ```
  https://github.com/google/GoogleSignIn-iOS
  ```
  Version rule: **Up to Next Major** from `7.0.0`
  Add to target: `qwip`
  Product to add: `GoogleSignIn`

- [ ] **Step 3: Build to confirm packages resolve**

  Product → Build (⌘B). Expected: build succeeds with no errors.

---

### Task 2: Credentials config

**Files:**
- Create: `qwip/Services/Config.swift`
- Create: `qwip/Services/Config.example.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Add Config.swift to .gitignore**

  Add to `.gitignore`:
  ```
  qwip/Services/Config.swift
  ```

- [ ] **Step 2: Create Config.example.swift (committed template)**

  Create `qwip/Services/Config.example.swift`:
  ```swift
  // Config.example.swift — committed to git as a setup guide.
  // Copy to Config.swift, fill in real values, and do NOT commit Config.swift.
  enum Config {
      static let supabaseURL = URL(string: "https://YOUR_PROJECT_REF.supabase.co")!
      static let supabaseAnonKey = "YOUR_ANON_KEY"
      static let googleIOSClientID = "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com"
  }
  ```

- [ ] **Step 3: Create Config.swift (gitignored, fill in real values)**

  Create `qwip/Services/Config.swift` with the same structure, substituting:
  - `supabaseURL`: from Supabase Dashboard → Project Settings → API → Project URL
  - `supabaseAnonKey`: from Supabase Dashboard → Project Settings → API → anon/public key
  - `googleIOSClientID`: from Google Cloud Console → Credentials → iOS OAuth Client ID

  ```swift
  // Config.swift — DO NOT COMMIT (listed in .gitignore)
  enum Config {
      static let supabaseURL = URL(string: "https://REAL_REF.supabase.co")!
      static let supabaseAnonKey = "REAL_ANON_KEY"
      static let googleIOSClientID = "REAL_IOS_CLIENT_ID.apps.googleusercontent.com"
  }
  ```

- [ ] **Step 4: Commit template + gitignore**

  ```bash
  git add .gitignore qwip/Services/Config.example.swift
  git commit -m "chore: add credentials template and gitignore for Config.swift"
  ```

---

## Chunk 2: SupabaseClient + AuthService

### Task 3: Create SupabaseClient.swift

**Files:**
- Create: `qwip/Services/SupabaseClient.swift`

- [ ] **Step 1: Create the file**

  ```swift
  import Supabase

  let supabase = SupabaseClient(
      supabaseURL: Config.supabaseURL,
      supabaseKey: Config.supabaseAnonKey
  )
  ```

  This is the single shared instance used everywhere. Import `Supabase` and reference `supabase` directly.

- [ ] **Step 2: Build**

  ⌘B. Expected: build succeeds.

---

### Task 4: Create AuthService.swift

**Files:**
- Create: `qwip/Services/AuthService.swift`

The `session` property is updated by subscribing to `supabase.auth.authStateChanges` — a streaming async sequence that fires whenever any auth event occurs (sign in, sign out, token refresh). This is more robust than manually assigning `session` after each call.

- [ ] **Step 1: Create AuthService.swift**

  ```swift
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
  ```

- [ ] **Step 2: Build**

  ⌘B. Expected: build succeeds.

- [ ] **Step 3: Commit**

  ```bash
  git add qwip/Services/SupabaseClient.swift qwip/Services/AuthService.swift
  git commit -m "feat: add SupabaseClient and AuthService with Supabase + Google auth"
  ```

---

## Chunk 3: OTPVerificationView

### Task 5: Create OTPVerificationView.swift

**Files:**
- Create: `qwip/Views/OTPVerificationView.swift`

Styled to match the existing glass/brand design. Auto-verifies when 6 digits are entered. Includes a 60-second resend cooldown.

Note: `glassBackground(cornerRadius:)` is a free function defined in `qwip/Components/SpotCard.swift` — globally available, no import needed.

- [ ] **Step 1: Create OTPVerificationView.swift**

  ```swift
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
  ```

  Note: `OTPVerificationView` does not need an `onSuccess` callback. When `verifyOTP` succeeds, `authService.session` is set via the `authStateChanges` listener, `isAuthenticated` becomes `true`, and `RootView` transitions to `.main` automatically. The sheet will be dismissed as the parent `SignInView` is replaced.

- [ ] **Step 2: Build**

  ⌘B. Expected: build succeeds.

- [ ] **Step 3: Commit**

  ```bash
  git add qwip/Views/OTPVerificationView.swift
  git commit -m "feat: add OTPVerificationView for email OTP entry"
  ```

---

## Chunk 4: Wire Up App Shell

### Task 6: Update qwipApp.swift

**Files:**
- Modify: `qwip/qwipApp.swift`

Preserve the existing font registration and tab bar appearance in `init()`. Add:
- `@State private var authService = AuthService()`
- `.environment(authService)` on RootView
- `.task { await authService.restoreSession() }` on RootView
- `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }` so Google Sign In redirects back to the app

- [ ] **Step 1: Update qwipApp.swift**

  Replace the `body` property (keep `init()` unchanged):

  ```swift
  import SwiftUI
  import CoreText
  import GoogleSignIn

  @main
  struct qwipApp: App {

      @State private var authService = AuthService()

      init() {
          // font registration — unchanged
          let fontFiles = [
              "FunnelDisplay-Regular.ttf",
              "FunnelDisplay-Bold.ttf",
              "CormorantGaramond-Italic.ttf",
              "CormorantGaramond-LightItalic.ttf",
              "DMSans-VariableFont_opsz,wght.ttf"
          ]
          for file in fontFiles {
              if let url = Bundle.main.url(forResource: file, withExtension: nil) {
                  CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
              }
          }

          // tab bar appearance — unchanged
          let normalColor  = UIColor(Color.brandSecondary.opacity(0.45))
          let selectedColor = UIColor(Color.brandSecondary)
          let item = UITabBarItemAppearance()
          item.normal.iconColor = normalColor
          item.normal.titleTextAttributes   = [.foregroundColor: normalColor]
          item.selected.iconColor = selectedColor
          item.selected.titleTextAttributes = [.foregroundColor: selectedColor]
          let bar = UITabBarAppearance()
          bar.configureWithOpaqueBackground()
          bar.backgroundColor = UIColor(Color.brandPrimary)
          bar.stackedLayoutAppearance       = item
          bar.inlineLayoutAppearance        = item
          bar.compactInlineLayoutAppearance = item
          UITabBar.appearance().standardAppearance    = bar
          UITabBar.appearance().scrollEdgeAppearance  = bar

          // Required by GoogleSignIn-iOS v7+ — must be set before the first sign-in attempt.
          GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: Config.googleIOSClientID)
      }

      var body: some Scene {
          WindowGroup {
              RootView()
                  .environment(authService)
                  .task {
                      await authService.restoreSession()
                  }
                  .onOpenURL { url in
                      GIDSignIn.sharedInstance.handle(url)
                  }
          }
      }
  }
  ```

- [ ] **Step 2: Build**

  ⌘B. Expected: build succeeds.

---

### Task 7: Update RootView.swift

**Files:**
- Modify: `qwip/Views/RootView.swift`

Replace `@State private var phase: AppPhase` with `@Environment(AuthService.self)`. Keep the 2.2s splash. Wire the `signOut` environment action to call `authService.signOut()`.

`AppPhase` enum can be removed — phase is now derived from `showSplash` + `authService.isAuthenticated`.

- [ ] **Step 1: Update RootView.swift**

  ```swift
  import SwiftUI

  struct RootView: View {
      @Environment(AuthService.self) private var authService
      @State private var showSplash = true

      var body: some View {
          ZStack {
              if showSplash {
                  SplashView()
                      .transition(.opacity)
                      .zIndex(2)
              } else if authService.isAuthenticated {
                  ContentView()
                      .environment(\.signOut) {
                          // signOut environment key type is () -> Void (synchronous).
                          // We spawn a Task and use try? to satisfy that type.
                          // On failure: authStateChanges won't fire, session stays set,
                          // user stays logged in. This is acceptable — sign-out failures
                          // are rare (network is not required for local session clearing
                          // in Supabase SDK) and a retry is as simple as tapping again.
                          Task { try? await authService.signOut() }
                      }
                      .transition(.opacity)
                      .zIndex(1)
              } else {
                  SignInView()
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
          .onAppear {
              DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                  showSplash = false
              }
          }
      }
  }
  ```

  Key changes:
  - No more `AppPhase` — remove the enum entirely
  - `SignInView` no longer takes an `onSignIn` callback
  - `ContentView` gets the real `signOut` action that calls `authService.signOut()`

- [ ] **Step 2: Build**

  ⌘B. Expected: build succeeds.

---

### Task 8: Update SignInView.swift

**Files:**
- Modify: `qwip/Views/SignInView.swift`

Remove the `onSignIn: () -> Void` parameter. Add AuthService from environment. Wire Google button and email Continue button. Show `OTPVerificationView` as a `fullScreenCover` after OTP is sent.

The Apple button stays visible but does nothing (no developer account yet).

Note: `glassBackground(cornerRadius:)` is a free function defined in `qwip/Components/SpotCard.swift` — it's globally available and does not need to be imported or redefined.

- [ ] **Step 1: Replace only the `SignInView` struct and the `#Preview` at the top/bottom of SignInView.swift**

  **Do NOT touch `GlassSocialButton`** — it stays in the file unchanged below `SignInView`.

  Replace the `SignInView` struct (everything from `struct SignInView: View {` to its closing `}`) and the `#Preview` block at the end. Leave the `// MARK: - Glass Social Button` section and `GlassSocialButton` struct exactly as they are.

  ```swift
  import SwiftUI

  struct SignInView: View {

      @Environment(AuthService.self) private var authService

      @State private var email: String = ""
      @State private var isLoading: Bool = false
      @State private var contentOpacity: Double = 0
      @State private var contentOffset: CGFloat = 28
      @State private var showOTP: Bool = false
      @State private var errorMessage: String?
      @FocusState private var emailFocused: Bool

      var body: some View {
          ZStack {
              Color.brandSecondary.ignoresSafeArea()

              // Background decoration orbs — unchanged
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

                      // Header — unchanged
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

                          // Divider — unchanged
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

                      // Footer — unchanged
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
          .fullScreenCover(isPresented: $showOTP) {
              OTPVerificationView(
                  email: email,
                  onBack: { showOTP = false }
              )
              // fullScreenCover renders in a new scene graph branch and does NOT
              // inherit the parent's environment in iOS 17. AuthService must be
              // re-injected explicitly here or OTPVerificationView will crash.
              .environment(authService)
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
              showOTP = true
          } catch {
              errorMessage = error.localizedDescription
          }
          isLoading = false
      }
  }
  ```

- [ ] **Step 2: Add a replacement `#Preview` at the bottom of SignInView.swift**

  The old `#Preview { SignInView(onSignIn: { }) }` no longer compiles — `SignInView` now takes no arguments and needs `AuthService` in the environment. Replace it with:

  ```swift
  #Preview {
      SignInView()
          .environment(AuthService())
  }
  ```

- [ ] **Step 3: Build**

  ⌘B. Expected: build succeeds. If there's a complaint about `AppPhase` being undefined elsewhere, delete the enum from `RootView.swift` — it's no longer needed.

### Task 9: Update ContentView.swift

**Files:**
- Modify: `qwip/ContentView.swift`

`ContentView` currently has `.environment(\.signOut) { }` — a no-op placeholder. This override shadows the real `signOut` closure injected by `RootView`, meaning the Profile tab's Sign Out button would silently do nothing. Remove the override so `RootView`'s action propagates down.

- [ ] **Step 1: Remove the no-op `.environment(\.signOut)` from ContentView**

  In `ContentView.swift`, find:
  ```swift
  .environment(\.signOut) {
      // handled by RootView via environment, this is a placeholder
  }
  ```
  Delete these three lines entirely. `RootView` now injects the real closure on `ContentView` directly.

- [ ] **Step 2: Build**

  ⌘B. Expected: build succeeds.

  Note: `ContentView`'s existing `#Preview { ContentView() }` will still compile. In that preview context, there's no `signOut` environment value injected, so `ProfileView`'s Sign Out button will use the `defaultValue` no-op. This is expected — previews don't need a working sign-out.

- [ ] **Step 3: Commit**

  ```bash
  git add qwip/qwipApp.swift qwip/Views/RootView.swift qwip/Views/SignInView.swift qwip/ContentView.swift
  git commit -m "feat: wire AuthService into app shell — real sign-in replaces simulation"
  ```

---

## Chunk 5: Google Sign In URL Scheme

### Task 10: Register Google URL scheme in Info.plist

Google Sign In needs a URL scheme so iOS can redirect back to the app after the OAuth web step.

- [ ] **Step 1: Find your reversed iOS Client ID**

  Your iOS Client ID looks like:
  ```
  123456789-abcdefghij.apps.googleusercontent.com
  ```
  The reversed form is:
  ```
  com.googleusercontent.apps.123456789-abcdefghij
  ```

- [ ] **Step 2: Add URL type in Xcode**

  Select the `qwip` target → Info tab → URL Types → click `+`:
  - **URL Schemes**: your reversed client ID (e.g. `com.googleusercontent.apps.123456789-abcdefghij`)
  - **Identifier**: `com.qwipuk.qwip`

  Alternatively, edit `qwip/Info.plist` XML directly. Add inside the root `<dict>`:

  ```xml
  <key>CFBundleURLTypes</key>
  <array>
      <dict>
          <key>CFBundleURLSchemes</key>
          <array>
              <string>com.googleusercontent.apps.YOUR_CLIENT_ID_PREFIX</string>
          </array>
          <key>CFBundleURLName</key>
          <string>com.qwipuk.qwip</string>
      </dict>
  </array>
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add qwip/Info.plist
  git commit -m "feat: add Google Sign In URL scheme to Info.plist"
  ```

---

## Chunk 6: Manual Testing

### Task 11: Test all flows end-to-end

- [ ] **Email OTP flow**
  1. Launch app → splash → sign-in screen
  2. Enter a real email address → tap Continue
  3. OTPVerificationView appears
  4. Check your email for the 6-digit code
  5. Enter the code → auto-verifies → app transitions to main tab bar
  6. Force-quit app → reopen → should go straight to main (session restored from Keychain)

- [ ] **Google Sign In flow**
  1. From sign-in screen, tap "Continue with Google"
  2. Google sign-in sheet appears in-app
  3. Sign in → app transitions to main tab bar

- [ ] **Sign Out flow**
  1. In app → Profile tab → tap Sign Out
  2. App transitions back to sign-in screen
  3. Session is cleared

- [ ] **Session expiry behaviour**
  - Sessions last 30 days (configured in Supabase dashboard)
  - After 30 days of no use, `restoreSession()` will return nothing and user sees sign-in

---

## Notes

**If `verifyOTP` return type causes a compiler error:** The exact return type of `supabase.auth.verifyOTP` varies between supabase-swift patch versions. If the compiler complains, check the SDK signature — it may return `AuthResponse` (with a `.session` property) or `Session` directly. Since `AuthService` uses the `authStateChanges` listener, the return value isn't needed — add `_ =` to discard it.

**If `signInWithIdToken` signature differs:** In some versions the parameter is `credentials:`, in others it's positional. Check autocomplete in Xcode.

**Apple Sign In:** Can be added later. The `signInWithApple()` method slot is already planned in the architecture; it needs `ASAuthorizationController` and the Developer Program.
