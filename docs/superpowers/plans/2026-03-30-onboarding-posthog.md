# Onboarding Flow + PostHog Event Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3-step onboarding screen for new users, a profile existence check after every login, and PostHog event tracking throughout the app.

**Architecture:** `AuthService` gains `needsOnboarding` state set by calling `GET /users/profile/{id}` after every `signedIn`/`initialSession` event. `RootView` reacts to this flag to show `OnboardingView` before `ContentView`. PostHog is initialised once at app startup and called directly at each event site.

**Tech Stack:** Swift/SwiftUI, iOS 17+, PostHog iOS SDK (SPM ≥ 3.0.0), Supabase session tokens

**Important constraint:** Do NOT run tests via Cmd+U or `xcodebuild test` — these hang the machine. Verification is always "ask user to do Cmd+B and report errors". Only proceed to the next task after a clean build.

---

## File Map

| File | Status | Responsibility |
|---|---|---|
| `qwip/Services/UserProfileAPIClient.swift` | **New** | `GET /users/profile/{id}` and `POST /users/profile` |
| `qwip/Views/OnboardingView.swift` | **New** | 3-step onboarding form |
| `qwip/Services/AuthService.swift` | Modify | Add `needsOnboarding`, `checkOnboardingStatus()`, `completeOnboarding()`, `identify()` |
| `qwip/Views/RootView.swift` | Modify | Add `OnboardingView` branch |
| `qwip/Views/SpotDetailView.swift` | Modify | `spot_viewed`, `spot_directions_tapped`, `spot_shared` events; replace ShareLink |
| `qwip/Services/SavedSpotService.swift` | Modify | `spot_saved` event after successful save |
| `qwip/Views/SaveToCollectionSheet.swift` | Modify | `collection_spot_added` event per collection added |
| `qwip/Services/Config.swift` | Modify | Add `postHogAPIKey` |
| `qwip/qwipApp.swift` | Modify | PostHog SDK init |

---

## Task 1: Add PostHog SDK via Xcode + Config + App Init

**Files:**
- Manual Xcode action (SPM)
- Modify: `qwip/Services/Config.swift`
- Modify: `qwip/qwipApp.swift`

- [ ] **Step 1: Add PostHog via Xcode SPM**

  In Xcode: File → Add Package Dependencies → paste `https://github.com/PostHog/posthog-ios` → set minimum version to `3.0.0` → click Add Package → tick `PostHog` library → click Add to Target `qwip`.

- [ ] **Step 2: Add API key to Config.swift**

  Current `Config.swift`:
  ```swift
  enum Config {
    static let supabaseURL = ...
    static let supabaseAnonKey = ...
    static let googleIOSClientID = ...
    static let googleWebClientID = ...
  }
  ```

  Add one line inside the enum:
  ```swift
  static let postHogAPIKey = "INSERT_POSTHOG_API_KEY"
  ```

- [ ] **Step 3: Initialise PostHog in qwipApp.swift**

  Add `import PostHog` at the top of `qwip/qwipApp.swift` (after existing imports).

  Inside `init()`, at the very beginning (before the font registration block):
  ```swift
  let postHogConfig = PostHogConfig(
      apiKey: Config.postHogAPIKey,
      host: "https://eu.i.posthog.com"
  )
  PostHogSDK.shared.setup(postHogConfig)
  ```

- [ ] **Step 4: Ask user to build (Cmd+B) and confirm it compiles**

- [ ] **Step 5: Commit**
  ```bash
  git add qwip/Services/Config.swift qwip/qwipApp.swift
  git commit -m "feat: add PostHog SDK and initialise at app startup"
  ```

---

## Task 2: UserProfileAPIClient

**Files:**
- Create: `qwip/Services/UserProfileAPIClient.swift`

- [ ] **Step 1: Create the file**

  Create `qwip/Services/UserProfileAPIClient.swift` with the following content:

  ```swift
  import Foundation

  struct UserProfileAPIClient {

      private static let baseURL = "https://spotsvc.up.railway.app"

      /// Returns true if a profile exists, false if `{"exists": false}` is returned.
      /// Returns true on any network/decode error — safe default is to skip onboarding.
      static func fetchExists(userId: String, token: String) async -> Bool {
          guard let url = URL(string: "\(baseURL)/users/profile/\(userId)") else { return true }
          var request = URLRequest(url: url)
          request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          guard let (data, _) = try? await URLSession.shared.data(for: request) else { return true }
          struct NoProfileBody: Decodable { let exists: Bool }
          if let body = try? JSONDecoder().decode(NoProfileBody.self, from: data), !body.exists {
              return false
          }
          return true
      }

      /// Posts the user's profile. Throws on server errors; callers should fail silently.
      static func saveProfile(
          userId: String,
          token: String,
          workingStyle: String?,
          homeArea: String?,
          workArea: String?
      ) async throws {
          guard let url = URL(string: "\(baseURL)/users/profile") else { return }
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          var body: [String: String] = ["user_id": userId]
          if let v = workingStyle { body["working_style"] = v }
          if let v = homeArea    { body["home_area"] = v }
          if let v = workArea    { body["work_area"] = v }
          request.httpBody = try JSONEncoder().encode(body)
          let (_, response) = try await URLSession.shared.data(for: request)
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          guard (200...299).contains(status) else { throw ProfileError.saveFailed(status) }
      }
  }

  // MARK: - Errors

  enum ProfileError: LocalizedError {
      case saveFailed(Int)

      var errorDescription: String? {
          switch self {
          case .saveFailed(let code): return "Profile save failed (server error \(code))."
          }
      }
  }
  ```

- [ ] **Step 2: Ask user to build (Cmd+B) and confirm it compiles**

- [ ] **Step 3: Commit**
  ```bash
  git add qwip/Services/UserProfileAPIClient.swift
  git commit -m "feat: add UserProfileAPIClient for profile existence check and save"
  ```

---

## Task 3: AuthService — needsOnboarding + profile check + identify

**Files:**
- Modify: `qwip/Services/AuthService.swift`

- [ ] **Step 1: Add import and `needsOnboarding` property**

  Add `import PostHog` to the top of `AuthService.swift` (after existing imports).

  In the `// MARK: - State` section, after `var emailOptIn: Bool = false`, add:
  ```swift
  private(set) var needsOnboarding: Bool = false
  ```

- [ ] **Step 2: Replace the authStateChanges loop in `init()`**

  Current code in `init()`:
  ```swift
  Task { @MainActor in
      for await (_, session) in supabase.auth.authStateChanges {
          self.session = session
      }
  }
  ```

  Replace with:
  ```swift
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
  ```

- [ ] **Step 3: Add the three new methods**

  Add the following methods in a new `// MARK: - Onboarding` section after the existing `// MARK: - Sign Out` section:

  ```swift
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
  ```

- [ ] **Step 4: Ask user to build (Cmd+B) and confirm it compiles**

- [ ] **Step 5: Commit**
  ```bash
  git add qwip/Services/AuthService.swift
  git commit -m "feat: add needsOnboarding state, profile check, and PostHog identify to AuthService"
  ```

---

## Task 4: RootView — add OnboardingView branch

**Files:**
- Modify: `qwip/Views/RootView.swift`

- [ ] **Step 1: Add the OnboardingView branch**

  In `RootView.swift`, find the `else if authService.needsDisplayName` block. Insert a new branch immediately after it (between the NameCollectionView block and the ContentView block):

  Current:
  ```swift
  } else if authService.needsDisplayName {
      NameCollectionView()
          .transition(.opacity)
          .zIndex(1)
  } else if authService.isAuthenticated {
  ```

  Replace with:
  ```swift
  } else if authService.needsDisplayName {
      NameCollectionView()
          .transition(.opacity)
          .zIndex(1)
  } else if authService.needsOnboarding {
      OnboardingView()
          .transition(.opacity)
          .zIndex(1)
  } else if authService.isAuthenticated {
  ```

- [ ] **Step 2: Add the animation modifier**

  In the chain of `.animation(...)` modifiers at the bottom of the body, add:
  ```swift
  .animation(.easeInOut(duration: 0.45), value: authService.needsOnboarding)
  ```

- [ ] **Step 3: Ask user to build (Cmd+B) — expect a compile error because OnboardingView doesn't exist yet. Confirm the error is only "cannot find type 'OnboardingView'"**

- [ ] **Step 4: Commit**
  ```bash
  git add qwip/Views/RootView.swift
  git commit -m "feat: add OnboardingView branch to RootView phase logic"
  ```

---

## Task 5: OnboardingView

**Files:**
- Create: `qwip/Views/OnboardingView.swift`

- [ ] **Step 1: Create the file**

  Create `qwip/Views/OnboardingView.swift`:

  ```swift
  import SwiftUI

  struct OnboardingView: View {
      @Environment(AuthService.self) private var authService

      @State private var currentStep = 0
      @State private var workingStyle: String? = nil
      @State private var homeArea: String? = nil
      @State private var workArea: String? = nil
      @State private var isLoading = false

      private let workingStyles = [
          "Fully remote", "Office-based", "Freelance / self-employed", "Student", "Other"
      ]
      private let londonAreas = [
          "North London", "West London", "North West London", "East London",
          "South East London", "South West London", "Central London", "Outside London"
      ]
      private let questions = [
          "How do you work?",
          "Where do you live in London?",
          "Where do you work in London?"
      ]

      private var currentOptions: [String] {
          currentStep == 0 ? workingStyles : londonAreas
      }

      private var currentSelection: String? {
          switch currentStep {
          case 0: return workingStyle
          case 1: return homeArea
          default: return workArea
          }
      }

      private func setSelection(_ value: String) {
          switch currentStep {
          case 0: workingStyle = (workingStyle == value) ? nil : value
          case 1: homeArea    = (homeArea == value)    ? nil : value
          default: workArea   = (workArea == value)    ? nil : value
          }
      }

      private func advance() {
          if currentStep < 2 {
              withAnimation(.easeInOut(duration: 0.25)) { currentStep += 1 }
          } else {
              Task { await submit() }
          }
      }

      private func skip() {
          switch currentStep {
          case 0: workingStyle = nil
          case 1: homeArea = nil
          default: workArea = nil
          }
          advance()
      }

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
                      progressBar
                          .padding(.top, 20)
                          .padding(.horizontal, 24)

                      VStack(alignment: .leading, spacing: 6) {
                          Text("ABOUT YOU")
                              .font(.dmSans(10, weight: .black))
                              .tracking(1.5)
                              .foregroundStyle(Color.brandPrimary.opacity(0.4))
                          Text(questions[currentStep])
                              .font(.dmSans(26, weight: .heavy))
                              .foregroundStyle(Color.brandPrimary)
                              .fixedSize(horizontal: false, vertical: true)
                      }
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.top, 32)
                      .padding(.horizontal, 24)
                      .padding(.bottom, 20)

                      optionsCard
                          .padding(.horizontal, 24)

                      actionButtons
                          .padding(.top, 16)
                          .padding(.horizontal, 24)

                      Button(action: skip) {
                          Text("Skip this question")
                              .font(.dmSans(13, weight: .semibold))
                              .foregroundStyle(Color.brandPrimary.opacity(0.4))
                      }
                      .padding(.top, 14)
                  }
                  .padding(.bottom, 40)
              }
              .scrollBounceBehavior(.basedOnSize)
          }
      }

      // MARK: - Progress Bar

      private var progressBar: some View {
          HStack(spacing: 10) {
              Text("\(currentStep + 1) of 3")
                  .font(.dmSans(11, weight: .bold))
                  .tracking(0.5)
                  .foregroundStyle(Color.brandPrimary.opacity(0.4))
              GeometryReader { geo in
                  ZStack(alignment: .leading) {
                      RoundedRectangle(cornerRadius: 2, style: .continuous)
                          .fill(Color.brandPrimary.opacity(0.1))
                      RoundedRectangle(cornerRadius: 2, style: .continuous)
                          .fill(Color.brandPrimary)
                          .frame(width: geo.size.width * CGFloat(currentStep + 1) / 3)
                          .animation(.easeInOut(duration: 0.3), value: currentStep)
                  }
              }
              .frame(height: 4)
          }
      }

      // MARK: - Options Card

      private var optionsCard: some View {
          VStack(spacing: 0) {
              ForEach(Array(currentOptions.enumerated()), id: \.offset) { index, option in
                  if index > 0 {
                      Divider()
                          .overlay(Color.brandPrimary.opacity(0.07))
                  }
                  optionRow(option)
              }
          }
          .padding(.vertical, 4)
          .background(glassBackground(cornerRadius: 20))
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
      }

      private func optionRow(_ option: String) -> some View {
          let selected = currentSelection == option
          return Button {
              setSelection(option)
          } label: {
              HStack {
                  Text(option)
                      .font(.dmSans(14, weight: .semibold))
                      .foregroundStyle(Color.brandPrimary)
                  Spacer()
                  ZStack {
                      Circle()
                          .stroke(Color.brandPrimary.opacity(selected ? 0 : 0.2), lineWidth: 1.5)
                          .frame(width: 22, height: 22)
                      if selected {
                          Circle()
                              .fill(Color.brandPrimary)
                              .frame(width: 22, height: 22)
                          Image(systemName: "checkmark")
                              .font(.system(size: 10, weight: .bold))
                              .foregroundStyle(Color.brandSecondary)
                      }
                  }
                  .contentTransition(.symbolEffect(.replace))
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 14)
              .background(selected ? Color.brandPrimary.opacity(0.05) : Color.clear)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
      }

      // MARK: - Action Buttons

      private var actionButtons: some View {
          HStack(spacing: 10) {
              if currentStep > 0 {
                  Button {
                      withAnimation(.easeInOut(duration: 0.25)) { currentStep -= 1 }
                  } label: {
                      ZStack {
                          RoundedRectangle(cornerRadius: 14, style: .continuous)
                              .fill(Color.brandPrimary.opacity(0.05))
                              .overlay(
                                  RoundedRectangle(cornerRadius: 14, style: .continuous)
                                      .stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1.5)
                              )
                              .frame(width: 48, height: 48)
                          Image(systemName: "chevron.left")
                              .font(.system(size: 14, weight: .bold))
                              .foregroundStyle(Color.brandPrimary.opacity(0.6))
                      }
                  }
                  .buttonStyle(.plain)
              }

              Button {
                  advance()
              } label: {
                  ZStack {
                      RoundedRectangle(cornerRadius: 14, style: .continuous)
                          .fill(Color.brandPrimary)
                          .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
                      if isLoading {
                          ProgressView().tint(Color.brandSecondary)
                      } else {
                          HStack(spacing: 8) {
                              Text(currentStep < 2 ? "Next" : "Finish")
                                  .font(.dmSans(15, weight: .black))
                                  .tracking(0.3)
                              Image(systemName: currentStep < 2 ? "arrow.right" : "checkmark")
                                  .font(.system(size: 13, weight: .bold))
                          }
                          .foregroundStyle(Color.brandSecondary)
                      }
                  }
                  .frame(maxWidth: .infinity)
                  .frame(height: 48)
              }
              .buttonStyle(.plain)
              .disabled(isLoading)
          }
      }

      // MARK: - Submit

      private func submit() async {
          isLoading = true
          if let session = authService.session {
              try? await UserProfileAPIClient.saveProfile(
                  userId: session.user.id.uuidString,
                  token: session.accessToken,
                  workingStyle: workingStyle,
                  homeArea: homeArea,
                  workArea: workArea
              )
          }
          authService.completeOnboarding()
      }
  }
  ```

- [ ] **Step 2: Ask user to build (Cmd+B) and confirm it compiles cleanly**

- [ ] **Step 3: Manual smoke test**

  Ask user to:
  1. Run the app in Simulator
  2. Sign in with a new email (one that has never completed onboarding)
  3. Verify the onboarding screen appears after OTP verification
  4. Tap through all 3 steps selecting options
  5. Tap Finish — verify it navigates to the main app
  6. Sign out and sign back in — verify onboarding does NOT appear again (profile now exists)

- [ ] **Step 4: Commit**
  ```bash
  git add qwip/Views/OnboardingView.swift
  git commit -m "feat: add OnboardingView 3-step onboarding form"
  ```

---

## Task 6: SpotDetailView — PostHog events + ShareLink replacement

**Files:**
- Modify: `qwip/Views/SpotDetailView.swift`

- [ ] **Step 1: Add import and share sheet state**

  Add `import PostHog` at the top of `SpotDetailView.swift` (after existing imports).

  In `SpotDetailView`, after `@State private var showingSaveSheet = false`, add:
  ```swift
  @State private var showingShareSheet = false
  ```

- [ ] **Step 2: Add `spot_viewed` on appear**

  The `body` property contains a `NavigationStack`. Add `.onAppear` to the `ScrollView` inside it:

  Find:
  ```swift
  ScrollView {
      VStack(alignment: .leading, spacing: 0) {
  ```

  Add after the closing `}` of `ScrollView` (before `.background`):
  ```swift
  .onAppear {
      PostHogSDK.shared.capture("spot_viewed", properties: [
          "spot_id": detail.id,
          "spot_name": detail.name,
          "spot_area": detail.shortAddress ?? ""
      ])
  }
  ```

- [ ] **Step 3: Add `spot_shared` — add share sheet and replace ShareLink**

  Add the share sheet presenter type at the bottom of `SpotDetailView.swift`, after the closing `}` of `SpotDetailView` and before `TagChip`:

  ```swift
  // MARK: - Share Sheet

  private struct ShareSheet: UIViewControllerRepresentable {
      let items: [Any]
      func makeUIViewController(context: Context) -> UIActivityViewController {
          UIActivityViewController(activityItems: items, applicationActivities: nil)
      }
      func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
  }
  ```

  In the `actionsRow` computed property, find the `ShareLink` block:
  ```swift
  // Share
  ShareLink(item: shareText) {
      VStack(spacing: 7) {
          Image(systemName: "square.and.arrow.up")
              ...
      }
      ...
  }
  .buttonStyle(.plain)
  ```

  Replace it entirely with:
  ```swift
  // Share
  Button {
      PostHogSDK.shared.capture("spot_shared", properties: [
          "spot_id": detail.id,
          "spot_name": detail.name,
          "spot_area": detail.shortAddress ?? ""
      ])
      showingShareSheet = true
  } label: {
      VStack(spacing: 7) {
          Image(systemName: "square.and.arrow.up")
              .font(.system(size: 22, weight: .semibold))
              .foregroundStyle(Color.brandPrimary)
          Text("Share")
              .font(.dmSans(12, weight: .bold))
              .foregroundStyle(Color.brandPrimary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .background(glassBackground(cornerRadius: 16))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  ```

  Then find the existing `.sheet(isPresented: $showingSaveSheet)` and add a second sheet for sharing directly after it:
  ```swift
  .sheet(isPresented: $showingShareSheet) {
      ShareSheet(items: [shareText])
          .presentationDetents([.medium, .large])
  }
  ```

- [ ] **Step 4: Add `spot_directions_tapped`**

  In the Directions button action, find:
  ```swift
  Button {
      var urlString = "maps://?daddr=\(detail.latitude),\(detail.longitude)&dirflg=d"
      if let loc = locationService.userLocation {
          urlString += "&saddr=\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
      }
      if let url = URL(string: urlString) { UIApplication.shared.open(url) }
  } label: {
  ```

  Replace the action body with:
  ```swift
  Button {
      PostHogSDK.shared.capture("spot_directions_tapped", properties: [
          "spot_id": detail.id,
          "spot_name": detail.name,
          "spot_area": detail.shortAddress ?? ""
      ])
      var urlString = "maps://?daddr=\(detail.latitude),\(detail.longitude)&dirflg=d"
      if let loc = locationService.userLocation {
          urlString += "&saddr=\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
      }
      if let url = URL(string: urlString) { UIApplication.shared.open(url) }
  } label: {
  ```

- [ ] **Step 5: Ask user to build (Cmd+B) and confirm it compiles cleanly**

- [ ] **Step 6: Commit**
  ```bash
  git add qwip/Views/SpotDetailView.swift
  git commit -m "feat: add spot_viewed, spot_directions_tapped, spot_shared PostHog events"
  ```

---

## Task 7: SavedSpotService — spot_saved event

**Files:**
- Modify: `qwip/Services/SavedSpotService.swift`

- [ ] **Step 1: Add import**

  Add `import PostHog` at the top of `SavedSpotService.swift` (after existing imports).

- [ ] **Step 2: Fire event after successful save**

  In the `save(spot:collectionIds:)` method, find the block where the real server entry is swapped in:
  ```swift
  let real = try await SavedSpotAPIClient.shared.saveSpot(spotId: spot.id, collectionIds: collectionIds)
  if let index = savedEntries.firstIndex(where: { $0.id == stub.id }) {
      savedEntries[index] = real
  }
  ```

  Add the PostHog capture immediately after `savedEntries[index] = real`:
  ```swift
  let real = try await SavedSpotAPIClient.shared.saveSpot(spotId: spot.id, collectionIds: collectionIds)
  if let index = savedEntries.firstIndex(where: { $0.id == stub.id }) {
      savedEntries[index] = real
  }
  PostHogSDK.shared.capture("spot_saved", properties: [
      "spot_id": spot.id,
      "spot_name": spot.name,
      "spot_area": spot.shortAddress ?? ""
  ])
  ```

- [ ] **Step 3: Ask user to build (Cmd+B) and confirm it compiles cleanly**

- [ ] **Step 4: Commit**
  ```bash
  git add qwip/Services/SavedSpotService.swift
  git commit -m "feat: add spot_saved PostHog event after successful save"
  ```

---

## Task 8: SaveToCollectionSheet — collection_spot_added event

**Files:**
- Modify: `qwip/Views/SaveToCollectionSheet.swift`

- [ ] **Step 1: Add import**

  Add `import PostHog` at the top of `SaveToCollectionSheet.swift` (after existing imports).

- [ ] **Step 2: Fire events in `confirm()`**

  The `confirm()` method has two branches: `wasAlreadySaved` (spot already saved, just updating collections) and the new-save path. Both need `collection_spot_added` events.

  Find the `wasAlreadySaved` branch:
  ```swift
  let added = selectedIds.subtracting(original)
  let removed = original.subtracting(selectedIds)
  for id in added {
      _ = try await collectionService.addSpot(spotId: spot.id, toCollection: id)
  }
  ```

  Replace with:
  ```swift
  let added = selectedIds.subtracting(original)
  let removed = original.subtracting(selectedIds)
  for id in added {
      _ = try await collectionService.addSpot(spotId: spot.id, toCollection: id)
      PostHogSDK.shared.capture("collection_spot_added", properties: [
          "spot_id": spot.id,
          "spot_name": spot.name,
          "spot_area": spot.shortAddress ?? "",
          "collection_id": id
      ])
  }
  ```

  Find the new-save branch:
  ```swift
  } else {
      try await savedSpotService.save(spot: spot, collectionIds: Array(selectedIds))
  }
  ```

  Replace with:
  ```swift
  } else {
      try await savedSpotService.save(spot: spot, collectionIds: Array(selectedIds))
      for id in selectedIds {
          PostHogSDK.shared.capture("collection_spot_added", properties: [
              "spot_id": spot.id,
              "spot_name": spot.name,
              "spot_area": spot.shortAddress ?? "",
              "collection_id": id
          ])
      }
  }
  ```

- [ ] **Step 3: Ask user to build (Cmd+B) and confirm it compiles cleanly**

- [ ] **Step 4: Commit**
  ```bash
  git add qwip/Views/SaveToCollectionSheet.swift
  git commit -m "feat: add collection_spot_added PostHog events in SaveToCollectionSheet"
  ```

---

## Done

All tasks complete. The user should add their PostHog API key to `Config.swift` at `static let postHogAPIKey`.

**Manual verification checklist:**
- [ ] New user (OTP) → onboarding screen appears → complete → lands on main app → sign out → sign in again → onboarding does NOT appear
- [ ] New user (Google) → onboarding screen appears
- [ ] Existing user → onboarding skipped, lands on main app directly
- [ ] Open a spot → `spot_viewed` appears in PostHog Live Events
- [ ] Tap Directions → `spot_directions_tapped` appears
- [ ] Tap Share → share sheet appears, `spot_shared` appears in PostHog
- [ ] Save a spot → `spot_saved` appears in PostHog
- [ ] Add spot to a collection → `collection_spot_added` appears with `collection_id`
- [ ] PostHog user identity shows as Supabase UUID after login
