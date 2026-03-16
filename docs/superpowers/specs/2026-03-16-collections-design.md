# Collections — Design Spec

**Date:** 2026-03-16

## Summary

Users can organise saved spots into named collections. When saving a spot, a bottom sheet lets them pick one or more collections (or leave it in "Favourite Spots", a client-side virtual collection). The Saved tab becomes a collections list; tapping a collection shows its spots.

---

## Scope

New files:
- `qwip/Models/Collection.swift` — `Collection` model
- `qwip/Services/CollectionAPIClient.swift` — raw HTTP client
- `qwip/Services/CollectionService.swift` — `@Observable @MainActor` state service
- `qwip/Views/CollectionsView.swift` — replaces `SavedSpotsView` as the Saved tab
- `qwip/Views/CollectionDetailView.swift` — spots inside a single collection
- `qwip/Views/SaveToCollectionSheet.swift` — bottom sheet for save/organise

Modified files:
- `qwip/Models/Spot.swift` — no model changes needed (`SavedSpotEntry.collectionIds` already exists)
- `qwip/Services/SavedSpotService.swift` — `save(spot:collectionIds:)` gains optional `collectionIds` param
- `qwip/Services/SavedSpotAPIClient.swift` — `saveSpot(spotId:collectionIds:)` adds `collection_ids` to request body; `fetchSavedSpots(collectionId:)` adds optional query param
- `qwip/Views/SpotDetailView.swift` — heart tap opens `SaveToCollectionSheet` instead of toggling directly
- `qwip/Views/ContentView.swift` — inject `CollectionService`; load both services on startup
- `qwip/Views/SavedSpotsView.swift` — replaced by `CollectionsView` in the tab (file may be deleted or repurposed as `CollectionDetailView`)

---

## 1. Data Model

### `Collection` (`qwip/Models/Collection.swift`)

```swift
struct Collection: Identifiable, Codable {
    let id: String
    let name: String
    let spotCount: Int
    let createdAt: Date
    let updatedAt: Date
    // is_shareable decoded but unused in UI
    let isShareable: Bool
}
```

Decoder: `.convertFromSnakeCase`, same fractional-second ISO 8601 date format as `SavedSpotAPIClient`.

### `SavedSpotEntry` (unchanged)

`collectionIds: [String]` already present. A spot belongs to "Favourite Spots" when `collectionIds.isEmpty`.

---

## 2. `CollectionAPIClient` (`qwip/Services/CollectionAPIClient.swift`)

Singleton struct, mirrors `SavedSpotAPIClient` exactly:
- Same `baseURL`, same `bearerToken()` / `authedRequest()` helpers
- Same decoder (`.convertFromSnakeCase`, fractional-second dates) and encoder (`.convertToSnakeCase`)
- Same `CollectionAPIError` type mirroring `SavedSpotAPIError`

### Response wrappers (private)

```swift
private struct CollectionsResponse: Decodable { let collections: [Collection] }
```

### Endpoints

| Method | Signature | HTTP |
|--------|-----------|------|
| `fetchCollections()` | `async throws -> [Collection]` | `GET /me/collections` |
| `createCollection(name:)` | `async throws -> Collection` | `POST /me/collections` body: `{"name":"..."}` |
| `renameCollection(id:name:)` | `async throws -> Collection` | `PATCH /me/collections/{id}` body: `{"name":"..."}` |
| `deleteCollection(id:)` | `async throws` | `DELETE /me/collections/{id}` (204) |
| `addSpotToCollection(collectionId:spotId:)` | `async throws -> SavedSpotEntry` | `POST /me/collections/{id}/spots` body: `{"spot_id":"..."}` |
| `removeSpotFromCollection(collectionId:spotId:)` | `async throws` | `DELETE /me/collections/{id}/spots/{spotId}` (204) |

---

## 3. `CollectionService` (`qwip/Services/CollectionService.swift`)

```swift
@Observable @MainActor
final class CollectionService {
    var collections: [Collection] = []
    var isLoading = false
    var loadError: String? = nil
}
```

### Methods

**`load()`** — guarded against re-entrancy (same pattern as `SavedSpotService.load()`). Sets `isLoading`, calls `fetchCollections()`, updates `collections`, clears `isLoading`.

**`create(name:) async throws -> Collection`** — optimistic: appends a stub collection (id: UUID placeholder, spotCount: 0) immediately, replaces with server response, removes stub on failure.

**`rename(id:name:) async throws`** — optimistic: updates `name` in place, reverts on failure.

**`delete(id:) async throws`** — optimistic: removes from `collections` immediately, re-inserts at original index on failure.

**`addSpot(spotId:toCollection:) async throws -> SavedSpotEntry`** — calls `addSpotToCollection`, increments `spotCount` on the matching collection optimistically, reverts on failure. Returns `SavedSpotEntry` so callers can update `savedEntries`.

**`removeSpot(spotId:fromCollection:) async throws`** — calls `removeSpotFromCollection`, decrements `spotCount` optimistically.

---

## 4. `SavedSpotService` updates

### `save(spot:collectionIds:)`

Signature change:
```swift
func save(spot: SpotPin, collectionIds: [String] = []) async throws
```

Passes `collectionIds` through to `SavedSpotAPIClient.saveSpot(spotId:collectionIds:)`. After the server responds, updates the stub entry's `collectionIds` with the returned `SavedSpotResponse.collectionIds`.

### No other changes — `isSaved(_:)`, `unsave(spotId:)`, `load()` unchanged.

---

## 5. `SavedSpotAPIClient` updates

### `saveSpot(spotId:collectionIds:)`

```swift
private struct SaveSpotBody: Encodable {
    let spotId: String
    let collectionIds: [String]
}
```

`collection_ids` always included in body (empty array if none selected).

### `fetchSavedSpots(collectionId:)`

```swift
func fetchSavedSpots(collectionId: String? = nil) async throws -> [SavedSpotEntry]
```

If `collectionId` is non-nil, appends `?collection_id={id}` to the URL.

---

## 6. `SaveToCollectionSheet` (`qwip/Views/SaveToCollectionSheet.swift`)

A `.sheet` presented from `SpotDetailView` when the heart icon is tapped.

### Input

```swift
struct SaveToCollectionSheet: View {
    let spot: SpotPin // or SpotDetail — whichever is available at call site
    let isSaved: Bool
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService
    @Environment(\.dismiss) var dismiss
}
```

### State

```swift
@State private var selectedIds: Set<String> = []   // real collection IDs
@State private var favouritesTicked: Bool = true   // virtual "Favourite Spots" row
@State private var isNewCollectionExpanded = false
@State private var newCollectionName = ""
@State private var isSaving = false
@State private var error: String? = nil
```

On appear:
- If `isSaved`: populate `selectedIds` from `savedSpotService.savedEntries[spot.id].collectionIds`; set `favouritesTicked = selectedIds.isEmpty`
- If not saved: `selectedIds = []`, `favouritesTicked = true`

### Layout

1. **Drag handle** — `Capsule` 36×4pt, `Color.brandPrimary.opacity(0.2)`, centred
2. **Title** — "Save to collection" / "Organise" (if already saved), dmSans heavy
3. **"Favourite Spots" row** — always first, checkbox tick, non-deletable. Ticking/unticking toggles `favouritesTicked`. If all real collections are unticked and `favouritesTicked` is false, this is equivalent to "save with no collection".
4. **Collection rows** — one per `collectionService.collections`, each with checkbox. Toggle adds/removes from `selectedIds`.
5. **"+ New collection" row** — tapping expands an inline text field + "Create" button. On confirm: calls `collectionService.create(name:)`, auto-ticks the new collection in `selectedIds`, collapses the field.
6. **Primary action button** — "Save" (if not saved) / "Done" (if saved). Full-width, `Color.brandPrimary` fill.
7. **"Remove from saved" button** (only if `isSaved`) — text-only destructive button at bottom. Calls `savedSpotService.unsave(spotId:)` then dismisses.

### On confirm ("Save" / "Done")

**Not saved:**
- Call `savedSpotService.save(spot:collectionIds: Array(selectedIds))`
- Dismiss

**Already saved:**
- Diff `selectedIds` vs original `collectionIds`
- For each added ID: `collectionService.addSpot(spotId:toCollection:)`
- For each removed ID: `collectionService.removeSpot(spotId:fromCollection:)`
- If `favouritesTicked` toggled off and all real collections unticked → no-op (spot stays saved)
- Update `savedEntries` entry's `collectionIds` with new set
- Dismiss

Errors surface via `error` state → `.alert` on the sheet.

---

## 7. `SpotDetailView` changes

Heart icon tap: instead of calling `toggleSave()`, set `@State private var showingSaveSheet = false` and present `SaveToCollectionSheet` as `.sheet(isPresented: $showingSaveSheet)`.

`toggleSave()` and `isSaving` are removed. `saveError` is removed (errors now handled inside the sheet).

Heart icon still reflects `savedSpotService.isSaved(detail.id)` for its filled/unfilled state.

---

## 8. `CollectionsView` (`qwip/Views/CollectionsView.swift`)

Replaces `SavedSpotsView` as the content of the Saved tab in `ContentView`.

### Layout

- `NavigationStack` with title "Saved"
- `List` with two sections:
  1. **"Favourite Spots" row** — pinned first, shows count of `savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }.count`. No swipe actions. Tap → `CollectionDetailView(collection: .favourites)`
  2. **Real collections** — from `collectionService.collections`. Each row: name + spot count. Swipe left: grey pencil (rename) + red bin (delete).

### Rename

Swipe pencil → `Alert` with `TextField` pre-filled with current name → confirm calls `collectionService.rename(id:name:)`.

### Delete

Swipe bin → confirmation `Alert` ("Spots will stay saved") → confirm calls `collectionService.delete(id:)`.

### Pull-to-refresh

Calls `await savedSpotService.load()` and `await collectionService.load()` concurrently via `async let`.

### `+` nav bar button

Alert with text field → `collectionService.create(name:)`.

### Loading / error states

Same three-state pattern as current `SavedSpotsView`: spinner, error with retry, empty state.

---

## 9. `CollectionDetailView` (`qwip/Views/CollectionDetailView.swift`)

Displays the spots inside a single collection. Reuses the spot grid layout from `SavedSpotsView`.

### Input

```swift
enum CollectionSource {
    case favourites                  // client-side: savedEntries where collectionIds.isEmpty
    case collection(Collection)      // real backend collection
}
```

```swift
struct CollectionDetailView: View {
    let source: CollectionSource
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService
}
```

### Data

- `.favourites`: reads `savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }` — no extra fetch needed
- `.collection(c)`: fetches `GET /me/saved-spots?collection_id={c.id}` into local `@State var entries: [SavedSpotEntry]` on appear; pull-to-refresh re-fetches

### Swipe action on spot card

- `.favourites`: "Unsave" (red) → `savedSpotService.unsave(spotId:)`
- `.collection(c)`: "Remove from collection" (orange) → `collectionService.removeSpot(spotId:fromCollection:c.id)`

### Tap → `SpotDetailView` sheet (unchanged)

---

## 10. `ContentView` changes

```swift
@State private var collectionService = CollectionService()
```

Injected via `.environment(collectionService)` alongside existing services.

Initial `.task`:
```swift
async let _ = savedSpotService.load()
async let _ = collectionService.load()
```

`SavedSpotsView()` tab replaced with `CollectionsView()`.

---

## Out of Scope

- `is_shareable` / shareability UI
- Reordering collections
- Spot reordering within a collection
- Collection cover images
- Sharing collections with other users
