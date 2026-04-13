# Search Overlay on Current Tab — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the search frost overlay over whichever tab the user is on; only redirect to the Map tab after pressing Done.

**Architecture:** `SearchOverlay` is lifted out of `MapView` and placed as an `.overlay` on the root `TabView` in `ContentView`. The tab-switch intercept in `ContentView` is updated to stay on the current tab (rather than jumping to Map) when Search is tapped. The existing `onChange(of: searchViewModel.selectedRadius)` already redirects to Map after Done — no change needed there.

**Tech Stack:** SwiftUI, `@Observable` (`SearchViewModel`), iOS 17+

---

### Task 1: Lift SearchOverlay to ContentView and fix tab intercept

**Files:**
- Modify: `qwip/ContentView.swift`
- Modify: `qwip/Views/MapView.swift`

There is no meaningful unit test for a SwiftUI overlay placement change. Verification is manual (see step 4).

- [ ] **Step 1: Update `ContentView.swift`**

Make two changes:

**a) In `onChange(of: selectedTab)`, replace the `new == 3` branch** — change `selectedTab = 0` to `selectedTab = old` so the user stays on their current tab:

```swift
// Before
if new == 3 {
    // Intercept search bubble tap: go to Map and open overlay
    selectedTab = 0
    withAnimation(.easeInOut(duration: 0.25)) {
        searchViewModel.isSearchActive = true
    }
}

// After
if new == 3 {
    // Intercept search bubble tap: stay on current tab and open overlay
    selectedTab = old
    withAnimation(.easeInOut(duration: 0.25)) {
        searchViewModel.isSearchActive = true
    }
}
```

**b) Add a `.overlay` + `.animation` on the `TabView`** — place this immediately after the closing `}` of the `TabView { ... }` block, before `.environment(store)`:

```swift
TabView(selection: $selectedTab) {
    // ... existing tabs ...
}
.overlay {
    if searchViewModel.isSearchActive {
        SearchOverlay()
            .transition(.opacity)
    }
}
.animation(.easeInOut(duration: 0.22), value: searchViewModel.isSearchActive)
.environment(store)
// ... rest of modifiers unchanged ...
```

- [ ] **Step 2: Update `MapView.swift`**

Remove the `SearchOverlay` block and its associated animation from `MapView`'s `body`.

**a) Remove the overlay block** (lines ~123–127):

```swift
// DELETE this entire block:
if searchViewModel.isSearchActive {
    SearchOverlay()
        .transition(.opacity)
        .zIndex(10)
}
```

**b) Remove the animation modifier on the ZStack** (line ~129):

```swift
// DELETE this line:
.animation(.easeInOut(duration: 0.22), value: searchViewModel.isSearchActive)
```

The `ZStack` after these removals should read:

```swift
ZStack(alignment: .top) {
    mapLayer
    filterBarOverlay
    mapControlsOverlay
    selectedSpotPreview
    if store.isLoading && store.spots.isEmpty {
        loadingOverlay
    }
}
.task {
    // ... unchanged
```

- [ ] **Step 3: Build and verify**

Build in Xcode (Cmd+B). Fix any compile errors before proceeding.

Then manually verify the three key flows:

1. **From Saved tab → tap Search** — frost appears over the Saved tab (not the map). After selecting a location + radius and tapping Done, the app switches to Map and shows filtered results.
2. **From Profile tab → tap Search** — same as above, frost over Profile.
3. **From Map tab → tap Search** — frost appears over the map (same as before).
4. **Dismiss without searching** — tap the frost background or the ✕ button; overlay dismisses and the user is back on the tab they started from.

- [ ] **Step 4: Commit**

```bash
git add qwip/ContentView.swift qwip/Views/MapView.swift
git commit -m "feat: show search overlay on current tab, redirect to map only after Done"
```
