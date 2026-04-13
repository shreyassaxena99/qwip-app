# Map Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a liquid glass search bubble to the custom bottom tab bar that expands to a full-width search field, queries MKLocalSearch for places/streets/postcodes, lets the user pick a radius, and filters the map annotations to spots within that radius while drawing a circle overlay.

**Architecture:** The native UIKit tab bar is hidden; a custom `CustomBottomBar` view is injected via `.safeAreaInset(edge: .bottom)` on the `TabView`. `SearchViewModel` (@Observable) owns all search state and debounced MKLocalSearch logic. `MapView` reads `SearchViewModel` from the environment to apply the circle overlay and radius-based spot filter.

**Tech Stack:** SwiftUI, MapKit (`MKLocalSearch`, `MapCircle`), CoreLocation (`CLLocation.distance(from:)`), Contacts (`CNPostalAddressFormatter`), `@Observable`, `Task` cancellation for debounce

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `qwip/Models/Place.swift` | Create | `Place` struct wrapping `MKMapItem`, single-line address via Contacts |
| `qwip/Services/SearchViewModel.swift` | Create | `@Observable` search state, debounced `MKLocalSearch`, radius options |
| `qwip/Views/CustomBottomBar.swift` | Create | Custom tab bar + glass search bubble, expanded search field, results list, radius picker |
| `qwip/ContentView.swift` | Modify | Hide native tab bar, `.safeAreaInset` with `CustomBottomBar`, inject `SearchViewModel`, switch to Map tab on radius select |
| `qwip/Views/MapView.swift` | Modify | Inject `SearchViewModel`, `MapCircle` overlay, radius-filter `clusters`, `onChange` for `selectedRadius`, "Clear" button in filter bar |

---

### Task 1: `Place` model

**Files:**
- Create: `qwip/Models/Place.swift`

- [ ] **Step 1: Create `Place.swift`**

```swift
import Foundation
import MapKit
import Contacts

struct Place: Identifiable {
    let id: UUID
    let name: String
    let formattedAddress: String
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem

    init(from mapItem: MKMapItem) {
        self.id = UUID()
        self.name = mapItem.name ?? "Unknown"
        self.coordinate = mapItem.placemark.coordinate
        self.mapItem = mapItem

        if let postalAddress = mapItem.placemark.postalAddress {
            let raw = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            self.formattedAddress = raw
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        } else {
            self.formattedAddress = ""
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add qwip/Models/Place.swift
git commit -m "feat: add Place model wrapping MKMapItem with formatted address"
```

---

### Task 2: `SearchViewModel`

**Files:**
- Create: `qwip/Services/SearchViewModel.swift`

- [ ] **Step 1: Create `SearchViewModel.swift`**

```swift
import Foundation
import MapKit
import Observation

@Observable
final class SearchViewModel {
    var query: String = ""
    var results: [Place] = []
    var isSearching: Bool = false
    var isExpanded: Bool = false
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
        results = []
        query = ""
    }

    func selectRadius(_ metres: Double) {
        selectedRadius = metres
        isExpanded = false
    }

    func clearSearch() {
        searchTask?.cancel()
        query = ""
        results = []
        isSearching = false
        isExpanded = false
        selectedPlace = nil
        selectedRadius = nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add qwip/Services/SearchViewModel.swift
git commit -m "feat: add SearchViewModel with debounced MKLocalSearch"
```

---

### Task 3: `CustomBottomBar`

**Files:**
- Create: `qwip/Views/CustomBottomBar.swift`

This file contains four views:
- `CustomBottomBar` — the bar itself (collapsed bubble or expanded search field)
- `SearchResultsCard` — autocomplete results list shown above the bar
- `RadiusPickerCard` — four radius option pills shown after a place is selected
- `SearchRegionHelper` — one computed property extracted for reuse

- [ ] **Step 1: Create `CustomBottomBar.swift`**

```swift
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Custom Bottom Bar

struct CustomBottomBar: View {
    @Binding var selectedTab: Int
    @Environment(SearchViewModel.self) var searchViewModel
    @Environment(LocationService.self) var locationService
    @FocusState private var searchFocused: Bool

    // Adaptive tint — brandPrimary in light, lavender in dark (matches former UIKit tab bar tint)
    private static let lavender = Color(red: 0xC9/255, green: 0xB8/255, blue: 0xE0/255)

    private var adaptiveTint: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xC9/255, green: 0xB8/255, blue: 0xE0/255, alpha: 1)
                : UIColor(red: 0x1F/255, green: 0x3D/255, blue: 0x32/255, alpha: 1)
        })
    }

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
        .frame(height: 49)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 0.5)
                }
        }
        .onChange(of: searchViewModel.isExpanded) { _, expanded in
            if expanded {
                searchFocused = true
            } else {
                searchFocused = false
            }
        }
    }

    // MARK: Collapsed

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            tabItem(icon: "map.fill",    label: "Map",     tag: 0)
            tabItem(icon: "heart.fill",  label: "Saved",   tag: 1)
            tabItem(icon: "person.fill", label: "Profile", tag: 2)

            Spacer(minLength: 12)

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
            .padding(.trailing, 14)
        }
    }

    private func tabItem(icon: String, label: String, tag: Int) -> some View {
        Button { selectedTab = tag } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: selectedTab == tag ? .semibold : .regular))
                Text(label)
                    .font(.dmSans(10, weight: .bold))
            }
            .foregroundStyle(selectedTab == tag ? adaptiveTint : Color.primary.opacity(0.4))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .padding(.horizontal, 14)
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

- [ ] **Step 2: Commit**

```bash
git add qwip/Views/CustomBottomBar.swift
git commit -m "feat: add CustomBottomBar with glass search bubble, results card, radius picker"
```

---

### Task 4: Wire `ContentView`

**Files:**
- Modify: `qwip/ContentView.swift`

- [ ] **Step 1: Add `searchViewModel` state property**

After `@State private var selectedTab = 0`, add:

```swift
@State private var searchViewModel = SearchViewModel()
```

- [ ] **Step 2: Hide the native tab bar on each tab**

Update each `Tab` to add `.toolbar(.hidden, for: .tabBar)` on its root view:

```swift
Tab("Map", systemImage: "map.fill", value: 0) {
    MapView().toolbar(.hidden, for: .tabBar)
}
Tab("Saved", systemImage: "heart.fill", value: 1) {
    CollectionsView().toolbar(.hidden, for: .tabBar)
}
Tab("Profile", systemImage: "person.fill", value: 2) {
    ProfileView().toolbar(.hidden, for: .tabBar)
}
```

- [ ] **Step 3: Add `.safeAreaInset` with `CustomBottomBar` and results overlay**

Replace the existing `.environment(store)` chain with the complete modifier chain below (preserve all existing modifiers, add the new ones):

```swift
TabView(selection: $selectedTab) { ... }
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
            CustomBottomBar(selectedTab: $selectedTab)
        }
        .environment(searchViewModel)
        .environment(locationService)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: searchViewModel.isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.results.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchViewModel.selectedPlace?.id)
    }
    .environment(searchViewModel)  // ← add this alongside existing .environment() calls
    // ... keep all other existing modifiers (.environment(store), .tint, .preferredColorScheme, etc.)
```

- [ ] **Step 4: Switch to Map tab when a radius is selected**

Add this `onChange` alongside the existing `.onChange(of: appRouter.pendingCollectionId)`:

```swift
.onChange(of: searchViewModel.selectedRadius) { _, radius in
    if radius != nil { selectedTab = 0 }
}
```

- [ ] **Step 5: Build — ask user to press Cmd+B and confirm no errors**

- [ ] **Step 6: Commit**

```bash
git add qwip/ContentView.swift
git commit -m "feat: wire SearchViewModel into ContentView with custom bottom bar"
```

---

### Task 5: MapView search integration

**Files:**
- Modify: `qwip/Views/MapView.swift`

- [ ] **Step 1: Inject `SearchViewModel` into `MapView`**

After the existing `@Environment(LocationService.self) var locationService` line, add:

```swift
@Environment(SearchViewModel.self) var searchViewModel
```

- [ ] **Step 2: Add radius filtering to the `clusters` computed var**

At the top of the `clusters` computed var, before `let radius = mapSpan.latitudeDelta * 0.15`, add a filtered source:

```swift
private var clusters: [SpotCluster] {
    // Apply search radius filter on top of store's category/preference filters
    let source: [SpotPin]
    if let place = searchViewModel.selectedPlace, let radiusMetres = searchViewModel.selectedRadius {
        let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        source = store.filteredSpots.filter { spot in
            let spotLocation = CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude)
            return spotLocation.distance(from: placeLocation) <= radiusMetres
        }
    } else {
        source = store.filteredSpots
    }

    let radius = mapSpan.latitudeDelta * 0.15
    var remaining = source   // ← was `store.filteredSpots`
    var result: [SpotCluster] = []
    // ... rest of existing clustering code unchanged
```

- [ ] **Step 3: Add `MapCircle` overlay inside the `Map` builder**

Inside `mapLayer`, after the `ForEach(clusters)` block and before the closing `}` of `Map(position: $position)`, add:

```swift
if let place = searchViewModel.selectedPlace, let radius = searchViewModel.selectedRadius {
    MapCircle(center: place.coordinate, radius: radius)
        .foregroundStyle(Color.brandPrimary.opacity(0.07))
        .stroke(Color.brandPrimary.opacity(0.35), lineWidth: 1.5)
}
```

- [ ] **Step 4: Add `onChange` for `selectedRadius` to centre the map**

Add this modifier to `mapLayer` (alongside the existing `.onMapCameraChange` modifiers):

```swift
.onChange(of: searchViewModel.selectedRadius) { _, radius in
    guard let radius, let place = searchViewModel.selectedPlace else { return }
    withAnimation(.easeInOut(duration: 0.8)) {
        position = .region(MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: radius * 2.4,
            longitudinalMeters: radius * 2.4
        ))
    }
}
```

- [ ] **Step 5: Add "Clear" button to the filter bar**

In `filterBarOverlay`, inside the `GlassEffectContainer`'s `HStack`, add this as the **first** child (before the existing `FilterPill(title: "All", ...)`):

```swift
if searchViewModel.selectedPlace != nil {
    Button {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            searchViewModel.clearSearch()
            selectedSpot = nil
        }
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
            Text("Clear")
                .font(.dmSans(10, weight: .black))
                .tracking(0.5)
        }
        .foregroundStyle(Color.brandSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.brandPrimary))
    }
    .buttonStyle(.plain)
    .transition(.scale.combined(with: .opacity))
}
```

- [ ] **Step 6: Build — ask user to press Cmd+B and confirm no errors**

- [ ] **Step 7: Manual smoke test**

1. Tap the "Search" glass bubble in the bottom bar — it expands to show a text field
2. Type "Shoreditch" — results appear above the bar after ~300 ms
3. Tap a result — radius picker appears
4. Tap "½ mi" — map centres on the place, circle drawn, only spots within 805 m shown, picker collapses
5. "Clear" pill appears in the filter bar — tap it — circle removed, all spots restored, bar collapses
6. Tap "Cancel" in expanded bar without selecting a place — bar collapses, map unchanged

- [ ] **Step 8: Commit**

```bash
git add qwip/Views/MapView.swift
git commit -m "feat: MapView radius filter, circle overlay, and clear button"
```
