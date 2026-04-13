# Search Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bottom-anchored search bar in MapView with a liquid-glass search bubble in the tab bar that opens a frosted full-map overlay with a top-sliding input panel, location suggestions, and radius picker.

**Architecture:** A `.search`-role `Tab` in `ContentView` gives iOS 26 the signal to render a separate glass bubble; tapping it is intercepted to switch to Map + set `searchViewModel.isSearchActive = true`. `SearchOverlay` is a new ZStack layer inside `MapView` that owns the frost, input panel, results list, and radius card. `MapSearchBar.swift` is deleted.

**Tech Stack:** SwiftUI, MapKit (MKLocalSearch — unchanged), iOS 26 liquid glass TabView

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Modify | `qwip/Services/SearchViewModel.swift` | Replace `isExpanded` with `isSearchActive`; add `editPlace()` |
| Modify | `qwip/ContentView.swift` | Add `.search` Tab; intercept tap in `onChange` |
| Create | `qwip/Views/SearchOverlay.swift` | Frost overlay, input panel, results list, radius card |
| Modify | `qwip/Views/MapView.swift` | Remove `safeAreaInset` search bar; add `SearchOverlay` to ZStack |
| Delete | `qwip/Views/MapSearchBar.swift` | No longer needed |

---

## Task 1: Update SearchViewModel

**Files:**
- Modify: `qwip/Services/SearchViewModel.swift`

- [ ] **Step 1: Replace `isExpanded` with `isSearchActive` and add `editPlace()`**

Replace the entire file content:

```swift
import Foundation
import MapKit
import Observation

@Observable
final class SearchViewModel {
    var query: String = ""
    var results: [Place] = []
    var isSearching: Bool = false
    var isSearchActive: Bool = false
    var selectedPlace: Place? = nil
    var selectedRadius: Double? = nil  // metres

    static let radiusOptions: [(label: String, metres: Double)] = [
        ("¼ mi", 402),
        ("½ mi", 805),
        ("1 mi", 1609),
        ("3 mi", 4828)
    ]

    private var searchTask: Task<Void, Never>? = nil

    /// Call on every keystroke. Cancels any in-flight search and debounces 300 ms.
    func updateQuery(_ newQuery: String, region: MKCoordinateRegion) {
        query = newQuery
        searchTask?.cancel()
        guard !newQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await search(query: newQuery, region: region)
        }
    }

    @MainActor
    private func search(query: String, region: MKCoordinateRegion) async {
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = [.address, .pointOfInterest]
        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.map { Place(from: $0) }
        } catch {
            results = []
        }
        isSearching = false
    }

    func selectPlace(_ place: Place) {
        selectedPlace = place
        selectedRadius = nil
        results = []
        query = ""
    }

    /// Resets back to the location input step, keeping isSearchActive true.
    func editPlace() {
        selectedPlace = nil
        selectedRadius = nil
        results = []
        query = ""
    }

    func selectRadius(_ metres: Double) {
        selectedRadius = metres
        isSearchActive = false
    }

    func clearSearch() {
        searchTask?.cancel()
        query = ""
        results = []
        isSearching = false
        isSearchActive = false
        selectedPlace = nil
        selectedRadius = nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add qwip/Services/SearchViewModel.swift
git commit -m "refactor: replace isExpanded with isSearchActive in SearchViewModel, add editPlace()"
```

---

## Task 2: Update ContentView — add search Tab and intercept logic

**Files:**
- Modify: `qwip/ContentView.swift`

- [ ] **Step 1: Add the `.search` role Tab and update the `onChange` handler**

Replace the entire file content:

```swift
import SwiftUI

struct ContentView: View {
    init() {
        let item = UITabBarItemAppearance(style: .stacked)
        item.selected.iconColor = .label
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.label]

        let appearance = UITabBarAppearance()
        appearance.stackedLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    @State private var store = SpotStore()
    @State private var locationService = LocationService()
    @State private var savedSpotService = SavedSpotService()
    @State private var collectionService = CollectionService()
    @State private var selectedTab = 0
    @State private var searchViewModel = SearchViewModel()
    @Environment(AppRouter.self) var appRouter

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
            Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                EmptyView()
            }
        }
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
        .onChange(of: selectedTab) { old, new in
            guard new != old else { return }
            if new == 3 {
                // Intercept search bubble tap: go to Map and open overlay
                selectedTab = 0
                withAnimation(.easeInOut(duration: 0.25)) {
                    searchViewModel.isSearchActive = true
                }
            } else if old != 3 && searchViewModel.isSearchActive {
                // Navigated to another tab while search was open — dismiss
                withAnimation(.easeInOut(duration: 0.2)) {
                    searchViewModel.clearSearch()
                }
            }
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

- [ ] **Step 2: Commit**

```bash
git add qwip/ContentView.swift
git commit -m "feat: add search Tab with .search role, intercept tap to show overlay"
```

---

## Task 3: Create SearchOverlay

**Files:**
- Create: `qwip/Views/SearchOverlay.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import MapKit
import CoreLocation

struct SearchOverlay: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @Environment(LocationService.self) private var locationService
    @FocusState private var inputFocused: Bool
    @State private var panelVisible = false

    private var searchRegion: MKCoordinateRegion {
        let center = locationService.userLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        return MKCoordinateRegion(
            center: center,
            latitudinalMeters: 10_000,
            longitudinalMeters: 10_000
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Frost background — tap to dismiss
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        searchViewModel.clearSearch()
                    }
                }

            // Content column — does not dismiss on tap
            VStack(alignment: .leading, spacing: 12) {
                topPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if searchViewModel.selectedPlace == nil {
                    if !searchViewModel.results.isEmpty || searchViewModel.isSearching {
                        resultsCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } else {
                    radiusCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer()
            }
            .offset(y: panelVisible ? 0 : -40)
            .opacity(panelVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                panelVisible = true
            }
            // Small delay so the panel animation is visible before keyboard appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                inputFocused = true
            }
        }
        .onDisappear {
            panelVisible = false
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.results.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.selectedPlace?.id)
    }

    // MARK: - Top Panel

    @ViewBuilder
    private var topPanel: some View {
        if let place = searchViewModel.selectedPlace {
            // Step 2: selected place name + Edit button
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spots near")
                        .font(.dmSans(13, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.5))
                    Text(place.name)
                        .font(.dmSans(28, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        searchViewModel.editPlace()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        inputFocused = true
                    }
                } label: {
                    Text("Edit")
                        .font(.dmSans(14, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.brandPrimary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .contentShape(Rectangle())  // prevent tap-through to dismiss layer
        } else {
            // Step 1: large text input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.4))

                TextField("Where do you want to work?", text: Binding(
                    get: { searchViewModel.query },
                    set: { searchViewModel.updateQuery($0, region: searchRegion) }
                ))
                .font(.dmSans(22, weight: .semibold))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($inputFocused)

                if searchViewModel.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.primary.opacity(0.4))
                } else if !searchViewModel.query.isEmpty {
                    Button {
                        searchViewModel.updateQuery("", region: searchRegion)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

                // Dismiss button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        searchViewModel.clearSearch()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .contentShape(Rectangle())  // prevent tap-through to dismiss layer
        }
    }

    // MARK: - Results Card

    private var resultsCard: some View {
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
                                    .font(.dmSans(14, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                if !place.formattedAddress.isEmpty {
                                    Text(place.formattedAddress)
                                        .font(.dmSans(12))
                                        .foregroundStyle(Color.primary.opacity(0.5))
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if place.id != searchViewModel.results.last?.id {
                        Divider()
                            .overlay(Color.brandBorder)
                            .padding(.leading, 48)
                    }
                }
            }
        }
        .frame(maxHeight: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())  // prevent tap-through to dismiss layer
    }

    // MARK: - Radius Card

    private var radiusCard: some View {
        SearchRadiusCard()
            .padding(.horizontal, 16)
            .contentShape(Rectangle())  // prevent tap-through to dismiss layer
    }
}

// MARK: - Radius Card Component

private struct SearchRadiusCard: View {
    @Environment(SearchViewModel.self) private var searchViewModel
    @State private var sliderIndex: Double = 0

    private let options = SearchViewModel.radiusOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Search radius")
                .font(.dmSans(13, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.55))
                .padding(.horizontal, 16)

            VStack(spacing: 4) {
                Slider(value: $sliderIndex, in: 0...Double(options.count - 1), step: 1)
                    .padding(.horizontal, 16)

                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Text(option.label)
                            .font(.dmSans(10, weight: .semibold))
                            .foregroundStyle(
                                Int(sliderIndex.rounded()) == index
                                    ? Color.primary
                                    : Color.primary.opacity(0.35)
                            )
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: sliderIndex)
                    }
                }
                .padding(.horizontal, 8)
            }

            Button {
                let index = Int(sliderIndex.rounded())
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    searchViewModel.selectRadius(options[index].metres)
                }
            } label: {
                Text("Done")
                    .font(.dmSans(14, weight: .black))
                    .tracking(0.3)
                    .foregroundStyle(Color.brandSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add qwip/Views/SearchOverlay.swift
git commit -m "feat: add SearchOverlay with frost, large text input, results list, and radius card"
```

---

## Task 4: Update MapView — remove old search bar, add SearchOverlay

**Files:**
- Modify: `qwip/Views/MapView.swift`

- [ ] **Step 1: Remove the `safeAreaInset` block**

Find and delete this entire block (it's below the closing `}` of the `ZStack`):

```swift
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
```

- [ ] **Step 2: Add `SearchOverlay` as the top ZStack layer**

In `var body: some View`, the `ZStack(alignment: .top)` currently ends with:

```swift
            if store.isLoading && store.spots.isEmpty {
                loadingOverlay
            }
        }
```

Add `SearchOverlay` after the loading overlay, inside the same ZStack:

```swift
            if store.isLoading && store.spots.isEmpty {
                loadingOverlay
            }
            if searchViewModel.isSearchActive {
                SearchOverlay()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: searchViewModel.isSearchActive)
```

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/MapView.swift
git commit -m "feat: replace safeAreaInset search bar with SearchOverlay ZStack layer in MapView"
```

---

## Task 5: Delete MapSearchBar.swift

**Files:**
- Delete: `qwip/Views/MapSearchBar.swift`

- [ ] **Step 1: Delete the file**

```bash
rm qwip/Views/MapSearchBar.swift
```

Because the project uses `PBXFileSystemSynchronizedRootGroup`, Xcode will automatically remove it from the build — no `.pbxproj` edit needed.

- [ ] **Step 2: Commit**

```bash
git commit -am "chore: delete MapSearchBar.swift — replaced by SearchOverlay"
```

---

## Task 6: Build and Fix

- [ ] **Step 1: Ask the user to build (Cmd+B) and report any errors**

Expected: clean build. Possible issues:
- Any remaining reference to `isExpanded` in files not covered above (e.g. `MapSearchBar` import somewhere) — fix by updating to `isSearchActive`
- Any remaining reference to `MapSearchBar`, `SearchResultsCard`, or `RadiusPickerCard` types — fix by removing the reference (they no longer exist)
- If `Tab(..., role: .search)` gives a compile error, check the iOS deployment target is set to iOS 26 / the SDK supports `TabRole.search`

- [ ] **Step 2: Fix any reported errors, commit fix**

```bash
git add -p
git commit -m "fix: resolve build errors after search redesign"
```
