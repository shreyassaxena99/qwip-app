# Analytics Consent Design

**Date:** 2026-04-17
**Status:** Approved (revised)

## Problem

qwip tracks anonymous behavioral events via PostHog. For a worldwide release, collecting any behavioral data without prior consent violates GDPR (EU/UK), LGPD (Brazil), and similar laws. Consent must be:
1. Per-user (not per-device) — if two users share a device, each makes their own choice
2. Shown before the user reaches the main app (part of the sign-up flow)
3. Changeable at any time via Preferences

## Solution

Three-part consent system:

1. **Per-user consent storage** — keyed by `"analyticsConsent_<userId>"` in UserDefaults; absent = not yet decided, `true` = accepted, `false` = declined.
2. **Consent phase in sign-in flow** — `AuthService` gains a `needsAnalyticsConsent` flag; `RootView` shows `AnalyticsConsentView` after onboarding (if any) and before `ContentView`, exactly like the existing `needsOnboarding` gate.
3. **Preferences toggle** — lets users change their choice at any time, reads/writes the same per-user key via `AuthService`.

## Consent State

Single `UserDefaults` key per user: `"analyticsConsent_<userId>"`

| Value | Meaning |
|-------|---------|
| absent (`nil`) | Never decided — show consent view |
| `true` | Accepted — call `PostHogSDK.shared.optIn()` |
| `false` | Declined — PostHog stays opted-out |

`UserDefaults.standard.object(forKey:)` returns `nil` for absent keys, distinguishing "not decided" from `false`.

## PostHog Init

`qwipApp.init` sets `postHogConfig.optOut = true` unconditionally before setup. No per-user restore logic at init (no userId available yet). `AuthService` applies the user's stored preference when the session is known.

## AuthService Changes

New property: `private(set) var needsAnalyticsConsent: Bool = false`

New private method `checkAnalyticsConsent(userId:)` — called from `authStateChanges` after `checkOnboardingStatus` and `loadProfile`:
- If no decision stored → `needsAnalyticsConsent = true`
- If decision stored → `needsAnalyticsConsent = false`; call `optIn()` if accepted

New public method `recordAnalyticsConsent(accepted: Bool)`:
- Writes decision to `"analyticsConsent_<userId>"`
- Calls `optIn()` or `optOut()`
- Sets `needsAnalyticsConsent = false`

On sign-out: reset `needsAnalyticsConsent = false`

## RootView Changes

Add `AnalyticsConsentView` branch in the ZStack between `OnboardingView` and `ContentView`:

```
showSplash → OnboardingView (if needsOnboarding) → AnalyticsConsentView (if needsAnalyticsConsent) → ContentView
```

## AnalyticsConsentView

Full-screen view (not a sheet — no drag handle, no `interactiveDismissDisabled`). Gets userId from `@Environment(AuthService.self)`. On Accept/Decline calls `authService.recordAnalyticsConsent(accepted:)`. Visual content matches the existing sheet design (shield icon, title, description, Accept button, Decline link).

## Preferences Toggle

In `PreferencesView`, reads `AnalyticsConsent.isAccepted(for: userId)` in the getter, calls `authService.recordAnalyticsConsent(accepted:)` in the setter. No `@AppStorage` — all reads/writes go through the shared helper and `AuthService`.

## AnalyticsConsent Helper

`qwip/Services/AnalyticsConsent.swift` — namespace with:
- `storageKey(for userId: String) -> String` — `"analyticsConsent_\(userId)"`
- `isDecided(for userId: String) -> Bool`
- `isAccepted(for userId: String) -> Bool`
- `record(accepted: Bool, for userId: String)` — writes to UserDefaults

## Files Changed

| File | Change |
|------|--------|
| `qwip/Services/AnalyticsConsent.swift` | Replace per-device constants with per-user helper methods |
| `qwip/Services/AuthService.swift` | Add `needsAnalyticsConsent`, `checkAnalyticsConsent`, `recordAnalyticsConsent` |
| `qwip/qwipApp.swift` | Remove per-device consent-restore logic (keep optOut=true at init) |
| `qwip/Views/AnalyticsConsentView.swift` | Rename from Sheet; full-screen, uses authService |
| `qwip/Views/AnalyticsConsentSheet.swift` | Delete (replaced by AnalyticsConsentView) |
| `qwip/Views/RootView.swift` | Add consent phase branch + animation |
| `qwip/ContentView.swift` | Remove consent sheet changes (revert to pre-implementation state) |
| `qwip/Views/ProfileView.swift` | Update toggle to use per-user storage via authService |
