# Search Overlay on Current Tab

**Date:** 2026-04-13

## Problem

When a user taps the Search tab from Saved or Profile, the app immediately redirects them to the Map tab before showing the search overlay. This is disorienting — the screen jumps before the user has even entered anything.

## Goal

Show the search frost overlay over whichever tab the user is currently on. Only redirect to the Map tab after the user presses "Done" (i.e., selects a radius).

## Design

### Overlay placement

Move `SearchOverlay` from inside `MapView` to the `ContentView` level, applied as an `.overlay` on the `TabView`. This ensures the frost renders on top of any tab.

The overlay uses `.ultraThinMaterial` + `ignoresSafeArea()` (already the case in `SearchOverlay`), so it covers the full screen including the tab bar — full-screen frost, Option B.

### Tab switching logic (`ContentView`)

**Before:** Tapping Search (tab 3) → `selectedTab = 0` + `isSearchActive = true`  
**After:** Tapping Search (tab 3) → stay on current tab + `isSearchActive = true`

The `onChange(of: searchViewModel.selectedRadius)` block that switches to tab 0 after Done is unchanged — it still handles the Map redirect.

The guard `else if old != 3 && searchViewModel.isSearchActive { clearSearch() }` that clears search when switching tabs while the overlay is open becomes unreachable (tab bar is covered), but can stay as a safety net.

### MapView cleanup

Remove the `if searchViewModel.isSearchActive { SearchOverlay() }` block from `MapView` — the overlay now lives at `ContentView` level.

## Files Changed

| File | Change |
|------|--------|
| `qwip/ContentView.swift` | Add overlay on TabView; remove tab-0 switch on search tap |
| `qwip/Views/MapView.swift` | Remove SearchOverlay render block |

## Out of Scope

- No changes to `SearchOverlay.swift` or `SearchViewModel.swift`
- No changes to search logic, radius options, or results display
