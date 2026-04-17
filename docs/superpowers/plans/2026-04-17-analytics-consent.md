# Analytics Consent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GDPR-compliant analytics consent — a first-launch sheet and a Preferences toggle — so PostHog events only fire after the user explicitly opts in.

**Architecture:** PostHog is configured `optOut = true` at init, then the stored consent preference is applied immediately after setup. A one-time sheet appears in `ContentView` when consent has never been decided. A toggle in `PreferencesView` lets users change their choice at any time. Both the sheet and the toggle write to the same two `@AppStorage` keys and call PostHog's `optIn()`/`optOut()` API.

**Tech Stack:** SwiftUI, PostHog iOS SDK (`PostHogSDK.shared.optIn()`, `optOut()`, `isOptOut()`), `UserDefaults` via `@AppStorage`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `qwip/qwipApp.swift` | Modify | Start PostHog opted-out; apply stored consent on launch |
| `qwip/Views/AnalyticsConsentSheet.swift` | Create | First-launch consent bottom sheet |
| `qwip/ContentView.swift` | Modify | Present consent sheet when consent has never been decided |
| `qwip/Views/ProfileView.swift` | Modify | Add analytics toggle to `PreferencesView` |

---

## Consent State Convention

Two `UserDefaults` keys (accessed via `@AppStorage`) carry the full consent state:

| Key | Type | Meaning |
|-----|------|---------|
| `analyticsConsentDecided` | `Bool` (default `false`) | Has the user ever made a choice? |
| `analyticsConsentAccepted` | `Bool` (default `false`) | Did they accept? |

- First launch: both `false` → PostHog starts opted-out, sheet is shown.
- Accepted: `decided = true`, `accepted = true` → `optIn()` called.
- Declined: `decided = true`, `accepted = false` → `optOut()` remains in effect.

---

## Task 1: Configure PostHog to start opted-out

**Files:**
- Modify: `qwip/qwipApp.swift`

- [ ] **Step 1: Update PostHog init in `qwipApp.swift`**

Replace the existing PostHog setup block with this (lines 13–18):

```swift
// PostHog setup — start opted-out until user decides
let postHogConfig = PostHogConfig(
    apiKey: Config.postHogAPIKey,
    host: "https://eu.i.posthog.com"
)
postHogConfig.optOut = true
PostHogSDK.shared.setup(postHogConfig)

// Apply stored consent immediately after setup
let consentDecided = UserDefaults.standard.bool(forKey: "analyticsConsentDecided")
let consentAccepted = UserDefaults.standard.bool(forKey: "analyticsConsentAccepted")
if consentDecided && consentAccepted {
    PostHogSDK.shared.optIn()
}
```

- [ ] **Step 2: Verify `isOptOut()` behaviour manually**

Build and run in the simulator (Cmd+R). Open the Xcode console and add a temporary `print(PostHogSDK.shared.isOptOut())` after the setup block. Expected output on first launch: `true`. Remove the print after verifying.

- [ ] **Step 3: Commit**

```bash
git add qwip/qwipApp.swift
git commit -m "feat: configure PostHog to start opted-out until user consents"
```

---

## Task 2: Create AnalyticsConsentSheet

**Files:**
- Create: `qwip/Views/AnalyticsConsentSheet.swift`

- [ ] **Step 1: Create the file**

Create `qwip/Views/AnalyticsConsentSheet.swift` with this content:

```swift
import SwiftUI
import PostHog

struct AnalyticsConsentSheet: View {
    @AppStorage("analyticsConsentDecided") private var consentDecided = false
    @AppStorage("analyticsConsentAccepted") private var consentAccepted = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.brandPrimary.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 28) {
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
                    .padding(.top, 36)

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

                    VStack(spacing: 14) {
                        Button {
                            consentAccepted = true
                            consentDecided = true
                            PostHogSDK.shared.optIn()
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
                            consentAccepted = false
                            consentDecided = true
                            PostHogSDK.shared.optOut()
                        } label: {
                            Text("Decline")
                                .font(.dmSans(14))
                                .foregroundStyle(Color.brandPrimary.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 48)
                }
                .padding(.horizontal, 28)
            }
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .interactiveDismissDisabled(true)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Build (Cmd+B). Fix any compile errors before proceeding.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/AnalyticsConsentSheet.swift
git commit -m "feat: add AnalyticsConsentSheet for first-launch consent"
```

---

## Task 3: Present consent sheet from ContentView

**Files:**
- Modify: `qwip/ContentView.swift`

- [ ] **Step 1: Add `@AppStorage` property to `ContentView`**

After the existing `@Environment(AppRouter.self) var appRouter` line (line 27), add:

```swift
@AppStorage("analyticsConsentDecided") private var analyticsConsentDecided = false
```

- [ ] **Step 2: Add the sheet modifier**

In `ContentView.body`, add the following modifier after the existing `.onChange(of: searchViewModel.selectedRadius)` modifier (after line 98, before the closing `}`):

```swift
.sheet(isPresented: Binding(
    get: { !analyticsConsentDecided },
    set: { _ in }
)) {
    AnalyticsConsentSheet()
}
```

- [ ] **Step 3: Verify first-launch behaviour**

Build and run (Cmd+R). Sign in. The consent sheet should appear automatically over the main tab view and cannot be dismissed by dragging. Tapping Accept should dismiss it and not show it again on re-launch. Tapping Decline should also dismiss it and not show it again.

To re-test first-launch: delete the app from the simulator and reinstall.

- [ ] **Step 4: Commit**

```bash
git add qwip/ContentView.swift
git commit -m "feat: present analytics consent sheet on first launch"
```

---

## Task 4: Add analytics toggle to PreferencesView

**Files:**
- Modify: `qwip/Views/ProfileView.swift`

- [ ] **Step 1: Add `@AppStorage` and `import PostHog` to `PreferencesView`**

`PreferencesView` is a `private struct` inside `ProfileView.swift`. Add `import PostHog` at the top of the file (after the existing `import SwiftUI`).

Then inside `PreferencesView`, add two `@AppStorage` properties alongside the existing ones:

```swift
@AppStorage("analyticsConsentDecided") private var analyticsConsentDecided = false
@AppStorage("analyticsConsentAccepted") private var analyticsConsentAccepted = false
```

- [ ] **Step 2: Add the analytics toggle to the first `GlassCard`**

In `PreferencesView.body`, the first `GlassCard` currently contains only the Email Updates toggle. Add a `Divider` and the analytics toggle below it:

```swift
GlassCard {
    Toggle(isOn: Binding(
        get: { authService.emailOptIn },
        set: { newValue in
            authService.emailOptIn = newValue
            Task { try? await authService.updateProfile(emailOptIn: newValue) }
        }
    )) {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Email Updates")
                    .font(.dmSans(14, weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
                Text("New spots and local tips")
                    .font(.dmSans(12))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
            }
        } icon: {
            GlassIcon(iconName: "ic_mail", color: Color(hex: "1f3d32"))
        }
    }
    .tint(Color.brandPrimary)

    Divider().overlay(Color.brandBorder).padding(.leading, 44)

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
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Analytics")
                    .font(.dmSans(14, weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
                Text("Anonymous usage data")
                    .font(.dmSans(12))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
            }
        } icon: {
            GlassIcon(iconName: "ic_shield_check", color: Color(hex: "34C759"))
        }
    }
    .tint(Color.brandPrimary)
}
```

- [ ] **Step 3: Verify toggle behaviour**

Build and run (Cmd+R). Navigate to Profile → Preferences. The Analytics toggle should reflect the current PostHog opt state. Toggling it off should call `optOut()` and toggling it on should call `optIn()`. Add a temporary `print(PostHogSDK.shared.isOptOut())` in the setter to verify, then remove it.

- [ ] **Step 4: Commit**

```bash
git add qwip/Views/ProfileView.swift
git commit -m "feat: add analytics opt-in/out toggle to Preferences"
```

---

## Self-Review

**Spec coverage:**
- ✅ PostHog starts opted-out — Task 1
- ✅ Stored consent applied on launch — Task 1
- ✅ First-launch consent sheet — Task 2 + 3
- ✅ Non-dismissable by drag — Task 2 (`interactiveDismissDisabled`)
- ✅ Accept calls `optIn()`, sets both keys — Task 2
- ✅ Decline calls `optOut()`, sets both keys — Task 2
- ✅ Sheet only shown when `consentDecided == false` — Task 3
- ✅ Preferences toggle reads/writes PostHog state — Task 4
- ✅ Toggle keeps `@AppStorage` in sync — Task 4

**Placeholder scan:** No TBDs, TODOs, or vague steps.

**Type consistency:** `analyticsConsentDecided` and `analyticsConsentAccepted` used consistently across Tasks 1–4. `PostHogSDK.shared.optIn()` / `optOut()` called consistently.
