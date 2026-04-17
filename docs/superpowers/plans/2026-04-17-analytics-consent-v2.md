# Analytics Consent (Per-User, Signup Flow) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-device analytics consent sheet (shown over ContentView) with a per-user consent screen embedded in the sign-in flow, driven by `AuthService.needsAnalyticsConsent`.

**Architecture:** `AuthService` gains a `needsAnalyticsConsent` flag checked on every sign-in against a per-user `UserDefaults` key (`"analyticsConsent_<userId>"`). `RootView` shows `AnalyticsConsentView` — a full-screen view in the app phase ZStack — between onboarding and `ContentView`. The old per-device `@AppStorage` approach is removed from `ContentView`, `ProfileView`, and `qwipApp`. The `PreferencesView` toggle is updated to read/write via `AuthService`.

**Tech Stack:** SwiftUI, PostHog iOS SDK (`PostHogSDK.shared.optIn()`, `optOut()`), `UserDefaults`, `@Observable` (iOS 17+)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `qwip/Services/AnalyticsConsent.swift` | Modify | Replace two-constant enum with per-user helper methods; keep old constants until Task 6 removes them |
| `qwip/Services/AuthService.swift` | Modify | Add `needsAnalyticsConsent`, `checkAnalyticsConsent(userId:)`, `recordAnalyticsConsent(accepted:)` |
| `qwip/Views/AnalyticsConsentView.swift` | Create | Full-screen consent view using `authService.recordAnalyticsConsent(accepted:)` |
| `qwip/Views/RootView.swift` | Modify | Add `AnalyticsConsentView` phase between onboarding and `ContentView` |
| `qwip/qwipApp.swift` | Modify | Remove per-device consent-restore block (keep `optOut = true`) |
| `qwip/ContentView.swift` | Modify | Remove `@AppStorage` consent property and `.sheet` modifier |
| `qwip/Views/ProfileView.swift` | Modify | Update `PreferencesView` toggle to use `AuthService`; remove `@AppStorage` consent properties and `import PostHog` |
| `qwip/Views/AnalyticsConsentSheet.swift` | Delete | Replaced by `AnalyticsConsentView` |

---

## Task 1: Add per-user helpers to AnalyticsConsent.swift

**Files:**
- Modify: `qwip/Services/AnalyticsConsent.swift`

This task adds the per-user methods while keeping the two old static constants (`decided`, `accepted`) so the build stays green — they are removed in Task 6.

- [ ] **Step 1: Replace the contents of `qwip/Services/AnalyticsConsent.swift`**

```swift
import Foundation

enum AnalyticsConsentKey {
    static func storageKey(for userId: String) -> String {
        "analyticsConsent_\(userId)"
    }

    static func isDecided(for userId: String) -> Bool {
        UserDefaults.standard.object(forKey: storageKey(for: userId)) != nil
    }

    static func isAccepted(for userId: String) -> Bool {
        UserDefaults.standard.object(forKey: storageKey(for: userId)) as? Bool ?? false
    }

    static func record(accepted: Bool, for userId: String) {
        UserDefaults.standard.set(accepted, forKey: storageKey(for: userId))
    }

    // Legacy per-device constants — still referenced by code being removed in Task 6.
    static let decided = "analyticsConsentDecided"
    static let accepted = "analyticsConsentAccepted"
}
```

- [ ] **Step 2: Verify it compiles**

Build (Cmd+B). Existing references to `AnalyticsConsentKey.decided` and `AnalyticsConsentKey.accepted` still work. Fix any compile errors before proceeding.

- [ ] **Step 3: Commit**

```bash
git add qwip/Services/AnalyticsConsent.swift
git commit -m "feat: add per-user consent helpers to AnalyticsConsentKey"
```

---

## Task 2: Add consent state and methods to AuthService

**Files:**
- Modify: `qwip/Services/AuthService.swift`

- [ ] **Step 1: Add `import PostHog` to AuthService.swift**

Add after the existing imports (after line 5, `import CryptoKit`):

```swift
import PostHog
```

- [ ] **Step 2: Add `needsAnalyticsConsent` to the State section**

After `private(set) var needsOnboarding: Bool = false` (line 16), add:

```swift
private(set) var needsAnalyticsConsent: Bool = false
```

- [ ] **Step 3: Update the `session == nil` branch in `authStateChanges`**

Find (lines 36–37):
```swift
if session == nil {
    needsOnboarding = false
```

Replace with:
```swift
if session == nil {
    needsOnboarding = false
    needsAnalyticsConsent = false
```

- [ ] **Step 4: Call `checkAnalyticsConsent` after `loadProfile()`**

Find (lines 39–40):
```swift
await checkOnboardingStatus(session: session)
await loadProfile()
```

Replace with:
```swift
await checkOnboardingStatus(session: session)
await loadProfile()
checkAnalyticsConsent(userId: session.user.id.uuidString)
```

- [ ] **Step 5: Add `checkAnalyticsConsent(userId:)` private method**

Add this in the `// MARK: - Onboarding` section, after `completeOnboarding()` (after line 216):

```swift
private func checkAnalyticsConsent(userId: String) {
    guard AnalyticsConsentKey.isDecided(for: userId) else {
        needsAnalyticsConsent = true
        return
    }
    needsAnalyticsConsent = false
    if AnalyticsConsentKey.isAccepted(for: userId) {
        PostHogSDK.shared.optIn()
    }
}
```

- [ ] **Step 6: Add `recordAnalyticsConsent(accepted:)` public method**

Add immediately after `checkAnalyticsConsent(userId:)`:

```swift
func recordAnalyticsConsent(accepted: Bool) {
    guard let userId = session?.user.id.uuidString else { return }
    AnalyticsConsentKey.record(accepted: accepted, for: userId)
    needsAnalyticsConsent = false
    if accepted {
        PostHogSDK.shared.optIn()
    } else {
        PostHogSDK.shared.optOut()
    }
}
```

- [ ] **Step 7: Verify it compiles**

Build (Cmd+B). Fix any errors before proceeding.

- [ ] **Step 8: Commit**

```bash
git add qwip/Services/AuthService.swift
git commit -m "feat: add needsAnalyticsConsent, checkAnalyticsConsent, recordAnalyticsConsent to AuthService"
```

---

## Task 3: Create AnalyticsConsentView.swift

**Files:**
- Create: `qwip/Views/AnalyticsConsentView.swift`

This is a full-screen view shown as a ZStack layer in `RootView` — not a sheet. It has no drag handle, no `interactiveDismissDisabled`, and no `@AppStorage`. It calls `authService.recordAnalyticsConsent(accepted:)` which sets `needsAnalyticsConsent = false`, causing `RootView` to transition away.

- [ ] **Step 1: Create `qwip/Views/AnalyticsConsentView.swift`**

```swift
import SwiftUI

struct AnalyticsConsentView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.brandPrimary.opacity(0.07))
                    .frame(width: 80, height: 80)
                Image("ic_shield_check")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color.brandPrimary)
            }
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text("Help us improve qwip")
                    .font(.dmSans(22, weight: .black))
                    .foregroundStyle(Color.brandPrimary)
                    .multilineTextAlignment(.center)

                Text("We'd like to collect anonymous usage data — which spots you view, save, and share — to make the app better. No personal information is ever collected.")
                    .font(.dmSans(14))
                    .foregroundStyle(Color.brandPrimary.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Button {
                    authService.recordAnalyticsConsent(accepted: true)
                } label: {
                    Text("Accept")
                        .font(.dmSans(15, weight: .black))
                        .tracking(0.3)
                        .foregroundStyle(Color.brandSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    authService.recordAnalyticsConsent(accepted: false)
                } label: {
                    Text("Decline")
                        .font(.dmSans(14))
                        .foregroundStyle(Color.brandPrimary.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandSecondary.ignoresSafeArea())
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build (Cmd+B). Fix any errors before proceeding.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/AnalyticsConsentView.swift
git commit -m "feat: add AnalyticsConsentView for per-user consent in sign-in flow"
```

---

## Task 4: Add consent phase to RootView

**Files:**
- Modify: `qwip/Views/RootView.swift`

The consent view slots between `OnboardingView` and `ContentView` in the ZStack, following the exact same pattern as `needsOnboarding`.

- [ ] **Step 1: Add the `AnalyticsConsentView` branch to the ZStack**

Find (lines 14–17):
```swift
} else if authService.needsOnboarding {
    OnboardingView()
        .transition(.opacity)
        .zIndex(1)
} else if authService.isAuthenticated {
```

Replace with:
```swift
} else if authService.needsOnboarding {
    OnboardingView()
        .transition(.opacity)
        .zIndex(1)
} else if authService.needsAnalyticsConsent {
    AnalyticsConsentView()
        .transition(.opacity)
        .zIndex(1)
} else if authService.isAuthenticated {
```

- [ ] **Step 2: Add the `needsAnalyticsConsent` animation value**

Find (line 46):
```swift
.animation(.easeInOut(duration: 0.45), value: authService.needsOnboarding)
```

Add a new line immediately after it:
```swift
.animation(.easeInOut(duration: 0.45), value: authService.needsAnalyticsConsent)
```

- [ ] **Step 3: Verify it compiles**

Build (Cmd+B). Fix any errors before proceeding.

- [ ] **Step 4: Commit**

```bash
git add qwip/Views/RootView.swift
git commit -m "feat: add analytics consent phase to RootView sign-in flow"
```

---

## Task 5: Remove per-device consent from qwipApp and ContentView

**Files:**
- Modify: `qwip/qwipApp.swift`
- Modify: `qwip/ContentView.swift`

- [ ] **Step 1: Remove the per-device consent-restore block from `qwipApp.swift`**

Find and delete these lines (currently lines 21–26):
```swift
// Apply stored consent immediately after setup
let consentDecided = UserDefaults.standard.bool(forKey: AnalyticsConsentKey.decided)
let consentAccepted = UserDefaults.standard.bool(forKey: AnalyticsConsentKey.accepted)
if consentDecided && consentAccepted {
    PostHogSDK.shared.optIn()
}
```

The `postHogConfig.optOut = true` and `PostHogSDK.shared.setup(postHogConfig)` lines remain — PostHog still starts opted-out on every launch; `AuthService.checkAnalyticsConsent` now handles restoring the user's preference.

- [ ] **Step 2: Remove the consent `@AppStorage` property from `ContentView.swift`**

Find and delete this line (currently line 28):
```swift
@AppStorage(AnalyticsConsentKey.decided) private var analyticsConsentDecided = false
```

- [ ] **Step 3: Remove the consent `.sheet` modifier from `ContentView.swift`**

Find and delete these lines at the end of `ContentView.body`:
```swift
.sheet(isPresented: Binding(
    get: { !analyticsConsentDecided },
    set: { _ in }
)) {
    AnalyticsConsentSheet()
}
```

- [ ] **Step 4: Verify it compiles**

Build (Cmd+B). Fix any errors before proceeding.

- [ ] **Step 5: Commit**

```bash
git add qwip/qwipApp.swift qwip/ContentView.swift
git commit -m "refactor: remove per-device consent restore from qwipApp and ContentView"
```

---

## Task 6: Update PreferencesView toggle, delete AnalyticsConsentSheet, clean up AnalyticsConsent.swift

**Files:**
- Modify: `qwip/Views/ProfileView.swift`
- Delete: `qwip/Views/AnalyticsConsentSheet.swift`
- Modify: `qwip/Services/AnalyticsConsent.swift`

- [ ] **Step 1: Remove `import PostHog` from the top of `ProfileView.swift`**

Delete the line:
```swift
import PostHog
```

- [ ] **Step 2: Remove the `@AppStorage` consent properties from `PreferencesView`**

Find and delete these two lines (in `PreferencesView`):
```swift
@AppStorage(AnalyticsConsentKey.decided) private var analyticsConsentDecided = false
@AppStorage(AnalyticsConsentKey.accepted) private var analyticsConsentAccepted = false
```

- [ ] **Step 3: Replace the analytics toggle binding in `PreferencesView`**

Find the existing analytics toggle (the second `Toggle` in the first `GlassCard`):
```swift
Toggle(isOn: Binding(
    get: { analyticsConsentAccepted },
    set: { newValue in
        analyticsConsentAccepted = newValue
        analyticsConsentDecided = true
        if newValue {
            PostHogSDK.shared.optIn()
        } else {
            PostHogSDK.shared.optOut()
        }
    }
)) {
```

Replace with:
```swift
Toggle(isOn: Binding(
    get: {
        guard let userId = authService.session?.user.id.uuidString else { return false }
        return AnalyticsConsentKey.isAccepted(for: userId)
    },
    set: { newValue in
        authService.recordAnalyticsConsent(accepted: newValue)
    }
)) {
```

- [ ] **Step 4: Delete `AnalyticsConsentSheet.swift`**

```bash
rm qwip/Views/AnalyticsConsentSheet.swift
```

- [ ] **Step 5: Remove the legacy constants from `AnalyticsConsent.swift`**

Find and delete these lines from `AnalyticsConsent.swift`:
```swift
// Legacy per-device constants — still referenced by code being removed in Task 6.
static let decided = "analyticsConsentDecided"
static let accepted = "analyticsConsentAccepted"
```

- [ ] **Step 6: Verify it compiles**

Build (Cmd+B). There should be no remaining references to `AnalyticsConsentKey.decided` or `AnalyticsConsentKey.accepted`. Fix any errors before proceeding.

- [ ] **Step 7: Commit**

```bash
git add qwip/Views/ProfileView.swift qwip/Services/AnalyticsConsent.swift
git rm qwip/Views/AnalyticsConsentSheet.swift
git commit -m "refactor: migrate PreferencesView toggle to per-user consent, remove AnalyticsConsentSheet"
```

---

## Self-Review

**Spec coverage:**
- ✅ Per-user storage key `"analyticsConsent_<userId>"` — Task 1 (`AnalyticsConsentKey.storageKey(for:)`)
- ✅ PostHog starts opted-out unconditionally — Task 5 (kept `optOut = true`, removed restore)
- ✅ `AuthService.needsAnalyticsConsent` — Task 2
- ✅ Consent checked on sign-in — Task 2 (`checkAnalyticsConsent` called from `authStateChanges`)
- ✅ `optIn()` restored on sign-in if previously accepted — Task 2 (`checkAnalyticsConsent`)
- ✅ Reset on sign-out — Task 2 (`needsAnalyticsConsent = false` in `session == nil` branch)
- ✅ `AnalyticsConsentView` full-screen, no sheet — Task 3
- ✅ Accept/Decline calls `authService.recordAnalyticsConsent(accepted:)` — Task 3
- ✅ `RootView` shows consent view between onboarding and ContentView — Task 4
- ✅ Animated transition — Task 4
- ✅ Per-device restore removed from `qwipApp` — Task 5
- ✅ `@AppStorage` consent removed from `ContentView` — Task 5
- ✅ `AnalyticsConsentSheet` deleted — Task 6
- ✅ `PreferencesView` toggle uses per-user storage — Task 6
- ✅ `import PostHog` removed from `ProfileView` — Task 6

**Placeholder scan:** No TBDs, TODOs, or vague steps.

**Type consistency:**
- `AnalyticsConsentKey.storageKey(for:)` defined in Task 1, used in Tasks 2 and 6 ✅
- `AnalyticsConsentKey.isDecided(for:)` defined in Task 1, used in Task 2 ✅
- `AnalyticsConsentKey.isAccepted(for:)` defined in Task 1, used in Task 6 ✅
- `AnalyticsConsentKey.record(accepted:for:)` defined in Task 1, used in Task 2 ✅
- `authService.recordAnalyticsConsent(accepted:)` defined in Task 2, used in Tasks 3 and 6 ✅
- `authService.needsAnalyticsConsent` defined in Task 2, used in Task 4 ✅
- `AnalyticsConsentView` defined in Task 3, used in Task 4 ✅
