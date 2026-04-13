# Saved Spots Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace local `savedSpotIDs: Set<String>` in `SpotStore` with a real backend-backed `SavedSpotService` that syncs saved spots via the `/me/saved-spots` API with optimistic updates.

**Architecture:** A new `SavedSpotService` (@Observable, @MainActor) owns `savedEntries: [SavedSpotEntry]` as the single source of truth. A new `SavedSpotAPIClient` handles the three authenticated endpoints. `SpotStore` loses all saved-state logic. Views wire to `SavedSpotService` via `@Environment`.

**Tech Stack:** Swift 5.9, SwiftUI (iOS 17+), @Observable, Supabase Swift SDK, async/await, URLSession

**Spec:** `docs/superpowers/specs/2026-03-15-saved-spots-phase1-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Modify | `qwip/Models/Spot.swift` | Add `SavedSpotEntry`, `SpotDetail.asSpotPin` |
| Modify | `qwip/Services/SpotStore.swift` | Remove all saved-state properties and methods |
| Create | `qwip/Services/SavedSpotAPIClient.swift` | Network calls for `/me/saved-spots` endpoints |
| Create | `qwip/Services/SavedSpotService.swift` | Observable service; owns `savedEntries`, optimistic save/unsave |
| Modify | `qwip/ContentView.swift` | Own and inject `SavedSpotService`; trigger initial load |
| Modify | `qwip/Views/SpotDetailView.swift` | Wire both heart buttons to `SavedSpotService` |
| Modify | `qwip/Views/SavedSpotsView.swift` | Replace `SpotStore` data source; add refresh, context menu, error/loading states |

> **Note on build state:** Tasks 1–6 each leave the project in a compilable state. Task 7 removes saved-state from `SpotStore` **and** wires `SavedSpotsView` in a single commit, so the only non-compiling window is the time between those two edits within a single task.

---

## Chunk 1: Data Model

### Task 1: Add `SavedSpotEntry` and `SpotDetail.asSpotPin` to `Spot.swift`

**Files:**
- Modify: `qwip/Models/Spot.swift`

- [ ] **Step 1: Verify the API response shape before writing the decoder**

Run a quick check to confirm the GET /me/saved-spots response nests the spot object under a `"spot"` key (rather than returning its fields flat at the top level). You can do this with a curl call using a valid session token, or by checking any existing API contract / Postman collection. **If the spot fields are flat (not nested under `"spot"`), the synthesised `Codable` on `SavedSpotEntry` will silently return decoding errors — a custom `init(from:)` will be required before proceeding.**

- [ ] **Step 2: Add `SavedSpotEntry` to `Spot.swift`**

Open `qwip/Models/Spot.swift`. Append the following after the closing brace of `SpotDetail`:

```swift
// MARK: - SavedSpotEntry  (GET /me/saved-spots item)

struct SavedSpotEntry: Identifiable, Codable {
    let spot: SpotPin
    let savedAt: Date
    let collectionIds: [String]

    /// Stable identity uses the nested spot's ID.
    var id: String { spot.id }
}
```

The decoder's `.convertFromSnakeCase` strategy maps `saved_at` → `savedAt` and `collection_ids` → `collectionIds` automatically. The `id` computed property is not stored, so it does not participate in Codable synthesis.

- [ ] **Step 3: Add `SpotDetail.asSpotPin` computed property**

Inside the `SpotDetail` struct body, after the `var displayDescription` computed property, add:

```swift
/// Converts this detail record to the lighter SpotPin type,
/// used to construct optimistic SavedSpotEntry stubs without a network call.
var asSpotPin: SpotPin {
    SpotPin(
        id: id,
        name: name,
        shortAddress: shortAddress,
        latitude: latitude,
        longitude: longitude,
        category: category,
        accessType: accessType,
        wifiAvailable: wifiAvailable,
        powerOutlets: powerOutlets,
        noiseMatrix: noiseMatrix,
        rating: rating,
        isOpenNow: isOpenNow,
        coverPhoto: coverPhoto
    )
}
```

Swift synthesises a memberwise initialiser for `SpotPin` using its stored properties in declaration order. The parameter labels match the property names exactly.

- [ ] **Step 4: Build to verify**

**⌘B** in Xcode. Expected: Build Succeeded with no new errors.

- [ ] **Step 5: Commit**

```bash
git add qwip/Models/Spot.swift
git commit -m "feat: add SavedSpotEntry model and SpotDetail.asSpotPin"
```

---

## Chunk 2: SavedSpotAPIClient

### Task 2: Create `SavedSpotAPIClient`

**Files:**
- Create: `qwip/Services/SavedSpotAPIClient.swift`

- [ ] **Step 1: Create the file**

Create `qwip/Services/SavedSpotAPIClient.swift`:

```swift
import Foundation
import Supabase

// MARK: - Errors

enum SavedSpotAPIError: LocalizedError {
    case notAuthenticated
    case serverError(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to save spots."
        case .serverError(let code):
            return "Server error (\(code))."
        case .decodingError:
            return "Couldn't parse the server response."
        }
    }
}

// MARK: - Request body

private struct SaveSpotBody: Encodable {
    // Encoded to snake_case ("spot_id") by the encoder's .convertToSnakeCase strategy
    let spotId: String
}

// MARK: - Client

struct SavedSpotAPIClient {
    static let shared = SavedSpotAPIClient()

    private let baseURL = URL(string: "https://spotsvc.up.railway.app")!

    /// Decodes Date fields using Supabase's fractional-second ISO 8601 format.
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

    // MARK: - Auth

    private func bearerToken() throws -> String {
        // currentSession is the synchronous in-memory accessor on GoTrueClient
        guard let token = supabase.auth.currentSession?.accessToken else {
            throw SavedSpotAPIError.notAuthenticated
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

    // MARK: - Endpoints

    /// GET /me/saved-spots — returns all saved spots for the current user, newest first.
    func fetchSavedSpots() async throws -> [SavedSpotEntry] {
        let url = baseURL.appendingPathComponent("me/saved-spots")
        let req = try authedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
        do {
            return try decoder.decode([SavedSpotEntry].self, from: data)
        } catch {
            throw SavedSpotAPIError.decodingError(error)
        }
    }

    /// POST /me/saved-spots — saves a spot and returns the created entry.
    func saveSpot(spotId: String) async throws -> SavedSpotEntry {
        let url = baseURL.appendingPathComponent("me/saved-spots")
        var req = try authedRequest(url: url, method: "POST")
        req.httpBody = try encoder.encode(SaveSpotBody(spotId: spotId))
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
        do {
            return try decoder.decode(SavedSpotEntry.self, from: data)
        } catch {
            throw SavedSpotAPIError.decodingError(error)
        }
    }

    /// DELETE /me/saved-spots/{spotId} — unsaves a spot.
    /// A 404 is treated as success (spot was already not saved).
    func unsaveSpot(spotId: String) async throws {
        let url = baseURL.appendingPathComponent("me/saved-spots/\(spotId)")
        let req = try authedRequest(url: url, method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return }
        guard (200...299).contains(status) else { throw SavedSpotAPIError.serverError(status) }
    }
}
```

- [ ] **Step 2: Build to verify**

**⌘B**. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add qwip/Services/SavedSpotAPIClient.swift
git commit -m "feat: add SavedSpotAPIClient for /me/saved-spots endpoints"
```

---

## Chunk 3: SavedSpotService

### Task 3: Create `SavedSpotService`

**Files:**
- Create: `qwip/Services/SavedSpotService.swift`

- [ ] **Step 1: Create the file**

Create `qwip/Services/SavedSpotService.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class SavedSpotService {

    // MARK: - State

    private(set) var savedEntries: [SavedSpotEntry] = []
    private(set) var isLoading = false
    private(set) var loadError: String? = nil

    // MARK: - Read

    func isSaved(_ spotId: String) -> Bool {
        savedEntries.contains { $0.id == spotId }
    }

    // MARK: - Load

    /// Fetches all saved spots. Clears any previous error immediately so
    /// the error banner dismisses as soon as the user taps Retry.
    func load() async {
        isLoading = true
        loadError = nil
        do {
            savedEntries = try await SavedSpotAPIClient.shared.fetchSavedSpots()
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Save (optimistic)

    /// Inserts a stub entry immediately, then replaces it with the real
    /// server response. Removes the stub and rethrows on failure.
    func save(spot: SpotPin) async throws {
        let stub = SavedSpotEntry(spot: spot, savedAt: .now, collectionIds: [])
        savedEntries.insert(stub, at: 0)
        do {
            let real = try await SavedSpotAPIClient.shared.saveSpot(spotId: spot.id)
            if let index = savedEntries.firstIndex(where: { $0.id == stub.id }) {
                savedEntries[index] = real
            }
        } catch {
            savedEntries.removeAll { $0.id == stub.id }
            throw error
        }
    }

    // MARK: - Unsave (optimistic)

    /// Removes the entry immediately, then re-inserts at the original
    /// position if the network call fails.
    func unsave(spotId: String) async throws {
        guard let index = savedEntries.firstIndex(where: { $0.id == spotId }) else { return }
        let captured = savedEntries[index]
        savedEntries.remove(at: index)
        do {
            try await SavedSpotAPIClient.shared.unsaveSpot(spotId: spotId)
        } catch {
            let safeIndex = min(index, savedEntries.count)
            savedEntries.insert(captured, at: safeIndex)
            throw error
        }
    }
}
```

- [ ] **Step 2: Build to verify**

**⌘B**. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add qwip/Services/SavedSpotService.swift
git commit -m "feat: add SavedSpotService with optimistic save/unsave"
```

---

## Chunk 4: UI Wiring

### Task 4: Wire `ContentView`

**Files:**
- Modify: `qwip/ContentView.swift`  ← note: this file is at the root of the `qwip/` target, not inside `Views/`

- [ ] **Step 1: Add `SavedSpotService` ownership, injection, and initial load**

In `ContentView`, add a new `@State` property alongside `store` and `locationService`:

```swift
@State private var savedSpotService = SavedSpotService()
```

Add it to the `.environment` chain on the `Group` (same chain as `store` and `locationService`):

```swift
.environment(store)
.environment(locationService)
.environment(savedSpotService)
```

Add `.task` on the `ZStack` to trigger the initial load. `ContentView` only renders when the user is authenticated (gated by `RootView`), so appearing equals sign-in:

```swift
.task { await savedSpotService.load() }
```

The complete `body` after changes:

```swift
var body: some View {
    ZStack(alignment: .bottom) {
        Group {
            switch selectedTab {
            case 0: MapView()
            case 1: SavedSpotsView()
            default: ProfileView()
            }
        }
        .environment(store)
        .environment(locationService)
        .environment(savedSpotService)

        GlassTabBar(selectedTab: $selectedTab)
    }
    .ignoresSafeArea(edges: .bottom)
    .task { await savedSpotService.load() }
}
```

- [ ] **Step 2: Build to verify**

**⌘B**. Expected: Build Succeeded (pre-existing view errors from SpotStore references are in views not yet modified — no new errors).

- [ ] **Step 3: Commit**

```bash
git add qwip/ContentView.swift
git commit -m "feat: own and inject SavedSpotService in ContentView"
```

---

### Task 5: Wire `SpotDetailView`

**Files:**
- Modify: `qwip/Views/SpotDetailView.swift`

- [ ] **Step 1: Add environment property and new state**

At the top of `SpotDetailView`, alongside the existing `@Environment` declarations, add:

```swift
@Environment(SavedSpotService.self) var savedSpotService
```

Add two new `@State` properties:

```swift
@State private var isSaving = false
@State private var saveError: String? = nil
```

- [ ] **Step 2: Add the shared `toggleSave` function**

Add this private method on `SpotDetailView` alongside the existing helpers:

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

- [ ] **Step 3: Update the toolbar heart button**

Replace the existing `ToolbarItem(placement: .topBarTrailing)` with:

```swift
ToolbarItem(placement: .topBarTrailing) {
    Button {
        toggleSave()
    } label: {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.brandPrimary.opacity(0.12), lineWidth: 1))
                .frame(width: 32, height: 32)
            Image(systemName: savedSpotService.isSaved(detail.id) ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(savedSpotService.isSaved(detail.id) ? Color(hex: "e74c3c") : Color.brandPrimary)
                .contentTransition(.symbolEffect(.replace))
        }
    }
    .disabled(isSaving)
}
```

- [ ] **Step 4: Update the `actionsRow` save button**

Replace the entire `actionsRow` computed property with:

```swift
private var actionsRow: some View {
    let saved = savedSpotService.isSaved(detail.id)
    return HStack(spacing: 12) {

        // Save
        Button {
            toggleSave()
        } label: {
            VStack(spacing: 7) {
                Image(systemName: saved ? "heart.fill" : "heart")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(saved ? Color(hex: "e74c3c") : Color.brandPrimary)
                    .contentTransition(.symbolEffect(.replace))
                Text(saved ? "Saved" : "Save")
                    .font(.dmSans(12, weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(glassBackground(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)

        // Directions — unchanged from original
        Button {
            var urlString = "maps://?daddr=\(detail.latitude),\(detail.longitude)&dirflg=d"
            if let loc = locationService.userLocation {
                urlString += "&saddr=\(loc.coordinate.latitude),\(loc.coordinate.longitude)"
            }
            if let url = URL(string: urlString) { UIApplication.shared.open(url) }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.brandSecondary)
                Text("Directions")
                    .font(.dmSans(12, weight: .bold))
                    .foregroundStyle(Color.brandSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.brandPrimary)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.brandPrimary.opacity(0.4), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 5: Add the `saveError` alert**

Add a second `.alert` to the `NavigationStack` modifier chain, after the existing toolbar:

```swift
.alert("Couldn't update saved spot", isPresented: Binding(
    get: { saveError != nil },
    set: { if !$0 { saveError = nil } }
)) {
    Button("OK") { saveError = nil }
} message: {
    Text(saveError ?? "")
}
```

- [ ] **Step 6: Build to verify `SpotDetailView` errors are resolved**

**⌘B**. Expected: errors in `SpotDetailView` are gone. Errors in `SavedSpotsView` still remain.

- [ ] **Step 7: Commit**

```bash
git add qwip/Views/SpotDetailView.swift
git commit -m "feat: wire SpotDetailView save buttons to SavedSpotService"
```

---

### Task 6: Wire `SavedSpotsView` + remove saved-state from `SpotStore`

These two changes are committed together so every committed state is a green build.

**Files:**
- Modify: `qwip/Views/SavedSpotsView.swift`
- Modify: `qwip/Services/SpotStore.swift`

- [ ] **Step 1: Rewrite `SavedSpotsView`**

The following members from the original file are **retained unchanged**: `detailSpot`, `isFetchingDetail`, `fetchDetailError`, `columns`, `fetchDetail(for:)`, `emptyState`, and `SavedSpotCard`. Only `body` changes, and a new `unsaveError` state is added.

Add to the state declarations:

```swift
@Environment(SavedSpotService.self) var savedSpotService
@State private var unsaveError: String? = nil
```

Replace the `body` computed property:

```swift
var body: some View {
    NavigationStack {
        ScrollView {
            if savedSpotService.isLoading && savedSpotService.savedEntries.isEmpty {
                VStack {
                    Spacer(minLength: 120)
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color.brandPrimary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = savedSpotService.loadError {
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
                    Button("Try Again") {
                        Task { await savedSpotService.load() }
                    }
                    .font(.dmSans(14, weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if savedSpotService.savedEntries.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(savedSpotService.savedEntries) { entry in
                        SavedSpotCard(spot: entry.spot, isLoading: isFetchingDetail)
                            .onTapGesture { fetchDetail(for: entry.spot) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task {
                                        do {
                                            try await savedSpotService.unsave(spotId: entry.spot.id)
                                        } catch {
                                            unsaveError = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    Label("Remove", systemImage: "heart.slash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .refreshable { await savedSpotService.load() }
        .navigationTitle("Saved")
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
            get: { unsaveError != nil },
            set: { if !$0 { unsaveError = nil } }
        )) {
            Button("OK") { unsaveError = nil }
        } message: {
            Text(unsaveError ?? "")
        }
    }
}
```

> Note: `.contextMenu` is applied at the `ForEach` call site on `SavedSpotCard`, not inside the `SavedSpotCard` struct. This gives the context menu access to `savedSpotService` and `entry` without modifying the private card struct.

- [ ] **Step 2: Remove saved-state from `SpotStore`**

Open `qwip/Services/SpotStore.swift`. Delete the following four members:

```swift
var savedSpotIDs: Set<String> = []
```

```swift
var savedSpots: [SpotPin] {
    spots.filter { savedSpotIDs.contains($0.id) }
}
```

```swift
func toggleSave(id: String) {
    if savedSpotIDs.contains(id) {
        savedSpotIDs.remove(id)
    } else {
        savedSpotIDs.insert(id)
    }
}

func isSaved(id: String) -> Bool {
    savedSpotIDs.contains(id)
}
```

Leave all other members (`spots`, `selectedCategory`, `filterOpenNow`, `filterWifi`, `filterNoiseLevel`, `filteredSpots`, `additionalFilterCount`, `hasAdditionalFilters`, `clearAdditionalFilters`, `loadSpots`) untouched.

- [ ] **Step 3: Build — all errors must be gone**

**⌘B**. Expected: **Build Succeeded** with no errors anywhere.

- [ ] **Step 4: Commit both files together**

```bash
git add qwip/Views/SavedSpotsView.swift qwip/Services/SpotStore.swift
git commit -m "feat: wire SavedSpotsView to SavedSpotService; remove saved-state from SpotStore"
```

---

### Task 7: Final verification

- [ ] **Step 1: Check for stale references**

```bash
grep -r "store\.savedSpots\|store\.toggleSave\|store\.isSaved\|savedSpotIDs" qwip/
```

Expected: no matches.

- [ ] **Step 2: Clean build**

In Xcode: **Product → Clean Build Folder** (⌘⇧K), then **⌘B**. Expected: Build Succeeded.

- [ ] **Step 3: Smoke test on simulator**

Run the app. Verify:
1. Sign in → Saved tab shows a brief spinner, then empty state or saved spots list
2. Open a spot detail → tap heart → fills immediately (optimistic), `actionsRow` label updates to "Saved"
3. Tap heart again → empties immediately, label reverts to "Save"
4. Return to Saved tab → spot appears / disappears correctly
5. Pull down on Saved tab → refresh spinner appears, list reloads
6. Long-press a saved spot card → context menu with "Remove" → tapping it removes the card instantly

- [ ] **Step 4: Final commit tag**

```bash
git commit --allow-empty -m "chore: phase 1 complete — saved spots wired to backend"
```
