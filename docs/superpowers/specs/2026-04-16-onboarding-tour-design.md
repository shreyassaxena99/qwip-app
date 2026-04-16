# Design: Just-in-Time Onboarding Tour

**Date:** 2026-04-16

## Overview

An optional feature tour that introduces new users to qwip's core features after they complete the profile onboarding questions. The tour uses coach marks (dimmed overlay + spotlight + tooltip card) rather than abstract slides, so users see real UI while learning.

The tour is split into two independent parts:

1. **Map tour** — 3 steps, fires immediately on first entry to `ContentView`
2. **Saved tab tour** — 1 step, fires the first time the user taps the Saved tab

Both tours are skippable at any point.

---

## Part 1 — Map Tour

### Trigger

Fires once on first launch of `ContentView` when `@AppStorage("hasSeenMapTour")` is `false`. Never shown again after completion or skip.

### Placement

The overlay sits at the `ContentView` level (above `MapView`, covering the full screen including tab bar). This is required because step 3 spotlights the Saved tab icon in the tab bar.

### Steps

**Step 1 — Explore the map**
- Spotlight: ~40pt circular cutout at a hardcoded position in the upper-centre of the map (approximates where a pin cluster would appear; does not track a live pin)
- Tooltip: positioned below the spotlight
- Headline: "Explore the map"
- Body: "Tap any green pin to discover a work-friendly spot near you."

**Step 2 — Spot details**
- Spotlight: rounded-rect cutout (~`UIScreen.width × 90pt`) over the bottom spot card drawer, positioned `44pt` above the tab bar
- Tooltip: positioned above the spotlight
- Headline: "Spot details"
- Body: "Tap a card to see opening hours, wifi quality, noise level, and directions."

**Step 3 — Save spots**
- Spotlight: ~`44pt` circular cutout centred on the Saved (heart) tab icon in the tab bar
- Tooltip: positioned above the spotlight
- Headline: "Save spots"
- Body: "Tap the heart on any spot to save it. Find all your saved spots in the Saved tab."
- CTA: "Got it ✓" (instead of "Next →")

### UI Anatomy (per step)

Each step renders:
- Full-screen dark overlay (`Color.black.opacity(0.45)`) with a transparent spotlight cutout using a `Path` with `.evenOdd` fill rule
- Tooltip card in `Color.brandPrimary` with `cornerRadius: 14`, positioned above or below the spotlight depending on step
- Card header: SF symbol emoji + bold headline in `Color.brandSecondary`, `.dmSans(15, weight: .heavy)`
- Card body: secondary copy in `Color.brandSecondary.opacity(0.7)`, `.dmSans(13)`
- Footer row: "Skip tour" text link (left, `opacity(0.4)`) + progress dots (centre) + Next/Got it button (right)
- Progress dots: active dot is `14pt` wide `Color.brandSecondary`, inactive dots are `6pt` wide at `opacity(0.3)`

### Completion

- Tapping "Got it ✓" on step 3: sets `hasSeenMapTour = true`, dismisses overlay
- Tapping "Skip tour" at any step: sets `hasSeenMapTour = true`, dismisses overlay immediately

---

## Part 2 — Saved Tab Tour

### Trigger

Fires once, the first time `selectedTab` becomes `1` in `ContentView`, when `@AppStorage("hasSeenSavedTour")` is `false`. Never shown again after completion or skip.

### Placement

The overlay sits on `CollectionsView`, passed in via `@Binding<Bool> var showSavedTour`. `ContentView` owns the binding and sets it to `true` from `.onChange(of: selectedTab)`.

### Step

**Step 1 — Collections**
- Full-screen dim over `CollectionsView` (no spotlight cutout needed)
- Headline: "Collections"
- Body: "Group saved spots into themed collections — by area, vibe, or whatever works for you."
- Single "Got it ✓" button (right-aligned, no progress dots, no skip link)

### Completion

- Tapping "Got it ✓": sets `hasSeenSavedTour = true`, sets binding to `false`

---

## State

```swift
// In ContentView
@AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
@AppStorage("hasSeenSavedTour") private var hasSeenSavedTour = false
@State private var showSavedTour = false
```

`@AppStorage` persists across launches. A user who reinstalls the app starts fresh naturally (keys absent = `false`).

---

## Spotlight Implementation

Use a `Path` with `.evenOdd` fill rule to cut a transparent hole in the dark overlay:

```swift
Path { path in
    path.addRect(UIScreen.main.bounds)  // full screen
    path.addEllipse(in: spotlightRect)  // hole
}
.fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
```

Spotlight positions are hardcoded per step — no preference keys. The tab bar height (`49pt` standard) and approximate pin/card regions are stable enough for this.

---

## Files

| File | Change |
|---|---|
| `qwip/Views/MapTourOverlay.swift` | **New** — 3-step map tour overlay |
| `qwip/Views/SavedTourOverlay.swift` | **New** — 1-step saved tab tour overlay |
| `qwip/ContentView.swift` | Add `@AppStorage` flags, `showSavedTour` state, `.onChange` trigger, overlay injection |
| `qwip/Views/CollectionsView.swift` | Accept `showSavedTour: Binding<Bool>`, add `SavedTourOverlay` overlay |
