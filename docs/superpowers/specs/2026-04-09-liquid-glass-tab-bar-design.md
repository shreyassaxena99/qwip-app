---
title: Native iOS 26 Liquid Glass Tab Bar
date: 2026-04-09
status: approved
---

## Overview

Replace the custom `CustomBottomBar` with the native iOS 26 liquid glass `TabView`. The search button and expanded search UI move into `MapView` as a floating overlay.

## Motivation

The app currently hides the native tab bar and renders its own `CustomBottomBar` via `.safeAreaInset`. iOS 26 ships a floating liquid glass tab bar by default — to get it, we just stop fighting it. The search integration (currently embedded in the bar) moves into MapView where it semantically belongs.

## Changes

### `ContentView.swift`

- **Remove `init()`** entirely. The `UITabBarAppearance` block is unnecessary and actively overrides the iOS 26 liquid glass rendering.
- **Remove `.toolbar(.hidden, for: .tabBar)`** from all three `Tab` views. The native floating glass tab bar appears automatically.
- **Remove the `.safeAreaInset(edge: .bottom)` block** containing `CustomBottomBar`, `SearchResultsCard`, and `RadiusPickerCard`. The `VStack` with `CustomBottomBar` and the `animation` modifiers tied to search state all go away.
- **Keep** `searchViewModel` `@State` and its `.environment(searchViewModel)` injection — MapView still needs it.
- **Keep** `.tint(...)` for the adaptive brand colour — this tints the selected tab item in the native glass bar.

The three `Tab` declarations remain unchanged (labels, icons, values).

### `MapView.swift`

Add a bottom overlay that contains the search button and expanded search UI. Positioned using `.safeAreaPadding(.bottom)` so it floats above the native tab bar.

**Collapsed state** (search not expanded):
- A glass capsule button — icon + "Search" label — identical in appearance to the existing button in `CustomBottomBar.collapsedContent`.
- Tapping it sets `searchViewModel.isExpanded = true`.

**Expanded state** (search expanded):
- The search text field + Cancel button row replaces the button, same layout as `CustomBottomBar.expandedContent`.
- `SearchResultsCard` and `RadiusPickerCard` appear above the search bar (stacked in a `VStack`), with the same transition animations as today.

Implementation: add `.overlay(alignment: .bottom)` on the map, containing a `VStack(spacing: 0)` with the cards and the search bar. Use `.safeAreaInset(edge: .bottom, spacing: 0)` within MapView (not ContentView) so the overlay respects the native tab bar's safe area.

### `CustomBottomBar.swift`

- Create `MapSearchBar.swift` (new file) and delete `CustomBottomBar.swift`. Xcode auto-detects both via `PBXFileSystemSynchronizedRootGroup` — no `.pbxproj` edits needed.
- Remove `CustomBottomBar` struct (tab items, `HStack` frame, material background, top border).
- Keep and rename the search views:
  - `collapsedSearchButton` (extracted from `collapsedContent`) — the glass capsule "Search" button.
  - `expandedSearchBar` (extracted from `expandedContent`) — the text field + Cancel row.
  - `SearchResultsCard` — unchanged.
  - `RadiusPickerCard` — unchanged.
- The `adaptiveTint` and `searchRegion` helpers stay (still needed by the search views).
- `@Binding var selectedTab` is removed (no longer needed).

## Layout Notes

- The search overlay sits in `MapView`'s `.safeAreaInset(edge: .bottom, spacing: 0)`, which places it between the map content and the tab bar. This mirrors the current layout without fighting the native bar.
- Bottom padding on the search button: `14pt` horizontal, enough vertical padding so it doesn't feel cramped above the floating glass bar.
- The tab bar's safe area is automatically accounted for by `.safeAreaInset` — no manual offset needed.

## What Doesn't Change

- Search logic (`SearchViewModel`, `LocationService` usage) — untouched.
- `SearchResultsCard` and `RadiusPickerCard` appearance — untouched.
- The three tab destinations (`MapView`, `CollectionsView`, `ProfileView`) — untouched.
- Brand tint colour for selected tab item — preserved via `.tint(...)` on `TabView`.
- All animations on search expand/collapse — preserved.

## Out of Scope

- Re-styling `SearchResultsCard` or `RadiusPickerCard`.
- Changing tab icons or labels.
- Any ProfileView / CollectionsView changes.
