# Analytics Consent Design

**Date:** 2026-04-17
**Status:** Approved

## Problem

qwip tracks anonymous behavioral events via PostHog (spot viewed, saved, shared, directions tapped, collection spot added, sign-in errors). For a worldwide release, collecting any behavioral data — even without a user ID — without prior consent violates GDPR (EU/UK), LGPD (Brazil), and similar laws. Opted-in by default is non-compliant.

## Solution

Two-part consent system:

1. **First-launch consent sheet** — shown once after the user first reaches the main app, before any PostHog events fire.
2. **Preferences toggle** — lets users change their choice at any time.

## Consent State

`@AppStorage("analyticsConsentGiven")` stores a `Bool?`:
- `nil` — never shown (first launch). PostHog starts opted-out via `postHogConfig.optOut = true` at init.
- `true` — user accepted. Call `PostHogSDK.shared.optIn()`.
- `false` — user declined. Call `PostHogSDK.shared.optOut()`.

On subsequent launches, `qwipApp.init` reads the stored value and calls `optIn()` or `optOut()` before setup completes, so no events fire before preference is applied.

## First-Launch Sheet

**Trigger:** `.sheet` on `ContentView`, presented when `analyticsConsentGiven == nil`. Non-dismissable by drag (`interactiveDismissDisabled(true)`).

**Visual style:** Matches existing app glass/cream design — cream background, `GlassCard`-style container, branded primary button for Accept, plain text link for Decline.

**Copy:**

> **Help us improve qwip**
> We'd like to collect anonymous usage data (which spots you view, save, and share) to make the app better. No personal information is ever collected.
>
> [Accept]
> Decline

**Behaviour:**
- Accept → `PostHogSDK.shared.optIn()`, set `analyticsConsentGiven = true`, dismiss.
- Decline → `PostHogSDK.shared.optOut()`, set `analyticsConsentGiven = false`, dismiss.

**File:** New `AnalyticsConsentSheet.swift` in `qwip/Views/`.

## Preferences Toggle

Added to `PreferencesView` (in `ProfileView.swift`) inside the existing first `GlassCard`, below the Email Updates toggle with a `Divider`.

**Label:** "Analytics" / "Anonymous usage data"

**Binding:** Reads `!PostHogSDK.shared.isOptOut()`. On change: calls `optIn()` or `optOut()` and writes `analyticsConsentGiven`.

## PostHog Init Change

In `qwipApp.init`, set `postHogConfig.optOut = true` before `PostHogSDK.shared.setup(postHogConfig)`. After setup, read `analyticsConsentGiven`:
- `true` → call `optIn()`
- `false` or `nil` → leave opted out

This ensures zero events fire on first launch before the user decides.

## Files Changed

| File | Change |
|------|--------|
| `qwip/qwipApp.swift` | Set `optOut = true` at init; apply stored consent after setup |
| `qwip/Views/ProfileView.swift` | Add analytics toggle to `PreferencesView` |
| `qwip/Views/AnalyticsConsentSheet.swift` | New — first-launch consent sheet |
| `ContentView.swift` | Present `AnalyticsConsentSheet` when consent is nil |
