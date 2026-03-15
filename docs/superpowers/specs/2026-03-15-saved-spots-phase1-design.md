# Saved Spots Phase 1 — Design Spec
**Date:** 2026-03-15
**Status:** Approved

## Overview

Wire saved spots to the real backend. Replace the current local `savedSpotIDs: Set<String>` in `SpotStore` with a new `SavedSpotService` that talks to the authenticated `/me/saved-spots` API. Phase 1 covers save, unsave, and loading the saved list. Collections UI is Phase 2.

## Endpoints Used

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| GET | `/me/saved-spots` | Bearer JWT | Load all saved spots |
| POST | `/me/saved-spots` | Bearer JWT | Save a spot |
| DELETE | `/me/saved-spots/{spot_id}` | Bearer JWT | Unsave a spot |

All requests include `Authorization: Bearer <supabase_access_token>` from `supabase.auth.session?.accessToken`.

## Data Model

New type added to `Models/Spot.swift`:

```swift
struct SavedSpotEntry: Identifiable, Codable {
    let spot: SpotPin
    let savedAt: Date
    let collectionIds: [String]

    var id: String { spot.id }
}
```

The decoder uses `.convertFromSnakeCase` so `saved_at` → `savedAt` and `collection_ids` → `collectionIds` convert automatically. If the API returns spot fields flat at the top level rather than nested under a `"spot"` key, a custom `init(from:)` will be added at that point.

**Date decoding**: Supabase emits timestamps with fractional seconds (e.g. `2026-03-15T10:00:00.123Z`). Plain `.iso8601` does not handle these. `SavedSpotAPIClient`'s decoder must use a custom `DateFormatter`:

```swift
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
decoder.dateDecodingStrategy = .formatted(formatter)
```

**`SpotDetail.asSpotPin`**: A computed property `var asSpotPin: SpotPin` is added to `SpotDetail` in `Models/Spot.swift`. It constructs a `SpotPin` from the overlapping fields (`id`, `name`, `shortAddress`, `latitude`, `longitude`, `category`, `accessType`, `wifiAvailable`, `powerOutlets`, `noiseMatrix`, `rating`, `isOpenNow`, `coverPhoto`). This keeps `SavedSpotService.save(spot:)` typed to `SpotPin` and is the single conversion point used in `SpotDetailView`.

## New Files

### `Services/SavedSpotAPIClient.swift`

Struct with a `shared` singleton. Uses the same base URL as `SpotAPIClient`. Owns three methods:

- `func fetchSavedSpots() async throws -> [SavedSpotEntry]` — GET /me/saved-spots
- `func saveSpot(spotId: String) async throws -> SavedSpotEntry` — POST /me/saved-spots with `{"spot_id": "<id>"}`
- `func unsaveSpot(spotId: String) async throws` — DELETE /me/saved-spots/{spot_id}

All methods read the JWT from `supabase.auth.session?.accessToken`. If no session exists, throw an auth error. A 404 response on `unsaveSpot` is treated as success (already gone) and does not throw.

Decoder is configured with `.convertFromSnakeCase` and the fractional-second `DateFormatter` above.

### `Services/SavedSpotService.swift`

`@Observable @MainActor final class`. Single source of truth for saved state.

**State:**
```swift
private(set) var savedEntries: [SavedSpotEntry] = []
private(set) var isLoading = false
private(set) var loadError: String? = nil
```

**Interface:**
```swift
func isSaved(_ spotId: String) -> Bool
func load() async                         // clears loadError on entry
func save(spot: SpotPin) async throws
func unsave(spotId: String) async throws
```

**`load()`** clears `loadError = nil` at the start of each call (matching the pattern in `SpotStore.loadSpots()`), so the error banner dismisses immediately when the user taps Retry rather than remaining visible until the request completes.

**Optimistic update strategy:**

- `save(spot:)`: construct a stub `SavedSpotEntry(spot: spot, savedAt: .now, collectionIds: [])` and insert at index 0 immediately → POST → replace stub with the real entry from the response (which has the authoritative `savedAt`). On failure: remove stub, rethrow error.
- `unsave(spotId:)`: capture the existing entry and its index, remove it immediately → DELETE → done. On failure: re-insert captured entry at its original index, rethrow error.

`isSaved` is a simple O(n) scan over `savedEntries` — acceptable for the expected list sizes.

## Modified Files

### `Services/SpotStore.swift`

Remove entirely:
- `var savedSpotIDs: Set<String>`
- `var savedSpots: [SpotPin]`
- `func toggleSave(id:)`
- `func isSaved(id:) -> Bool`

`additionalFilterCount` and `hasAdditionalFilters` are unaffected.

### `Views/ContentView.swift`

`SavedSpotService` follows the same ownership pattern as `SpotStore` and `LocationService`:

```swift
@State private var savedSpotService = SavedSpotService()
```

Injected alongside existing services:
```swift
.environment(savedSpotService)
```

Initial load triggered by `.task` — `ContentView` only renders when authenticated, so appearing equals sign-in:
```swift
.task { await savedSpotService.load() }
```

When the user signs out, `RootView` unmounts `ContentView`, destroying `@State` properties and clearing `savedEntries` automatically. No explicit clear needed. **No changes to `qwipApp.swift` or `RootView.swift`.**

### `Views/SpotDetailView.swift`

- Add `@Environment(SavedSpotService.self) var savedSpotService`
- Add `@State private var isSaving = false` and `@State private var saveError: String?`
- Replace `store.isSaved(id:)` → `savedSpotService.isSaved(detail.id)`
- Add a private `func toggleSave()` on the view that both the toolbar heart button and the actionsRow save button call. This ensures both share the same `isSaving` guard:

```swift
private func toggleSave() {
    guard !isSaving else { return }
    isSaving = true
    Task {
        do {
            if savedSpotService.isSaved(detail.id) {
                try await savedSpotService.unsave(spotId: detail.id)
            } else {
                try await savedSpotService.save(spot: detail.asSpotPin)
            }
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

- Both the **toolbar heart button** and the **actionsRow save button** call `toggleSave()` and are `.disabled(isSaving)`.
- Add `.alert` bound to `saveError` for failure display.

### `Views/SavedSpotsView.swift`

- Add `@Environment(SavedSpotService.self) var savedSpotService`
- Replace `store.savedSpots` → `savedSpotService.savedEntries`; pass `entry.spot` to `SavedSpotCard`
- Wrap the entire view body (both empty state and grid branches) in a `ScrollView` so pull-to-refresh is available in all states, including when the list is empty
- Add `.refreshable { await savedSpotService.load() }` on that outer `ScrollView`
- Retain the existing `LazyVGrid` (two-column) layout inside the scroll view — do **not** convert to `List`
- **Remove action on card**: `LazyVGrid` does not support `.onDelete`. Instead, add a long-press context menu to each `SavedSpotCard` with a "Remove" action that calls `Task { try? await savedSpotService.unsave(spotId: spot.id) }`. On failure, show a `.alert` error.
- Show `ProgressView` fullscreen when `savedSpotService.isLoading && savedSpotService.savedEntries.isEmpty`
- Show an inline error banner with a Retry button when `savedSpotService.loadError != nil`; tapping Retry calls `Task { await savedSpotService.load() }` which clears the error immediately
- Empty state shown when `savedEntries.isEmpty && !isLoading`

The API returns entries newest-first, so no client-side sort is needed.

**`MapView`**: No save button exists on the selected-spot tile. No changes needed there.

## Error Handling

| Scenario | Handling |
|----------|----------|
| Save fails | Roll back stub entry, surface error via `saveError` alert in `SpotDetailView` |
| Unsave fails (detail view) | Re-insert entry at original index, surface error via `saveError` alert |
| Unsave fails (saved spots view) | Re-insert entry, surface error via local alert |
| 404 on unsave | Treated as success in `SavedSpotAPIClient` — no error surfaced |
| Load fails | Set `loadError`, show error banner in `SavedSpotsView` with Retry; `load()` clears it on next call |
| No session when calling API | Throw auth error, surface as alert |

## Out of Scope (Phase 2)

- Collections filter/segmented control in `SavedSpotsView`
- "Save to collections" bottom sheet
- `collection_ids` from `SavedSpotEntry` is decoded and stored but not displayed
