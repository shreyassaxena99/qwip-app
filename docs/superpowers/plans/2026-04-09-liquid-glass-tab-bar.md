# Liquid Glass Tab Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the custom `CustomBottomBar` with the native iOS 26 liquid glass `TabView`, and move the search button + expanded search UI into `MapView` as a floating overlay.

**Architecture:** Remove all `UITabBarAppearance` overrides and `.toolbar(.hidden)` suppression so iOS 26 renders its native floating glass tab bar automatically. Extract search views from `CustomBottomBar` into a new `MapSearchBar.swift`, wired into `MapView` via `.safeAreaInset(edge: .bottom)` so the search button floats above the glass tab bar.

**Tech Stack:** SwiftUI, iOS 26, `GlassEffect` (already used), `@Observable` / `@Environment`

---

### Task 1: Simplify ContentView — remove custom tab bar machinery

**Files:**
- Modify: `qwip/ContentView.swift`

- [ ] **Step 1: Replace ContentView.swift with the simplified version**

Open `qwip/ContentView.swift` and replace the entire file contents with:

```swift
import SwiftUI

struct ContentView: View {
    @State private var store = SpotStore()
    @State private var locationService = LocationService()
    @State private var savedSpotService = SavedSpotService()
    @State private var collectionService = CollectionService()
    @State private var selectedTab = 0
    @State private var searchViewModel = SearchViewModel()
    @Environment(AppRouter.self) var appRouter
    @AppStorage("appTheme") private var appTheme = "system"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Map", systemImage: "map.fill", value: 0) {
                MapView()
            }
            Tab("Saved", systemImage: "heart.fill", value: 1) {
                CollectionsView()
            }
            Tab("Profile", systemImage: "person.fill", value: 2) {
                ProfileView()
            }
        }
        .preferredColorScheme(appTheme == "dark" ? .dark : appTheme == "light" ? .light : nil)
        .tint(Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xC9/255, green: 0xB8/255, blue: 0xE0/255, alpha: 1)
                : UIColor(red: 0x1F/255, green: 0x3D/255, blue: 0x32/255, alpha: 1)
        }))
        .environment(store)
        .environment(locationService)
        .environment(savedSpotService)
        .environment(collectionService)
        .environment(searchViewModel)
        .task {
            async let s: () = savedSpotService.load()
            async let c: () = collectionService.load()
            _ = await (s, c)
        }
        .onChange(of: appRouter.pendingCollectionId) { _, id in
            if id != nil { selectedTab = 1 }
        }
        .onChange(of: searchViewModel.selectedRadius) { _, radius in
            if radius != nil { selectedTab = 0 }
        }
    }
}

#Preview {
    ContentView()
}
```

What changed vs the original:
- Removed entire `init()` block (UITabBarAppearance setup — fights iOS 26 glass rendering)
- Removed `.toolbar(.hidden, for: .tabBar)` from all three `Tab` views
- Removed `.safeAreaInset(edge: .bottom)` block containing `CustomBottomBar` and animation modifiers
- `searchViewModel` environment injection is unchanged (already on the `TabView` at line 76 of the original)

- [ ] **Step 2: Build and verify**

Build in Xcode (Cmd+B). Expected: build succeeds. The native floating glass tab bar should now appear. `CustomBottomBar` is not yet deleted — it just isn't referenced from `ContentView` anymore, so it will compile but go unused.

- [ ] **Step 3: Commit**

```bash
git add qwip/ContentView.swift
git commit -m "feat: remove custom tab bar, enable native iOS 26 liquid glass TabView"
```

---

### Task 2: Create MapSearchBar.swift — extract search views

**Files:**
- Create: `qwip/Views/MapSearchBar.swift`

This new file takes the search-related views from `CustomBottomBar.swift` and exposes them as self-contained components for use in `MapView`.

- [ ] **Step 1: Create `qwip/Views/MapSearchBar.swift`**

```swift
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Map Search Bar

struct MapSearchBar: View {
    @Environment(SearchViewModel.self) var searchViewModel
    @Environment(LocationService.self) var locationService
    @FocusState private var searchFocused: Bool

    private var searchRegion: MKCoordinateRegion {
        let center = locationService.userLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        return MKCoordinateRegion(center: center, latitudinalMeters: 10_000, longitudinalMeters: 10_000)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if searchViewModel.isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onChange(of: searchViewModel.isExpanded) { _, expanded in
            searchFocused = expanded
        }
    }

    // MARK: Collapsed

    private var collapsedContent: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    searchViewModel.isExpanded = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Search")
                        .font(.dmSans(11, weight: .black))
                        .tracking(0.3)
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .glassEffect(in: .capsule)
        }
    }

    // MARK: Expanded

    private var expandedContent: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.45))
                TextField("Search places, streets, postcodes…", text: Binding(
                    get: { searchViewModel.query },
                    set: { searchViewModel.updateQuery($0, region: searchRegion) }
                ))
                .font(.dmSans(14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                if searchViewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(Color.primary.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )

            Button("Cancel") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    searchViewModel.isExpanded = false
                    searchViewModel.query = ""
                    searchViewModel.results = []
                }
            }
            .font(.dmSans(14, weight: .semibold))
            .foregroundStyle(Color.primary)
        }
    }
}

// MARK: - Search Results Card

struct SearchResultsCard: View {
    @Environment(SearchViewModel.self) var searchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(searchViewModel.results) { place in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            searchViewModel.selectPlace(place)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.brandPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.dmSans(13, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                if !place.formattedAddress.isEmpty {
                                    Text(place.formattedAddress)
                                        .font(.dmSans(11))
                                        .foregroundStyle(Color.primary.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if place.id != searchViewModel.results.last?.id {
                        Divider()
                            .overlay(Color.primary.opacity(0.07))
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}

// MARK: - Radius Picker Card

struct RadiusPickerCard: View {
    @Environment(SearchViewModel.self) var searchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let place = searchViewModel.selectedPlace {
                Text("Spots near \(place.name)")
                    .font(.dmSans(12, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 8) {
                ForEach(SearchViewModel.radiusOptions, id: \.metres) { option in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            searchViewModel.selectRadius(option.metres)
                        }
                    } label: {
                        Text(option.label)
                            .font(.dmSans(13, weight: .bold))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: -4)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
```

- [ ] **Step 2: Build and verify**

Build in Xcode (Cmd+B). Expected: build succeeds. `MapSearchBar`, `SearchResultsCard`, and `RadiusPickerCard` are now defined here but not yet wired into `MapView` — the old definitions in `CustomBottomBar.swift` still exist, so there will be **duplicate type errors**. That's expected and resolved in Task 4.

Actually — to avoid duplicate errors during this intermediate step, skip the build here and proceed directly to Task 3 and 4 before building.

- [ ] **Step 3: Continue to Task 3 before building**

---

### Task 3: Wire search overlay into MapView

**Files:**
- Modify: `qwip/Views/MapView.swift`

Two changes: (1) add the search overlay via `.safeAreaInset`, (2) fix `loadingOverlay` bottom padding which was tuned for the old custom bar height.

- [ ] **Step 1: Add `.safeAreaInset` with search overlay to MapView's body**

In `MapView.swift`, locate the `var body: some View {` computed property. The body is a `ZStack(alignment: .top)` followed by `.task`, `.onChange`, `.sheet`, `.alert` modifiers. Add `.safeAreaInset(edge: .bottom, spacing: 0)` immediately after the closing brace of the `ZStack` block, before `.task`:

```swift
var body: some View {
    ZStack(alignment: .top) {
        mapLayer
        filterBarOverlay
        mapControlsOverlay
        selectedSpotPreview
        if store.isLoading && store.spots.isEmpty {
            loadingOverlay
        }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        VStack(spacing: 0) {
            if searchViewModel.isExpanded {
                if searchViewModel.selectedPlace != nil && searchViewModel.selectedRadius == nil {
                    RadiusPickerCard()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if !searchViewModel.results.isEmpty {
                    SearchResultsCard()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            MapSearchBar()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: searchViewModel.isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.results.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.selectedPlace?.id)
    }
    .task {
        // ... existing task content unchanged
```

- [ ] **Step 2: Fix `loadingOverlay` bottom padding**

In `MapView.swift`, find the `loadingOverlay` computed property (around line 510). Change `.padding(.bottom, 110)` to `.padding(.bottom, 24)`:

```swift
private var loadingOverlay: some View {
    VStack {
        Spacer()
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.brandSecondary)
            Text("Loading spots…")
                .font(.dmSans(13, weight: .semibold))
                .foregroundStyle(Color.brandSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.brandPrimary.opacity(0.92))
        .clipShape(Capsule())
        .shadow(color: Color.brandPrimary.opacity(0.3), radius: 12, x: 0, y: 4)
        .padding(.bottom, 24)
    }
}
```

The old `110` was hand-tuned for the custom bar height. With `.safeAreaInset` the ZStack's bottom boundary is already above the search bar, so `24` gives a comfortable gap.

- [ ] **Step 3: Continue to Task 4 before building**

---

### Task 4: Delete CustomBottomBar.swift and verify build

**Files:**
- Delete: `qwip/Views/CustomBottomBar.swift`

`SearchResultsCard` and `RadiusPickerCard` now live in `MapSearchBar.swift`. `CustomBottomBar` itself is no longer referenced anywhere.

- [ ] **Step 1: Delete `CustomBottomBar.swift`**

```bash
rm qwip/Views/CustomBottomBar.swift
```

Xcode uses `PBXFileSystemSynchronizedRootGroup` — it auto-detects the deletion, no `.pbxproj` edit needed.

- [ ] **Step 2: Build and verify**

Build in Xcode (Cmd+B). Expected: build succeeds with no errors. If there are "use of unresolved identifier" errors, check that `SearchResultsCard`, `RadiusPickerCard`, and `MapSearchBar` are defined in `MapSearchBar.swift` and that the file is inside the `qwip/Views/` folder (which is auto-synced).

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/MapSearchBar.swift qwip/Views/MapView.swift
git rm qwip/Views/CustomBottomBar.swift
git commit -m "feat: move search into MapView overlay, use native liquid glass tab bar"
```
