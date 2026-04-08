# Map Search Design

## Overview

Add a liquid glass search bubble to the tab bar that expands to a full-width search bar. Search uses `MKLocalSearch` to find places, streets, and postcodes. Selecting a result shows a radius picker; selecting a radius centres the map, draws a circle overlay, and filters visible spot annotations. A clear button restores the original map state.

---

## New Files

### `qwip/Models/Place.swift`

`Place` is a value type wrapping `MKMapItem`.

```
struct Place: Identifiable {
    let id: UUID
    let name: String
    let formattedAddress: String   // single-line, built with CNPostalAddressFormatter
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem
}
```

Address formatting: use `CNPostalAddressFormatter` (Contacts framework) with `.mailingAddress` style, then collapse newlines to a comma-separated single line.

### `qwip/Services/SearchViewModel.swift`

`@Observable final class SearchViewModel` — owns all search state and logic.

**State:**
- `var query: String = ""`
- `var results: [Place] = []`
- `var isSearching: Bool = false`  — true while a search task is in-flight
- `var selectedPlace: Place? = nil`
- `var selectedRadius: Double? = nil`  — metres

**Search logic:**
- `func search(query: String, region: MKCoordinateRegion) async` — internal async function
- Called from a `Task` stored as `private var searchTask: Task<Void, Never>?`
- On each `query` change: cancel `searchTask`, create new task that sleeps 300 ms (`Task.sleep(nanoseconds: 300_000_000)`), then calls `search(query:region:)`
- `search` creates `MKLocalSearch.Request` with `naturalLanguageQuery = query`, `region = region`, `resultTypes = [.address, .pointOfInterest]`
- On success: map `MKMapItem` results to `Place` objects, assign to `results`
- Empty query: set `results = []` immediately without searching

**Selection:**
- `func selectPlace(_ place: Place)` — sets `selectedPlace`, clears `results`, clears `query`
- `func selectRadius(_ metres: Double)` — sets `selectedRadius`
- `func clearSearch()` — nils `selectedPlace`, `selectedRadius`, `query`, `results`

**Radius options (static):**

| Label | Metres |
|---|---|
| ¼ mi | 402 |
| ½ mi | 805 |
| 1 mi | 1609 |
| 3 mi | 4828 |

---

## Modified Files

### `qwip/ContentView.swift`

- Instantiate `SearchViewModel` as `@State private var searchViewModel = SearchViewModel()`
- Inject into environment: `.environment(searchViewModel)`
- Add `.overlay(alignment: .bottom)` containing `SearchOverlay` view (defined below)

### `qwip/Views/MapView.swift`

- Inject `@Environment(SearchViewModel.self) var searchViewModel`
- **Circle overlay:** inside `Map(position:)` builder, conditionally add `MapCircle(center: selectedPlace.coordinate, radius: selectedRadius)` stroked with `brandPrimary` at 0.25 opacity, filled at 0.06 opacity
- **Annotation filtering:** in the `clusters` computed var, after existing category/filter logic, additionally exclude spots whose `CLLocation.distance(from: placeLocation)` exceeds `selectedRadius` when both are non-nil
- **Map centring:** `onChange(of: searchViewModel.selectedRadius)` — when `selectedRadius` becomes non-nil (at this point `selectedPlace` is always also set), animate `position` to a region that fits the circle (use `latitudinalMeters: selectedRadius * 2.4`, same for longitudinal)
- **Clear button:** when `searchViewModel.selectedPlace != nil`, show a "Clear" `FilterPill` (using existing component, `isActive: true`) at the leading end of the filter bar. Tapping calls `searchViewModel.clearSearch()`.

---

## Search Overlay UI

`SearchOverlay` is a SwiftUI view defined in `qwip/Views/SearchOverlay.swift`.

### Collapsed state

A liquid glass capsule (`GlassEffectContainer` + `.glassEffect(in: .capsule)`) sitting to the right of the three tab items. Contains a magnifying glass SF Symbol + "Search" label. Taps set `isExpanded = true`.

Positioned via a bottom overlay on `ContentView`, inset from the bottom safe area to align with the tab bar.

### Expanded state

When `isExpanded`:
- The capsule animates (`.matchedGeometryEffect` or spring scale + opacity transition) to a full-width glass bar spanning the tab bar width
- Contains: a `TextField` with "Search spots…" placeholder, and a "Cancel" button that collapses back
- A `ScrollView` of autocomplete results appears above as a glass card (`.ultraThinMaterial` background), listing `Place` names and formatted addresses

### Radius picker

After `selectedPlace` is set (user tapped a result), the overlay switches from showing autocomplete results to showing the four radius option pills in a horizontal row. Once a radius is tapped, `searchViewModel.selectRadius(_:)` is called and the overlay collapses.

### Region for search

`SearchViewModel.search(query:region:)` receives a region. `SearchOverlay` constructs this from `locationService.userLocation` — if available, use `MKCoordinateRegion(center: userLocation.coordinate, latitudinalMeters: 10_000, longitudinalMeters: 10_000)`; otherwise fall back to London centre (`51.5074, -0.1278`) at the same radius.

---

## Behaviour Summary

| User action | Result |
|---|---|
| Tap search bubble | Expands to full-width search bar |
| Type in search bar | Debounced MKLocalSearch, results appear above |
| Tap a result | Radius picker appears |
| Tap a radius | Map centres, circle drawn, spots filtered, overlay collapses |
| Tap "Clear" in filter bar | Circle removed, all spots restored, search reset |
| Tap "Cancel" in expanded bar | Collapses without changing map state |

---

## Constraints

- `MKLocalSearch` only, not `MKLocalSearchCompleter`
- Debounce via `Task.sleep(nanoseconds: 300_000_000)` with task cancellation
- Address formatting via `CNPostalAddressFormatter` (Contacts framework)
- Circle overlay via `MapCircle` (SwiftUI MapKit API)
- Spot radius filtering via `CLLocation.distance(from:)` in the `clusters` computed var
- No persistence — search state is in-memory only
