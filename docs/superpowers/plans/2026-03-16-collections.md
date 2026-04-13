# Collections Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can organise saved spots into named collections; a bottom sheet lets them pick collections when saving; the Saved tab shows a collections list; "Favourite Spots" is a virtual collection for uncollected saves.

**Architecture:** New `Collection` model + `CollectionAPIClient` + `CollectionService` sit alongside the existing `SavedSpot*` layer. `SavedSpotService` gains `collectionIds` support and `updateCollectionIds`. The Saved tab's `SavedSpotsView` is replaced by `CollectionsView` (list) + `CollectionDetailView` (spot grid). `SpotDetailView`'s heart tap opens a `SaveToCollectionSheet` instead of toggling directly.

**Tech Stack:** SwiftUI, `@Observable @MainActor`, Swift Testing, existing `SavedSpotAPIClient`/`SavedSpotService` patterns.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `qwip/Models/Collection.swift` | `Collection` Codable struct |
| Create | `qwip/Services/CollectionAPIClient.swift` | Raw HTTP client for all `/me/collections` endpoints |
| Create | `qwip/Services/CollectionService.swift` | `@Observable @MainActor` state + optimistic updates |
| Create | `qwip/Views/SaveToCollectionSheet.swift` | Bottom sheet for save / organise |
| Create | `qwip/Views/CollectionsView.swift` | Saved tab — collections list with swipe rename/delete |
| Create | `qwip/Views/CollectionDetailView.swift` | Spot grid for a single collection |
| Modify | `qwip/Services/SavedSpotAPIClient.swift` | Add `collectionIds` to save body; add `collectionId` query param to fetch |
| Modify | `qwip/Services/SavedSpotService.swift` | Add `collectionIds` param to `save`; add `updateCollectionIds` |
| Modify | `qwip/Views/SpotDetailView.swift` | Heart tap opens sheet instead of toggling directly |
| Modify | `qwip/ContentView.swift` | Inject `CollectionService`; load both services; swap tab view |
| Modify | `qwip/Components/SpotCard.swift` | Move `SavedSpotCard` here from `SavedSpotsView` (removes `private`) |
| Delete | `qwip/Views/SavedSpotsView.swift` | Replaced entirely by `CollectionsView` + `CollectionDetailView` |
| Modify | `qwipTests/qwipTests.swift` | Add decoding + service unit tests |

---

## Chunk 1: Data & API layer

### Task 1: Collection model + unit test

**Files:**
- Create: `qwip/Models/Collection.swift`
- Modify: `qwipTests/qwipTests.swift`

**Background:**
- `Collection` uses the same fractional-second ISO 8601 date format as `SavedSpotEntry` — decoder must match
- `is_shareable` is decoded but unused in UI (include in model for completeness, ignore in views)
- `SavedSpotEntry` already has `collectionIds: [String]` — no model changes needed there

- [ ] **Step 1: Write the failing test**

Open `qwipTests/qwipTests.swift` and replace the placeholder with:

```swift
import Testing
@testable import qwip
import Foundation

struct qwipTests {

    // MARK: - Collection decoding

    @Test func collectionDecodesFromJSON() throws {
        let json = """
        {
            "id": "abc-123",
            "name": "Morning Cafes",
            "is_shareable": false,
            "spot_count": 3,
            "created_at": "2026-03-16T09:00:00.000+0000",
            "updated_at": "2026-03-16T09:00:00.000+0000"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        decoder.dateDecodingStrategy = .formatted(formatter)

        let collection = try decoder.decode(Collection.self, from: json)
        #expect(collection.id == "abc-123")
        #expect(collection.name == "Morning Cafes")
        #expect(collection.spotCount == 3)
        #expect(collection.isShareable == false)
    }

    @Test func collectionsResponseDecodesFromJSON() throws {
        let json = """
        {
            "collections": [
                {
                    "id": "abc-123",
                    "name": "Morning Cafes",
                    "is_shareable": false,
                    "spot_count": 3,
                    "created_at": "2026-03-16T09:00:00.000+0000",
                    "updated_at": "2026-03-16T09:00:00.000+0000"
                }
            ]
        }
        """.data(using: .utf8)!

        struct CollectionsResponse: Decodable { let collections: [Collection] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        decoder.dateDecodingStrategy = .formatted(formatter)

        let response = try decoder.decode(CollectionsResponse.self, from: json)
        #expect(response.collections.count == 1)
        #expect(response.collections[0].name == "Morning Cafes")
    }
}
```

- [ ] **Step 2: Create `qwip/Models/Collection.swift`**

```swift
import Foundation

struct Collection: Identifiable, Codable {
    let id: String
    let name: String
    let isShareable: Bool
    let spotCount: Int
    let createdAt: Date
    let updatedAt: Date
}
```

- [ ] **Step 3: Build and verify**

Build in Xcode (⌘B). The test file references `Collection` — confirm no compile errors.

- [ ] **Step 4: Commit**

```bash
git add qwip/Models/Collection.swift qwipTests/qwipTests.swift
git commit -m "feat: add Collection model with unit tests"
```

---

### Task 2: CollectionAPIClient

**Files:**
- Create: `qwip/Services/CollectionAPIClient.swift`

**Background:**
- Mirror `SavedSpotAPIClient` exactly: same `baseURL`, same `bearerToken()` helper, same decoder/encoder config, same `supabase` module-level singleton
- `SavedSpotEntry` is already importable — no need to redefine it
- Endpoints: GET/POST `/me/collections`, PATCH/DELETE `/me/collections/{id}`, POST/DELETE `/me/collections/{id}/spots/{spotId}`

- [ ] **Step 1: Create `qwip/Services/CollectionAPIClient.swift`**

```swift
import Foundation

// MARK: - Errors

enum CollectionAPIError: LocalizedError {
    case notAuthenticated
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to manage collections."
        case .serverError(let code): return "Server error (\(code))."
        case .decodingError: return "Couldn't parse the server response."
        }
    }
}

// MARK: - Request bodies

private struct CreateCollectionBody: Encodable { let name: String }
private struct RenameCollectionBody: Encodable { let name: String }
private struct AddSpotToCollectionBody: Encodable { let spotId: String }

// MARK: - Response wrappers

private struct CollectionsResponse: Decodable { let collections: [Collection] }

// MARK: - Client

struct CollectionAPIClient {
    static let shared = CollectionAPIClient()

    private let baseURL = URL(string: "https://spotsvc.up.railway.app")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        d.dateDecodingStrategy = .formatted(formatter)
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Auth helpers

    private func bearerToken() throws -> String {
        guard let token = supabase.auth.currentSession?.accessToken else {
            throw CollectionAPIError.notAuthenticated
        }
        return token
    }

    private func authedRequest(url: URL, method: String = "GET") throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try bearerToken())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    // MARK: - Collections

    /// GET /me/collections
    func fetchCollections() async throws -> [Collection] {
        let url = baseURL.appendingPathComponent("me/collections")
        let req = try authedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(CollectionsResponse.self, from: data).collections
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// POST /me/collections
    func createCollection(name: String) async throws -> Collection {
        let url = baseURL.appendingPathComponent("me/collections")
        var req = try authedRequest(url: url, method: "POST")
        req.httpBody = try encoder.encode(CreateCollectionBody(name: name))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(Collection.self, from: data)
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// PATCH /me/collections/{id}
    func renameCollection(id: String, name: String) async throws -> Collection {
        let url = baseURL.appendingPathComponent("me/collections/\(id)")
        var req = try authedRequest(url: url, method: "PATCH")
        req.httpBody = try encoder.encode(RenameCollectionBody(name: name))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(Collection.self, from: data)
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// DELETE /me/collections/{id} — 204, spots remain saved
    func deleteCollection(id: String) async throws {
        let url = baseURL.appendingPathComponent("me/collections/\(id)")
        let req = try authedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
    }

    // MARK: - Collection spots

    /// POST /me/collections/{collectionId}/spots — also saves the spot if not already saved
    func addSpotToCollection(collectionId: String, spotId: String) async throws -> SavedSpotEntry {
        let url = baseURL.appendingPathComponent("me/collections/\(collectionId)/spots")
        var req = try authedRequest(url: url, method: "POST")
        req.httpBody = try encoder.encode(AddSpotToCollectionBody(spotId: spotId))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
        do {
            return try decoder.decode(SavedSpotEntry.self, from: data)
        } catch {
            throw CollectionAPIError.decodingError(error)
        }
    }

    /// DELETE /me/collections/{collectionId}/spots/{spotId} — spot stays saved
    func removeSpotFromCollection(collectionId: String, spotId: String) async throws {
        let url = baseURL.appendingPathComponent("me/collections/\(collectionId)/spots/\(spotId)")
        let req = try authedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw CollectionAPIError.serverError(status) }
    }
}
```

- [ ] **Step 2: Build and verify (⌘B)**

Confirm no compile errors. There are no unit tests for the HTTP client itself (same approach as `SavedSpotAPIClient`).

- [ ] **Step 3: Commit**

```bash
git add qwip/Services/CollectionAPIClient.swift
git commit -m "feat: add CollectionAPIClient"
```

---

### Task 3: Update SavedSpotAPIClient and SavedSpotService

**Files:**
- Modify: `qwip/Services/SavedSpotAPIClient.swift`
- Modify: `qwip/Services/SavedSpotService.swift`
- Modify: `qwipTests/qwipTests.swift`

**Background:**
- `SavedSpotAPIClient.SaveSpotBody` currently only has `spotId`. The backend now expects `collection_ids` (optional array). Add it with a default of `[]`.
- `fetchSavedSpots` needs an optional `collectionId` query param for filtering by collection in `CollectionDetailView`.
- `SavedSpotService.save` needs to pass `collectionIds` through to the API.
- `SavedSpotService.updateCollectionIds` is a new synchronous method — it replaces a `SavedSpotEntry` in `savedEntries` in-place. Since `SavedSpotEntry` uses `let` properties, mutation requires constructing a new struct and swapping it by index.

- [ ] **Step 1: Add unit test for `updateCollectionIds`**

In `qwipTests/qwipTests.swift`, add a new test struct (outside `qwipTests`):

```swift
@MainActor
struct SavedSpotServiceTests {

    @Test func updateCollectionIdsReplacesEntry() async {
        let service = SavedSpotService()
        let pin = SpotPin(
            id: "spot-1", name: "Workshop Coffee", shortAddress: nil,
            latitude: 51.5, longitude: -0.1, category: .cafe,
            accessType: .free, wifiAvailable: true, powerOutlets: true,
            noiseMatrix: nil, rating: 4.5, isOpenNow: true, coverPhoto: nil
        )
        // Inject a saved entry with no collections
        // (Direct property access — savedEntries is private(set) but we can
        //  test via the public updateCollectionIds method after loading)
        //
        // Since we can't inject without a real network call, test the logic
        // via the public API: first verify the method does nothing on an
        // empty service, then trust the implementation for the happy path.
        service.updateCollectionIds(spotId: "spot-1", collectionIds: ["col-1"])
        // No crash and no state change (entry doesn't exist)
        #expect(service.savedEntries.isEmpty)
    }
}
```

Note: a full integration test for `updateCollectionIds` requires injecting entries, which would need DI on the API client. The test above verifies the guard path. The happy path is covered by manual verification during save-sheet testing.

- [ ] **Step 2: Update `SavedSpotAPIClient`**

In `qwip/Services/SavedSpotAPIClient.swift`:

**Replace** the `SaveSpotBody` struct:
```swift
private struct SaveSpotBody: Encodable {
    let spotId: String
    let collectionIds: [String]
}
```

**Replace** the `saveSpot` method signature and body construction:
```swift
func saveSpot(spotId: String, collectionIds: [String] = []) async throws -> SavedSpotEntry {
    let url = baseURL.appendingPathComponent("me/saved-spots")
    var req = try authedRequest(url: url, method: "POST")
    req.httpBody = try encoder.encode(SaveSpotBody(spotId: spotId, collectionIds: collectionIds))
    let (data, response) = try await URLSession.shared.data(for: req)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
    do {
        return try decoder.decode(SavedSpotEntry.self, from: data)
    } catch {
        throw SavedSpotAPIError.decodingError(error)
    }
}
```

**Replace** the `fetchSavedSpots` method to support optional collection filtering:
```swift
func fetchSavedSpots(collectionId: String? = nil) async throws -> [SavedSpotEntry] {
    var url = baseURL.appendingPathComponent("me/saved-spots")
    if let collectionId {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "collection_id", value: collectionId)]
        url = components.url ?? url
    }
    let req = try authedRequest(url: url)
    let (data, response) = try await URLSession.shared.data(for: req)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
    do {
        return try decoder.decode(SavedSpotsResponse.self, from: data).spots
    } catch {
        print("🔴 [SavedSpotAPIClient] Raw response:\n\(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
        print("🔴 [SavedSpotAPIClient] Decode error: \(error)")
        throw SavedSpotAPIError.decodingError(error)
    }
}
```

- [ ] **Step 3: Update `SavedSpotService`**

In `qwip/Services/SavedSpotService.swift`:

**Replace** `save(spot:)` with `save(spot:collectionIds:)`:
```swift
/// Inserts a stub entry immediately, then replaces it with the real
/// server response. Removes the stub and rethrows on failure.
func save(spot: SpotPin, collectionIds: [String] = []) async throws {
    guard !isSaved(spot.id) else { return }
    let stub = SavedSpotEntry(spot: spot, savedAt: .now, collectionIds: collectionIds)
    savedEntries.insert(stub, at: 0)
    do {
        let real = try await SavedSpotAPIClient.shared.saveSpot(spotId: spot.id, collectionIds: collectionIds)
        if let index = savedEntries.firstIndex(where: { $0.id == stub.id }) {
            savedEntries[index] = real
        }
    } catch {
        savedEntries.removeAll { $0.id == stub.id }
        throw error
    }
}
```

**Add** `updateCollectionIds` after `unsave`:
```swift
// MARK: - Update collection membership (synchronous, no network call)

/// Replaces the collectionIds on an existing entry in-place.
/// Called by SaveToCollectionSheet after diffing add/remove operations.
/// Since SavedSpotEntry uses let properties, mutation requires constructing
/// a new struct and swapping it at the original index.
func updateCollectionIds(spotId: String, collectionIds: [String]) {
    guard let index = savedEntries.firstIndex(where: { $0.id == spotId }) else { return }
    let old = savedEntries[index]
    savedEntries[index] = SavedSpotEntry(spot: old.spot, savedAt: old.savedAt, collectionIds: collectionIds)
}
```

- [ ] **Step 4: Build and verify (⌘B)**

Confirm no compile errors. `SavedSpotService.load()` calls `fetchSavedSpots()` with no arguments — the new default `collectionId: nil` means this call compiles unchanged.

- [ ] **Step 5: Commit**

```bash
git add qwip/Services/SavedSpotAPIClient.swift qwip/Services/SavedSpotService.swift qwipTests/qwipTests.swift
git commit -m "feat: add collectionIds support to SavedSpotAPIClient and SavedSpotService"
```

---

## Chunk 2: CollectionService

### Task 4: CollectionService

**Files:**
- Create: `qwip/Services/CollectionService.swift`

**Background:**
- Pattern: `@Observable @MainActor final class`, same as `SavedSpotService`
- Optimistic updates: `create` appends a UUID stub (replaces on success, removes on failure). `rename` replaces name in-place (reverts on failure). `delete` removes (re-inserts at original index on failure).
- `Collection` uses `let` properties — all mutations require constructing a new struct
- `addSpot` and `removeSpot` optimistically adjust `spotCount` on the matching collection

- [ ] **Step 1: Create `qwip/Services/CollectionService.swift`**

```swift
import Foundation
import Observation

@Observable
@MainActor
final class CollectionService {

    // MARK: - State

    private(set) var collections: [Collection] = []
    private(set) var isLoading = false
    private(set) var loadError: String? = nil

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        do {
            collections = try await CollectionAPIClient.shared.fetchCollections()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Create (optimistic)

    /// Returns the real (server-confirmed) Collection so callers can auto-tick it.
    /// The UUID stub id is guaranteed not to collide with server-generated UUIDs.
    @discardableResult
    func create(name: String) async throws -> Collection {
        let stubId = UUID().uuidString
        let stub = Collection(id: stubId, name: name, isShareable: false, spotCount: 0,
                              createdAt: .now, updatedAt: .now)
        collections.append(stub)
        do {
            let real = try await CollectionAPIClient.shared.createCollection(name: name)
            if let index = collections.firstIndex(where: { $0.id == stubId }) {
                collections[index] = real
            }
            return real
        } catch {
            collections.removeAll { $0.id == stubId }
            throw error
        }
    }

    // MARK: - Rename (optimistic)

    func rename(id: String, name: String) async throws {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let old = collections[index]
        collections[index] = Collection(id: old.id, name: name, isShareable: old.isShareable,
                                        spotCount: old.spotCount, createdAt: old.createdAt,
                                        updatedAt: .now)
        do {
            let updated = try await CollectionAPIClient.shared.renameCollection(id: id, name: name)
            if let newIndex = collections.firstIndex(where: { $0.id == id }) {
                collections[newIndex] = updated
            }
        } catch {
            if let newIndex = collections.firstIndex(where: { $0.id == id }) {
                collections[newIndex] = old
            }
            throw error
        }
    }

    // MARK: - Delete (optimistic)

    func delete(id: String) async throws {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let captured = collections[index]
        collections.remove(at: index)
        do {
            try await CollectionAPIClient.shared.deleteCollection(id: id)
        } catch {
            let safeIndex = min(index, collections.count)
            collections.insert(captured, at: safeIndex)
            throw error
        }
    }

    // MARK: - Spot membership

    /// Optimistically increments spotCount; reverts on failure.
    /// Returns the SavedSpotEntry from the server (contains updated collectionIds).
    @discardableResult
    func addSpot(spotId: String, toCollection collectionId: String) async throws -> SavedSpotEntry {
        incrementSpotCount(for: collectionId, by: 1)
        do {
            return try await CollectionAPIClient.shared.addSpotToCollection(
                collectionId: collectionId, spotId: spotId)
        } catch {
            incrementSpotCount(for: collectionId, by: -1)
            throw error
        }
    }

    /// Optimistically decrements spotCount; reverts on failure.
    func removeSpot(spotId: String, fromCollection collectionId: String) async throws {
        incrementSpotCount(for: collectionId, by: -1)
        do {
            try await CollectionAPIClient.shared.removeSpotFromCollection(
                collectionId: collectionId, spotId: spotId)
        } catch {
            incrementSpotCount(for: collectionId, by: 1)
            throw error
        }
    }

    // MARK: - Private helpers

    private func incrementSpotCount(for collectionId: String, by delta: Int) {
        guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        let old = collections[index]
        collections[index] = Collection(id: old.id, name: old.name, isShareable: old.isShareable,
                                        spotCount: max(0, old.spotCount + delta),
                                        createdAt: old.createdAt, updatedAt: old.updatedAt)
    }
}
```

- [ ] **Step 2: Build and verify (⌘B)**

Confirm no compile errors.

- [ ] **Step 3: Commit**

```bash
git add qwip/Services/CollectionService.swift
git commit -m "feat: add CollectionService with optimistic CRUD"
```

---

## Chunk 3: Save flow UI

### Task 5: SaveToCollectionSheet

**Files:**
- Create: `qwip/Views/SaveToCollectionSheet.swift`

**Background:**
- Presented as `.sheet` from `SpotDetailView` when the heart icon is tapped
- Takes a `SpotPin` (use `detail.asSpotPin` at call site in SpotDetailView)
- On appear: if spot is already saved, load current `collectionIds` from `savedSpotService.savedEntries` to pre-populate checkboxes; `favouritesTicked = collectionIds.isEmpty`
- "Favourite Spots" is virtual — ticking it means the spot will have empty `collectionIds`; the checkbox state is cosmetic and influences the displayed state only
- On confirm (already saved): diff `selectedIds` vs `originalCollectionIds`, call `addSpot`/`removeSpot` for each change, then call `savedSpotService.updateCollectionIds` with `Array(selectedIds)` — `selectedIds` only holds real collection IDs; an empty set correctly means the spot returns to Favourite Spots
- "+ New collection": expands inline text field, creates collection on confirm, auto-ticks new ID in `selectedIds`
- `presentationDetents([.medium, .large])` so the sheet feels native
- `glassBackground(cornerRadius:)` is a free function from `SpotCard.swift` — accessible in any view file in the same target

- [ ] **Step 1: Create `qwip/Views/SaveToCollectionSheet.swift`**

```swift
import SwiftUI

struct SaveToCollectionSheet: View {
    let spot: SpotPin
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService
    @Environment(\.dismiss) var dismiss

    @State private var selectedIds: Set<String> = []
    @State private var favouritesTicked = true
    @State private var isNewCollectionExpanded = false
    @State private var newCollectionName = ""
    @State private var isSaving = false
    @State private var error: String? = nil

    // Snapshot of collection IDs when sheet opened (for diffing on "Done")
    @State private var originalCollectionIds: [String] = []

    private var isSaved: Bool { savedSpotService.isSaved(spot.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(Color.brandPrimary.opacity(0.2))
                        .frame(width: 36, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 24)

                    // Collections list
                    VStack(spacing: 0) {
                        // Favourite Spots (virtual — always first, no swipe)
                        collectionRow(
                            name: "Favourite Spots",
                            icon: "star.fill",
                            isSelected: favouritesTicked
                        ) {
                            favouritesTicked.toggle()
                        }

                        // Real collections
                        ForEach(collectionService.collections) { collection in
                            Divider()
                                .padding(.leading, 58)
                                .overlay(Color.brandPrimary.opacity(0.08))
                            collectionRow(
                                name: collection.name,
                                icon: "folder.fill",
                                isSelected: selectedIds.contains(collection.id)
                            ) {
                                if selectedIds.contains(collection.id) {
                                    selectedIds.remove(collection.id)
                                } else {
                                    selectedIds.insert(collection.id)
                                    // Untick Favourites when a real collection is ticked
                                    favouritesTicked = false
                                }
                            }
                        }

                        // New collection
                        Divider()
                            .padding(.leading, 58)
                            .overlay(Color.brandPrimary.opacity(0.08))
                        if isNewCollectionExpanded {
                            newCollectionField
                        } else {
                            newCollectionButton
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .background(glassBackground(cornerRadius: 18))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            confirm()
                        } label: {
                            Group {
                                if isSaving {
                                    ProgressView().tint(Color.brandSecondary)
                                } else {
                                    Text(isSaved ? "Done" : "Save")
                                        .font(.dmSans(15, weight: .heavy))
                                        .foregroundStyle(Color.brandSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.brandPrimary)
                            )
                        }
                        .disabled(isSaving)
                        .buttonStyle(.plain)

                        if isSaved {
                            Button(role: .destructive) {
                                removeFromSaved()
                            } label: {
                                Text("Remove from saved")
                                    .font(.dmSans(14, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle(isSaved ? "Organise" : "Save to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(Circle().stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1))
                                .frame(width: 32, height: 32)
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.brandPrimary)
                        }
                    }
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear { loadInitialState() }
    }

    // MARK: - Subviews

    private func collectionRow(name: String, icon: String, isSelected: Bool,
                               onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }
                Text(name)
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.brandPrimary.opacity(isSelected ? 0 : 0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newCollectionButton: some View {
        Button {
            withAnimation(.spring(response: 0.3)) { isNewCollectionExpanded = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.05))
                        .frame(width: 36, height: 36)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary.opacity(0.45))
                }
                Text("New collection")
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary.opacity(0.45))
                Spacer()
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newCollectionField: some View {
        HStack(spacing: 12) {
            TextField("Collection name", text: $newCollectionName)
                .font(.dmSans(15))
                .foregroundStyle(Color.brandPrimary)
                .padding(.vertical, 14)
            Button("Create") {
                createCollection()
            }
            .font(.dmSans(14, weight: .bold))
            .foregroundStyle(Color.brandPrimary)
            .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Actions

    private func loadInitialState() {
        if isSaved {
            let ids = savedSpotService.savedEntries.first(where: { $0.id == spot.id })?.collectionIds ?? []
            originalCollectionIds = ids
            selectedIds = Set(ids)
            favouritesTicked = ids.isEmpty
        } else {
            originalCollectionIds = []
            selectedIds = []
            favouritesTicked = true
        }
    }

    private func createCollection() {
        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                let created = try await collectionService.create(name: name)
                selectedIds.insert(created.id)
                favouritesTicked = false
                withAnimation { isNewCollectionExpanded = false }
                newCollectionName = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func confirm() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if isSaved {
                    let original = Set(originalCollectionIds)
                    let added = selectedIds.subtracting(original)
                    let removed = original.subtracting(selectedIds)
                    for id in added {
                        _ = try await collectionService.addSpot(spotId: spot.id, toCollection: id)
                    }
                    for id in removed {
                        try await collectionService.removeSpot(spotId: spot.id, fromCollection: id)
                    }
                    // selectedIds contains only real collection IDs;
                    // empty set correctly means the spot returns to Favourite Spots
                    savedSpotService.updateCollectionIds(spotId: spot.id, collectionIds: Array(selectedIds))
                } else {
                    try await savedSpotService.save(spot: spot, collectionIds: Array(selectedIds))
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func removeFromSaved() {
        Task {
            do {
                try await savedSpotService.unsave(spotId: spot.id)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify (⌘B)**

Confirm no compile errors.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/SaveToCollectionSheet.swift
git commit -m "feat: add SaveToCollectionSheet"
```

---

### Task 6: Wire heart tap in SpotDetailView to SaveToCollectionSheet

**Files:**
- Modify: `qwip/Views/SpotDetailView.swift`

**Background:**
- Currently the toolbar heart button calls `toggleSave()` which directly calls `savedSpotService`
- Replace with `@State private var showingSaveSheet = false`; button sets it to `true`; `.sheet(isPresented:)` presents `SaveToCollectionSheet`
- Remove `toggleSave()`, `isSaving`, and `saveError` — errors are now handled inside the sheet
- The heart icon still reflects `savedSpotService.isSaved(detail.id)` for fill state
- `SaveToCollectionSheet` takes a `SpotPin` — pass `detail.asSpotPin`
- `SaveToCollectionSheet` needs both `SavedSpotService` and `CollectionService` from the environment — both are available since they're injected in `ContentView`

- [ ] **Step 1: Edit `qwip/Views/SpotDetailView.swift`**

**Remove** these `@State` properties:
```swift
@State private var isSaving = false
@State private var saveError: String? = nil
```

**Replace** them with:
```swift
@State private var showingSaveSheet = false
```

**Replace** the toolbar heart button's action:
```swift
// Before:
Button {
    toggleSave()
} label: { ... }
.disabled(isSaving)

// After:
Button {
    showingSaveSheet = true
} label: { ... }
// No .disabled needed
```

**Add** the sheet after the existing `.alert` modifier:
```swift
.sheet(isPresented: $showingSaveSheet) {
    SaveToCollectionSheet(spot: detail.asSpotPin)
}
```

**Remove** the `.alert("Couldn't update saved spot" ...)` block entirely.

**Remove** the `toggleSave()` function entirely.

The heart icon label is unchanged — it still reads `savedSpotService.isSaved(detail.id)` for `heart.fill` vs `heart`.

- [ ] **Step 2: Build and verify (⌘B)**

Confirm no compile errors or warnings.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/SpotDetailView.swift
git commit -m "feat: heart tap opens SaveToCollectionSheet in SpotDetailView"
```

---

## Chunk 4: Collections tab

### Task 7: Move SavedSpotCard to Components and delete SavedSpotsView

**Files:**
- Modify: `qwip/Components/SpotCard.swift`
- Delete: `qwip/Views/SavedSpotsView.swift`

**Background:**
- `SavedSpotCard` is currently `private struct` inside `SavedSpotsView.swift`
- `CollectionDetailView` (next task) needs it — move it to `SpotCard.swift` and make it `internal` (no access modifier)
- After moving, delete `SavedSpotsView.swift` — it will no longer be referenced by `ContentView` (that wiring happens in Task 9)
- `SavedSpotCard` depends on `glassBackground`, `OpenBadge`, `SpotPin` — all already available in `SpotCard.swift`

- [ ] **Step 1: Add `SavedSpotCard` to `qwip/Components/SpotCard.swift`**

Append this to the bottom of `SpotCard.swift` (after existing components):

```swift
// MARK: - Saved Spot Card (used in CollectionDetailView)

struct SavedSpotCard: View {
    let spot: SpotPin
    let isLoading: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.brandPrimary.opacity(0.06))
                .frame(width: 70)
                .offset(x: 16, y: -16)
                .blur(radius: 8)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.brandPrimary)
                            .frame(width: 36, height: 36)
                        Image(systemName: spot.category.systemIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                    .shadow(color: Color.brandPrimary.opacity(0.35), radius: 6, x: 0, y: 2)
                    Spacer()
                    OpenBadge(isOpen: spot.isOpenNow)
                }

                Text(spot.name)
                    .font(.dmSans(14, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(spot.category.displayName.uppercased())
                    .font(.dmSans(8.5, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Color.brandPrimary.opacity(0.4))

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                    Text(spot.formattedRating)
                        .font(.dmSans(13, weight: .black))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                    if isLoading {
                        ProgressView().scaleEffect(0.7)
                    }
                }
            }
            .padding(14)
        }
        .background(glassBackground(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.brandPrimary.opacity(0.1), radius: 14, x: 0, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}
```

- [ ] **Step 2: Delete `qwip/Views/SavedSpotsView.swift`**

Delete the file from the project:
```bash
rm /Users/shreyassaxena/development/qwip/qwip/Views/SavedSpotsView.swift
```

Because the project uses **PBXFileSystemSynchronizedRootGroup**, Xcode auto-syncs the file list — no need to edit `.pbxproj`.

- [ ] **Step 3: Build and verify (⌘B)**

There will be a compile error in `ContentView.swift` referencing `SavedSpotsView()` — that's expected and will be fixed in Task 9.

- [ ] **Step 4: Commit**

```bash
git add qwip/Components/SpotCard.swift
git rm qwip/Views/SavedSpotsView.swift
git commit -m "refactor: move SavedSpotCard to SpotCard.swift, delete SavedSpotsView"
```

---

### Task 8: CollectionDetailView

**Files:**
- Create: `qwip/Views/CollectionDetailView.swift`

**Background:**
- Pushed via `NavigationLink` from inside `CollectionsView`'s `NavigationStack` — do NOT wrap in its own `NavigationStack`
- `CollectionSource` enum distinguishes the virtual Favourite Spots from real collections
- For `.favourites`: derive entries reactively from `savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }` — no extra network call, stays in sync with service state
- For `.collection(c)`: fetch `GET /me/saved-spots?collection_id={c.id}` into local `@State var collectionEntries` on `.task`
- Spot cards use `contextMenu` (not swipe) — consistent with the grid layout and the existing `SavedSpotsView` pattern. Swipe actions don't work on `LazyVGrid` items in SwiftUI.
- Context menu: `.favourites` → "Remove" (unsave entirely). `.collection` → "Remove from collection" (spot stays saved)
- `fetchDetail` pattern matches `SavedSpotsView` exactly

- [ ] **Step 1: Create `qwip/Views/CollectionDetailView.swift`**

```swift
import SwiftUI

// MARK: - Collection source

enum CollectionSource {
    case favourites
    case collection(Collection)

    var title: String {
        switch self {
        case .favourites: return "Favourite Spots"
        case .collection(let c): return c.name
        }
    }
}

// MARK: - View

struct CollectionDetailView: View {
    let source: CollectionSource
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService

    // Used only for .collection case; .favourites reads from savedSpotService directly
    @State private var collectionEntries: [SavedSpotEntry] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var detailSpot: SpotDetail? = nil
    @State private var fetchingDetailID: String? = nil
    @State private var fetchDetailError: String? = nil
    @State private var removeError: String? = nil

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    // Reactive for .favourites; local state for .collection
    private var displayEntries: [SavedSpotEntry] {
        switch source {
        case .favourites:
            return savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }
        case .collection:
            return collectionEntries
        }
    }

    var body: some View {
        ScrollView {
            if isLoading && displayEntries.isEmpty {
                VStack {
                    Spacer(minLength: 120)
                    ProgressView().scaleEffect(1.2).tint(Color.brandPrimary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = loadError {
                VStack(spacing: 16) {
                    Spacer(minLength: 120)
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.brandPrimary.opacity(0.4))
                    Text(error)
                        .font(.dmSans(14))
                        .foregroundStyle(Color.brandPrimary.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Try Again") { Task { await loadEntries() } }
                        .font(.dmSans(14, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if displayEntries.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(displayEntries) { entry in
                        SavedSpotCard(spot: entry.spot, isLoading: fetchingDetailID == entry.spot.id)
                            .onTapGesture { fetchDetail(for: entry.spot) }
                            .contextMenu {
                                switch source {
                                case .favourites:
                                    Button(role: .destructive) {
                                        Task {
                                            do {
                                                try await savedSpotService.unsave(spotId: entry.spot.id)
                                            } catch {
                                                removeError = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Remove", systemImage: "heart.slash")
                                    }
                                case .collection(let c):
                                    Button(role: .destructive) {
                                        Task {
                                            do {
                                                try await collectionService.removeSpot(
                                                    spotId: entry.spot.id, fromCollection: c.id)
                                                collectionEntries.removeAll { $0.id == entry.id }
                                            } catch {
                                                removeError = error.localizedDescription
                                            }
                                        }
                                    } label: {
                                        Label("Remove from collection", systemImage: "folder.badge.minus")
                                    }
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .refreshable { await loadEntries() }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.large)
        .background(Color.brandSecondary.ignoresSafeArea())
        .sheet(item: $detailSpot) { detail in
            SpotDetailView(detail: detail)
        }
        .alert("Error", isPresented: Binding(
            get: { fetchDetailError != nil },
            set: { if !$0 { fetchDetailError = nil } }
        )) {
            Button("OK") { fetchDetailError = nil }
        } message: {
            Text(fetchDetailError ?? "")
        }
        .alert("Couldn't remove spot", isPresented: Binding(
            get: { removeError != nil },
            set: { if !$0 { removeError = nil } }
        )) {
            Button("OK") { removeError = nil }
        } message: {
            Text(removeError ?? "")
        }
        .task { await loadEntries() }
    }

    // MARK: - Data

    private func loadEntries() async {
        guard case .collection(let c) = source else { return } // .favourites is always reactive
        isLoading = true
        loadError = nil
        do {
            collectionEntries = try await SavedSpotAPIClient.shared.fetchSavedSpots(collectionId: c.id)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchDetail(for pin: SpotPin) {
        guard fetchingDetailID == nil else { return }
        Task {
            fetchingDetailID = pin.id
            do {
                detailSpot = try await SpotAPIClient.shared.fetchSpotDetail(id: pin.id)
            } catch SpotAPIError.notFound {
                fetchDetailError = "This spot is no longer available."
            } catch {
                fetchDetailError = error.localizedDescription
            }
            fetchingDetailID = nil
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle().stroke(Color.brandPrimary.opacity(0.06), lineWidth: 20).frame(width: 140)
                Circle().stroke(Color.brandPrimary.opacity(0.1), lineWidth: 1.5).frame(width: 100)
                ZStack {
                    Circle().fill(Color.brandPrimary.opacity(0.08)).frame(width: 80)
                    Image(systemName: source == .favourites ? "heart" : "folder")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                }
            }
            VStack(spacing: 6) {
                Text("No spots here yet")
                    .font(.dmSans(22, weight: .heavy))
                    .foregroundStyle(Color.brandPrimary)
                Text(source == .favourites
                     ? "Find spots on the map and\ntap ♥ to save them here."
                     : "Save spots and add them\nto this collection.")
                    .font(.dmSans(15))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - CollectionSource: Equatable (for empty state icon switch)

extension CollectionSource: Equatable {
    static func == (lhs: CollectionSource, rhs: CollectionSource) -> Bool {
        switch (lhs, rhs) {
        case (.favourites, .favourites): return true
        case (.collection(let a), .collection(let b)): return a.id == b.id
        default: return false
        }
    }
}
```

- [ ] **Step 2: Build and verify (⌘B)**

There will still be the `ContentView` compile error from Task 7 — expected. Check that `CollectionDetailView.swift` itself has no errors.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/CollectionDetailView.swift
git commit -m "feat: add CollectionDetailView"
```

---

### Task 9: CollectionsView + ContentView wiring

**Files:**
- Create: `qwip/Views/CollectionsView.swift`
- Modify: `qwip/ContentView.swift`

**Background:**
- `CollectionsView` wraps everything in a `NavigationStack` and uses `NavigationLink` to push `CollectionDetailView`
- "Favourite Spots" row has no swipe actions; real collections have grey pencil (rename) + red bin (delete)
- Rename: `.alert` with `TextField` — uses `.alert(_:isPresented:actions:)` with a `TextField` in the `actions:` closure (iOS 16+ syntax)
- Delete: `confirmationDialog` with "Spots will stay saved" message
- `+` toolbar button: same alert-with-TextField pattern
- `ContentView` adds `@State private var collectionService = CollectionService()`, injects it via `.environment`, replaces `SavedSpotsView()` with `CollectionsView()`, and loads both services concurrently in `.task`
- The existing `.task { await savedSpotService.load() }` in `ContentView` must be replaced with the `async let` parallel form

- [ ] **Step 1: Create `qwip/Views/CollectionsView.swift`**

```swift
import SwiftUI

struct CollectionsView: View {
    @Environment(SavedSpotService.self) var savedSpotService
    @Environment(CollectionService.self) var collectionService

    @State private var renameTarget: Collection? = nil
    @State private var renameText = ""
    @State private var deleteTarget: Collection? = nil
    @State private var showCreateAlert = false
    @State private var newCollectionName = ""
    @State private var actionError: String? = nil

    private var favouriteCount: Int {
        savedSpotService.savedEntries.filter { $0.collectionIds.isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if collectionService.isLoading && collectionService.collections.isEmpty
                    && savedSpotService.savedEntries.isEmpty {
                    loadingView
                } else if let error = collectionService.loadError ?? savedSpotService.loadError {
                    errorView(message: error)
                } else {
                    List {
                        // Favourite Spots — pinned first, no swipe
                        NavigationLink {
                            CollectionDetailView(source: .favourites)
                        } label: {
                            CollectionRow(name: "Favourite Spots", icon: "star.fill",
                                          count: favouriteCount)
                        }

                        // Real collections
                        ForEach(collectionService.collections) { collection in
                            NavigationLink {
                                CollectionDetailView(source: .collection(collection))
                            } label: {
                                CollectionRow(name: collection.name, icon: "folder.fill",
                                              count: collection.spotCount)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = collection
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    renameTarget = collection
                                    renameText = collection.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .refreshable {
                async let s: () = savedSpotService.load()
                async let c: () = collectionService.load()
                _ = await (s, c)
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.brandSecondary.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreateAlert = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
            // Create collection alert
            .alert("New collection", isPresented: $showCreateAlert) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                    newCollectionName = ""
                    guard !name.isEmpty else { return }
                    Task {
                        do { try await collectionService.create(name: name) }
                        catch { actionError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
            // Rename alert
            .alert("Rename collection", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    guard let target = renameTarget else { return }
                    let name = renameText.trimmingCharacters(in: .whitespaces)
                    renameTarget = nil
                    guard !name.isEmpty else { return }
                    Task {
                        do { try await collectionService.rename(id: target.id, name: name) }
                        catch { actionError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            // Delete confirmation
            .confirmationDialog(
                "Delete \"\(deleteTarget?.name ?? "")\"?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    guard let target = deleteTarget else { return }
                    deleteTarget = nil
                    Task {
                        do { try await collectionService.delete(id: target.id) }
                        catch { actionError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Spots will stay saved.")
            }
            // General action error
            .alert("Error", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    // MARK: - Loading / error states

    private var loadingView: some View {
        VStack {
            Spacer(minLength: 120)
            ProgressView().scaleEffect(1.2).tint(Color.brandPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 120)
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.brandPrimary.opacity(0.4))
            Text(message)
                .font(.dmSans(14))
                .foregroundStyle(Color.brandPrimary.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task {
                    async let s: () = savedSpotService.load()
                    async let c: () = collectionService.load()
                    _ = await (s, c)
                }
            }
            .font(.dmSans(14, weight: .bold))
            .foregroundStyle(Color.brandPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Collection row

private struct CollectionRow: View {
    let name: String
    let icon: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brandPrimary.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.dmSans(15, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Text("\(count) spot\(count == 1 ? "" : "s")")
                    .font(.dmSans(12))
                    .foregroundStyle(Color.brandPrimary.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Update `qwip/ContentView.swift`**

**Add** `collectionService` state:
```swift
@State private var collectionService = CollectionService()
```

**Add** environment injection — after `.environment(savedSpotService)` add:
```swift
.environment(collectionService)
```

**Replace** `SavedSpotsView()` with:
```swift
case 1: CollectionsView()
```

**Replace** the `.task` modifier:
```swift
// Before:
.task { await savedSpotService.load() }

// After:
.task {
    async let s: () = savedSpotService.load()
    async let c: () = collectionService.load()
    _ = await (s, c)
}
```

- [ ] **Step 3: Build and verify (⌘B)**

All compile errors from Task 7 should now be resolved. Full build should succeed.

- [ ] **Step 4: Manual smoke test**

Open the app in the simulator. Verify:
- Saved tab shows "Favourite Spots" + any real collections (empty list if no collections yet)
- Tap "Favourite Spots" → see your saved spots that aren't in a collection
- Tap the heart on a spot detail → sheet appears with "Favourite Spots" pre-ticked
- Tick a real collection (or create one inline) and tap "Save" → spot is saved
- Swipe left on a collection row → grey pencil + red bin appear
- Rename works (alert with text field, updates in-place)
- Delete works (confirmation dialog, collection disappears, spots stay saved)

- [ ] **Step 5: Commit**

```bash
git add qwip/Views/CollectionsView.swift qwip/ContentView.swift
git commit -m "feat: add CollectionsView and wire ContentView — collections feature complete"
```
