# Design: Onboarding Flow + PostHog Event Tracking

**Date:** 2026-03-30

## Overview

Three changes to the iOS app:

1. A 3-step onboarding screen that collects working style and London area preferences after a user's first login
2. A profile existence check after every successful login that gates the onboarding screen
3. PostHog event tracking for identity, spot interactions, and collection actions

---

## Change 1 — Onboarding Screen

### New file: `qwip/Views/OnboardingView.swift`

A stepped form with 3 questions, one per step. Uses the existing glass UI style (cream background `#FDFBF7`, forest green `#1f3d32`, `.ultraThinMaterial` glass card).

**Layout per step:**
- Progress bar at top: fills left-to-right, "X of 3" label alongside it
- `ABOUT YOU` uppercase section label
- Question text in large bold DM Sans
- Glass card (`glassBackground(cornerRadius: 20)`) containing option rows
- Each option row: label left, circle checkmark right — tapping selects/deselects, does not auto-advance
- Button row below card: Back (icon-only square, steps 2–3 only) + Next/Finish (fills remaining width, brandPrimary)
- "Skip this question" text link below buttons (always visible)

**Step 1 — How do you work?**
Options: `Fully remote`, `Office-based`, `Freelance / self-employed`, `Student`, `Other`
Maps to `working_style` in the API body.

**Step 2 — Where do you live in London?**
Options: `North London`, `West London`, `North West London`, `East London`, `South East London`, `South West London`, `Central London`, `Outside London`
Maps to `home_area` in the API body.

**Step 3 — Where do you work in London?**
Same options as Step 2. Maps to `work_area` in the API body.

**On Finish:**
- Call `POST /users/profile` via `UserProfileAPIClient` with `user_id` + any selected values (skipped steps send `nil`, omitted from body)
- On success or failure: call `authService.completeOnboarding()` to flip `needsOnboarding = false` and navigate to main app
- Never block navigation on API failure — fail silently

---

## Change 2 — Profile Check After Login

### New file: `qwip/Services/UserProfileAPIClient.swift`

Two methods:
- `static func fetchExists(userId: String, token: String) async -> Bool` — calls `GET /users/profile/{userId}`, returns `false` on `{"exists": false}` or any error
- `static func saveProfile(userId: String, token: String, workingStyle: String?, homeArea: String?, workArea: String?) async throws` — calls `POST /users/profile`

### Changes to `AuthService`

- Add `private(set) var needsOnboarding: Bool = false`
- In `authStateChanges` loop, capture the event type: when event is `.signedIn` or `.initialSession` and session is non-nil, call `checkOnboardingStatus()`
- `private func checkOnboardingStatus()`: calls `UserProfileAPIClient.fetchExists`, sets `needsOnboarding = !exists`
- Add `func completeOnboarding()`: sets `needsOnboarding = false`
- Add `func identify(userId: String)`: calls `PostHogSDK.shared.identify(userId, userProperties: [:])`
- Call `identify` on both `.signedIn` and `.initialSession` (so returning users on a fresh install are identified correctly)

### Changes to `RootView`

Insert one new branch between `needsDisplayName` and `isAuthenticated`:

```
showSplash → NameCollectionView (needsDisplayName) → OnboardingView (needsOnboarding) → ContentView (isAuthenticated) → SignInView
```

`OnboardingView` accesses `AuthService` via `@Environment(AuthService.self)` and calls `authService.completeOnboarding()` directly — same pattern as `NameCollectionView`. No closure needed.

---

## Change 3 — PostHog Event Tracking

### Dependency

Swift Package Manager: `https://github.com/PostHog/posthog-ios`, minimum version 3.0.0.

### Initialisation — `qwipApp.swift`

```swift
import PostHog

let config = PostHogConfig(
    apiKey: Config.postHogAPIKey,
    host: "https://eu.i.posthog.com"
)
PostHogSDK.shared.setup(config)
```

### Config key — `Config.swift`

```swift
static let postHogAPIKey = "INSERT_POSTHOG_API_KEY"
```

### Event map

All spot events use exact `Spot` model property names:
- `spot_id` → `spot.id` (or `detail.id`)
- `spot_name` → `spot.name` (or `detail.name`)
- `spot_area` → `spot.shortAddress ?? ""` (or `detail.shortAddress ?? ""`)

| Event | Location | Trigger |
|---|---|---|
| `identify` | `AuthService.authStateChanges` | `.signedIn` and `.initialSession` events — passes Supabase user UUID |
| `spot_viewed` | `SpotDetailView.onAppear` | Detail sheet appears |
| `spot_saved` | `SavedSpotService.save()` | After server confirms save (real entry replaces stub) |
| `spot_directions_tapped` | `SpotDetailView` directions button | Before `UIApplication.shared.open(url)` |
| `spot_shared` | `SpotDetailView` share button | Button tap, before share sheet presents |
| `collection_spot_added` | `SaveToCollectionSheet` Done action | Once per collection ID in the added diff |

**Note on `spot_shared`:** `ShareLink` has no tap callback in SwiftUI. The existing `ShareLink` will be replaced with a `Button` that fires the PostHog event then presents a `UIActivityViewController` via a `@State` sheet. User-visible behaviour is identical.

---

## Files Changed / Created

| File | Change |
|---|---|
| `qwip/Views/OnboardingView.swift` | **New** — 3-step onboarding form |
| `qwip/Services/UserProfileAPIClient.swift` | **New** — profile fetch + save API client |
| `qwip/Services/AuthService.swift` | Add `needsOnboarding`, profile check, `completeOnboarding()`, `identify()` |
| `qwip/Views/RootView.swift` | Add `OnboardingView` branch |
| `qwip/Views/SpotDetailView.swift` | Add `spot_viewed`, `spot_directions_tapped`, `spot_shared` events; replace ShareLink |
| `qwip/Services/SavedSpotService.swift` | Add `spot_saved` event after successful save |
| `qwip/Views/SaveToCollectionSheet.swift` | Add `collection_spot_added` event per collection in Done diff |
| `qwip/Services/Config.swift` | Add `postHogAPIKey` |
| `qwip/qwipApp.swift` | PostHog SDK init |
| `qwip.xcodeproj/project.pbxproj` | Add PostHog SPM package |
