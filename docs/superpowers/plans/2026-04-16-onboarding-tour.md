# Onboarding Tour Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a just-in-time feature tour: a 3-step coach-mark overlay on the map (fires once after onboarding) and a 1-step overlay on the Saved tab (fires once on first visit).

**Architecture:** Two self-contained overlay views (`MapTourOverlay`, `SavedTourOverlay`), each owning their own `@AppStorage` dismissal flag. Both are injected as `.overlay` modifiers — `MapTourOverlay` on `ContentView`'s `TabView`, `SavedTourOverlay` on `CollectionsView`'s `NavigationStack`. No bindings or init parameters needed on existing views.

**Tech Stack:** SwiftUI `@AppStorage`, `GeometryReader`, `Path` with `.evenOdd` fill for spotlight cutouts, `Color.brandPrimary`/`brandSecondary` brand colours, `.dmSans` custom font.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `qwip/Views/MapTourOverlay.swift` | **Create** | 3-step coach mark overlay: spotlight + tooltip card |
| `qwip/Views/SavedTourOverlay.swift` | **Create** | 1-step dim overlay for Collections tab |
| `qwip/ContentView.swift` | **Modify** | Add `MapTourOverlay` as overlay on `TabView` |
| `qwip/Views/CollectionsView.swift` | **Modify** | Add `SavedTourOverlay` as overlay on `NavigationStack` |

---

## Task 1: Create MapTourOverlay

**Files:**
- Create: `qwip/Views/MapTourOverlay.swift`

**No unit tests** — this is a pure SwiftUI overlay view. Verify visually after wiring in Task 3.

- [ ] **Step 1: Create `MapTourOverlay.swift`**

```swift
import SwiftUI

struct MapTourOverlay: View {
    @AppStorage("hasSeenMapTour") private var hasSeenMapTour = false
    @State private var step = 0

    var body: some View {
        if !hasSeenMapTour {
            GeometryReader { geo in
                ZStack {
                    spotlightMask(geo: geo)
                    tooltipCard(geo: geo)
                }
            }
            .ignoresSafeArea()
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
        }
    }

    // MARK: - Spotlight

    @ViewBuilder
    private func spotlightMask(geo: GeometryProxy) -> some View {
        if let rect = spotlightRect(geo: geo) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addEllipse(in: rect)
            }
            .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
        } else {
            Color.black.opacity(0.45)
        }
    }

    /// Returns the spotlight cutout rect for the current step, or nil for a full dim.
    private func spotlightRect(geo: GeometryProxy) -> CGRect? {
        switch step {
        case 0:
            // Circular spotlight over the pin cluster area (upper-centre of map)
            let cx = geo.size.width * 0.5
            let cy = geo.size.height * 0.3
            let r: CGFloat = 36
            return CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        default:
            // Steps 1 and 2: full dim, tooltip only
            return nil
        }
    }

    // MARK: - Tooltip card

    @ViewBuilder
    private func tooltipCard(geo: GeometryProxy) -> some View {
        let config = stepConfigs[step]

        VStack {
            if step == 0 {
                // Below spotlight — leave room for the pin area in upper 30%
                Spacer().frame(height: geo.size.height * 0.42)
            } else if step == 1 {
                // Upper area — map content below
                Spacer().frame(height: geo.size.height * 0.12)
            } else {
                // Step 2: centred
                Spacer().frame(height: geo.size.height * 0.28)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(config.emoji)
                        .font(.system(size: 22))
                    Text(config.headline)
                        .font(.dmSans(15, weight: .heavy))
                        .foregroundStyle(Color.brandSecondary)
                }

                Text(config.body)
                    .font(.dmSans(13))
                    .foregroundStyle(Color.brandSecondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .center) {
                    Button("Skip tour") {
                        withAnimation { hasSeenMapTour = true }
                    }
                    .font(.dmSans(12, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary.opacity(0.4))

                    Spacer()

                    // Progress dots
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == step
                                      ? Color.brandSecondary
                                      : Color.brandSecondary.opacity(0.3))
                                .frame(width: i == step ? 14 : 6, height: 3)
                                .animation(.easeInOut(duration: 0.2), value: step)
                        }
                    }

                    Spacer().frame(width: 12)

                    Button {
                        if step < 2 {
                            withAnimation { step += 1 }
                        } else {
                            withAnimation { hasSeenMapTour = true }
                        }
                    } label: {
                        Text(step < 2 ? "Next →" : "Got it ✓")
                            .font(.dmSans(13, weight: .black))
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.brandSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .padding(16)
            .background(Color.brandPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.brandPrimary.opacity(0.3), radius: 16, x: 0, y: 6)
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Step content

    private struct StepConfig {
        let emoji: String
        let headline: String
        let body: String
    }

    private let stepConfigs: [StepConfig] = [
        StepConfig(
            emoji: "📍",
            headline: "Explore the map",
            body: "Tap any green pin to discover a work-friendly spot near you."
        ),
        StepConfig(
            emoji: "☕",
            headline: "Spot details",
            body: "Tap a pin to see opening hours, wifi quality, noise level, and directions."
        ),
        StepConfig(
            emoji: "♥️",
            headline: "Save spots",
            body: "Tap the heart on any spot to save it. Find all your saved spots in the Saved tab below."
        ),
    ]
}
```

- [ ] **Step 2: Commit**

```bash
git add qwip/Views/MapTourOverlay.swift
git commit -m "feat: add MapTourOverlay — 3-step coach mark for map onboarding"
```

---

## Task 2: Create SavedTourOverlay

**Files:**
- Create: `qwip/Views/SavedTourOverlay.swift`

- [ ] **Step 1: Create `SavedTourOverlay.swift`**

```swift
import SwiftUI

struct SavedTourOverlay: View {
    @AppStorage("hasSeenSavedTour") private var hasSeenSavedTour = false

    var body: some View {
        if !hasSeenSavedTour {
            ZStack {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("🗂️")
                            .font(.system(size: 22))
                        Text("Collections")
                            .font(.dmSans(15, weight: .heavy))
                            .foregroundStyle(Color.brandSecondary)
                    }

                    Text("Group saved spots into themed collections — by area, vibe, or whatever works for you.")
                        .font(.dmSans(13))
                        .foregroundStyle(Color.brandSecondary.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Spacer()
                        Button {
                            withAnimation { hasSeenSavedTour = true }
                        } label: {
                            Text("Got it ✓")
                                .font(.dmSans(13, weight: .black))
                                .foregroundStyle(Color.brandPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.brandSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
                .padding(16)
                .background(Color.brandPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.brandPrimary.opacity(0.3), radius: 16, x: 0, y: 6)
                .padding(.horizontal, 24)
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add qwip/Views/SavedTourOverlay.swift
git commit -m "feat: add SavedTourOverlay — 1-step coach mark for Collections tab"
```

---

## Task 3: Wire MapTourOverlay into ContentView

**Files:**
- Modify: `qwip/ContentView.swift`

The `MapTourOverlay` is added as an `.overlay` on the `TabView` in `ContentView.body`. It sits above all tabs and the tab bar, which is required for step 3 (the tooltip references the Saved tab).

- [ ] **Step 1: Add the overlay to `ContentView.body`**

In `ContentView.swift`, find the existing `.overlay` block (the one that conditionally shows `SearchOverlay`). Add a second `.overlay` immediately after it:

```swift
// Existing overlay — keep this:
.overlay {
    if searchViewModel.isSearchActive {
        SearchOverlay()
            .transition(.opacity)
    }
}
.animation(.easeInOut(duration: 0.22), value: searchViewModel.isSearchActive)
// Add this directly after:
.overlay {
    MapTourOverlay()
}
```

- [ ] **Step 2: Build and test in Xcode**

Build the app (Cmd+B). Run on simulator (Cmd+R).

Expected behaviour on a fresh install / first launch:
- After completing the profile onboarding questions, the map appears with the `MapTourOverlay` visible
- Step 1: dark overlay with circular spotlight in upper-centre of map, tooltip below it reading "Explore the map" with progress dots showing `● ○ ○`
- Tapping "Next →" advances to step 2: full dim, tooltip reading "Spot details" with dots `○ ● ○`
- Tapping "Next →" advances to step 3: full dim, tooltip reading "Save spots" with dots `○ ○ ●` and a "Got it ✓" button
- Tapping "Got it ✓" dismisses the overlay with a fade
- "Skip tour" at any step also dismisses it
- Relaunching the app does NOT re-show the tour (flag persisted in `@AppStorage`)

To re-test from scratch: delete the app from the simulator and reinstall.

- [ ] **Step 3: Commit**

```bash
git add qwip/ContentView.swift
git commit -m "feat: wire MapTourOverlay into ContentView"
```

---

## Task 4: Wire SavedTourOverlay into CollectionsView

**Files:**
- Modify: `qwip/Views/CollectionsView.swift`

Add `SavedTourOverlay` as an overlay on the `NavigationStack` inside `CollectionsView.body`. It shows the first time the user visits the Saved tab and is already dismissed if they've already seen the map tour and come back.

- [ ] **Step 1: Add the overlay to `CollectionsView`**

In `CollectionsView.swift`, find the `NavigationStack(path: $navPath)` — it currently ends with `.background(Color.brandSecondary.ignoresSafeArea())`. Add `.overlay` immediately after `.background`:

```swift
.background(Color.brandSecondary.ignoresSafeArea())
.overlay {
    SavedTourOverlay()
}
```

The full tail of the `NavigationStack` should look like:

```swift
.navigationTitle("Saved")
.navigationBarTitleDisplayMode(.large)
.background(Color.brandSecondary.ignoresSafeArea())
.overlay {
    SavedTourOverlay()
}
.toolbar { ... }
```

- [ ] **Step 2: Build and test in Xcode**

Build the app (Cmd+B). Run on simulator (Cmd+R).

Expected behaviour:
- Complete the map tour (or skip it), then tap the Saved tab
- `SavedTourOverlay` appears: full dark dim, tooltip card reading "Collections" with the body copy and a single "Got it ✓" button
- Tapping "Got it ✓" dismisses it with a fade
- Switching away from the Saved tab and back does NOT re-show the overlay
- Relaunching the app does NOT re-show the overlay

To re-test from scratch: delete the app from the simulator and reinstall.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/CollectionsView.swift
git commit -m "feat: wire SavedTourOverlay into CollectionsView"
```
