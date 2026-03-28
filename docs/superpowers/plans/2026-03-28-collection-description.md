# Collection Description Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional `description` field to collections, surfaced in the create/edit form and shown as a subtitle in `CollectionDetailView`.

**Architecture:** `collectionDescription: String?` added to the `Collection` model with a `CodingKeys` mapping to the JSON key `"description"`. The field flows through `CollectionAPIClient` request bodies → `CollectionService` optimistic updates → `CollectionFormSheet` TextField → `CollectionDetailView` subtitle section.

**Tech Stack:** Swift 6, SwiftUI (iOS 17+), Swift Testing (`import Testing`, `@Test`, `#expect`), `@Observable`

**Spec:** `docs/superpowers/specs/2026-03-28-collection-description-design.md`

**Important:** Do NOT run `xcodebuild`. After each task, ask the user to build (Cmd+B) or run tests (Cmd+U) and wait for their confirmation before proceeding.

---

### Task 1: Add `collectionDescription` to `Collection` model and update tests

**Files:**
- Modify: `qwip/Models/Collection.swift`
- Test: `qwipTests/qwipTests.swift`

- [ ] **Step 1: Write failing tests**

Add two new tests to the `qwipTests` struct in `qwipTests/qwipTests.swift`:

```swift
@Test func collectionDecodesNullDescription() throws {
    let json = """
    {
        "id": "abc-123",
        "name": "Morning Cafes",
        "description": null,
        "is_shareable": false,
        "spot_count": 3,
        "created_at": "2026-03-16T09:00:00.000+0000",
        "updated_at": "2026-03-16T09:00:00.000+0000"
    }
    """.data(using: .utf8)!
    let collection = try makeDecoder().decode(Collection.self, from: json)
    #expect(collection.collectionDescription == nil)
}

@Test func collectionDecodesDescription() throws {
    let json = """
    {
        "id": "abc-123",
        "name": "Morning Cafes",
        "description": "Great spots for early birds",
        "is_shareable": false,
        "spot_count": 3,
        "created_at": "2026-03-16T09:00:00.000+0000",
        "updated_at": "2026-03-16T09:00:00.000+0000"
    }
    """.data(using: .utf8)!
    let collection = try makeDecoder().decode(Collection.self, from: json)
    #expect(collection.collectionDescription == "Great spots for early birds")
}
```

Also update the existing `collectionDecodesFromJSON` test — add `"description": null` to the JSON and assert `#expect(collection.collectionDescription == nil)`.

- [ ] **Step 2: Ask user to run tests (Cmd+U) — expect compile error**

Ask the user: "Please do a Cmd+U — expected to fail with `value of type 'Collection' has no member 'collectionDescription'`."

Wait for confirmation before continuing.

- [ ] **Step 3: Update `Collection` model**

Replace the entire `qwip/Models/Collection.swift` with:

```swift
import Foundation

struct Collection: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let collectionDescription: String?
    let isShareable: Bool
    let spotCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, isShareable, spotCount, createdAt, updatedAt
        case collectionDescription = "description"
    }
}
```

- [ ] **Step 4: Ask user to run tests (Cmd+U) — expect pass**

Ask the user: "Please do a Cmd+U — all tests should pass including the two new description tests."

Wait for confirmation before continuing.

- [ ] **Step 5: Commit**

```bash
git add qwip/Models/Collection.swift qwipTests/qwipTests.swift
git commit -m "feat: add collectionDescription to Collection model"
```

---

### Task 2: Update `CollectionAPIClient` request bodies and function signatures

**Files:**
- Modify: `qwip/Services/CollectionAPIClient.swift`

- [ ] **Step 1: Update `CreateCollectionBody`**

Replace:
```swift
private struct CreateCollectionBody: Encodable { let name: String; let isShareable: Bool }
```
With:
```swift
private struct CreateCollectionBody: Encodable {
    let name: String
    let description: String?
    let isShareable: Bool
}
```

- [ ] **Step 2: Update `UpdateCollectionBody`**

Replace:
```swift
private struct UpdateCollectionBody: Encodable { let name: String; let isShareable: Bool }
```
With:
```swift
private struct UpdateCollectionBody: Encodable {
    let name: String
    let description: String?
    let isShareable: Bool
}
```

- [ ] **Step 3: Update `createCollection` function**

Replace:
```swift
func createCollection(name: String, isShareable: Bool) async throws -> Collection {
    let url = baseURL.appendingPathComponent("me/collections")
    var req = try authedRequest(url: url, method: "POST")
    req.httpBody = try encoder.encode(CreateCollectionBody(name: name, isShareable: isShareable))
```
With:
```swift
func createCollection(name: String, description: String?, isShareable: Bool) async throws -> Collection {
    let url = baseURL.appendingPathComponent("me/collections")
    var req = try authedRequest(url: url, method: "POST")
    req.httpBody = try encoder.encode(CreateCollectionBody(name: name, description: description, isShareable: isShareable))
```

- [ ] **Step 4: Update `updateCollection` function**

Replace:
```swift
func updateCollection(id: String, name: String, isShareable: Bool) async throws -> Collection {
    let url = baseURL.appendingPathComponent("me/collections/\(id)")
    var req = try authedRequest(url: url, method: "PATCH")
    req.httpBody = try encoder.encode(UpdateCollectionBody(name: name, isShareable: isShareable))
```
With:
```swift
func updateCollection(id: String, name: String, description: String?, isShareable: Bool) async throws -> Collection {
    let url = baseURL.appendingPathComponent("me/collections/\(id)")
    var req = try authedRequest(url: url, method: "PATCH")
    req.httpBody = try encoder.encode(UpdateCollectionBody(name: name, description: description, isShareable: isShareable))
```

- [ ] **Step 5: Ask user to build (Cmd+B)**

Ask the user: "Please do a Cmd+B — expected compile errors in `CollectionService` (callers not yet updated)."

Wait for confirmation before continuing.

- [ ] **Step 6: Commit**

```bash
git add qwip/Services/CollectionAPIClient.swift
git commit -m "feat: add description to CollectionAPIClient request bodies"
```

---

### Task 3: Update `CollectionService` — signatures and all stub constructions

**Files:**
- Modify: `qwip/Services/CollectionService.swift`

There are three places where `Collection` is constructed memberwise and must include `collectionDescription`.

- [ ] **Step 1: Update `create` method**

Replace the entire `create` method:

```swift
@discardableResult
func create(name: String, collectionDescription: String? = nil, isShareable: Bool = false) async throws -> Collection {
    let stubId = UUID().uuidString
    let stub = Collection(id: stubId, name: name, collectionDescription: collectionDescription,
                          isShareable: isShareable, spotCount: 0,
                          createdAt: .now, updatedAt: .now)
    collections.append(stub)
    do {
        let real = try await CollectionAPIClient.shared.createCollection(
            name: name, description: collectionDescription, isShareable: isShareable)
        if let index = collections.firstIndex(where: { $0.id == stubId }) {
            collections[index] = real
        }
        return real
    } catch {
        collections.removeAll { $0.id == stubId }
        throw error
    }
}
```

- [ ] **Step 2: Update `update` method**

Replace the entire `update` method:

```swift
func update(id: String, name: String, collectionDescription: String?, isShareable: Bool) async throws {
    guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
    let old = collections[index]
    collections[index] = Collection(id: old.id, name: name,
                                    collectionDescription: collectionDescription,
                                    isShareable: isShareable, spotCount: old.spotCount,
                                    createdAt: old.createdAt, updatedAt: .now)
    do {
        let updated = try await CollectionAPIClient.shared.updateCollection(
            id: id, name: name, description: collectionDescription, isShareable: isShareable)
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
```

- [ ] **Step 3: Update `incrementSpotCount` helper**

Replace the existing `incrementSpotCount` body:

```swift
private func incrementSpotCount(for collectionId: String, by delta: Int) {
    guard let index = collections.firstIndex(where: { $0.id == collectionId }) else { return }
    let old = collections[index]
    collections[index] = Collection(id: old.id, name: old.name,
                                    collectionDescription: old.collectionDescription,
                                    isShareable: old.isShareable,
                                    spotCount: max(0, old.spotCount + delta),
                                    createdAt: old.createdAt, updatedAt: old.updatedAt)
}
```

- [ ] **Step 4: Ask user to build (Cmd+B)**

Ask the user: "Please do a Cmd+B — expected compile errors in `CollectionsView` (callers not yet updated)."

Wait for confirmation before continuing.

- [ ] **Step 5: Commit**

```bash
git add qwip/Services/CollectionService.swift
git commit -m "feat: thread collectionDescription through CollectionService"
```

---

### Task 4: Update `CollectionFormSheet` and its callers in `CollectionsView`

**Files:**
- Modify: `qwip/Views/CollectionsView.swift`

`CollectionFormSheet` is defined at the bottom of `CollectionsView.swift`. Its callers are the create sheet and edit sheet in `CollectionsView.body`.

- [ ] **Step 1: Update `CollectionFormSheet` struct**

Replace the entire `CollectionFormSheet` struct with:

```swift
struct CollectionFormSheet: View {
    let title: String
    let onSave: (String, String?, Bool) -> Void

    @State private var name: String
    @State private var descriptionText: String
    @State private var isShareable: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String = "", initialDescription: String = "",
         initialShareable: Bool = false, onSave: @escaping (String, String?, Bool) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: initialName)
        _descriptionText = State(initialValue: initialDescription)
        _isShareable = State(initialValue: initialShareable)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collection name", text: $name)
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary)
                        .submitLabel(.next)
                }
                Section {
                    TextField("Description (optional)", text: $descriptionText)
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary)
                        .submitLabel(.done)
                }
                Section {
                    Toggle(isOn: $isShareable) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shareable")
                                .font(.dmSans(15))
                                .foregroundStyle(Color.brandPrimary)
                            Text("Anyone with the link can view this collection")
                                .font(.dmSans(12))
                                .foregroundStyle(Color.brandPrimary.opacity(0.5))
                        }
                    }
                    .tint(Color.brandPrimary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmedName.isEmpty else { return }
                        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespaces)
                        onSave(trimmedName, trimmedDesc.isEmpty ? nil : trimmedDesc, isShareable)
                        dismiss()
                    }
                    .font(.dmSans(15, weight: .bold))
                    .foregroundStyle(Color.brandPrimary)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.brandSecondary)
    }
}
```

- [ ] **Step 2: Update the create sheet caller**

Find the create sheet in `CollectionsView.body`:
```swift
.sheet(isPresented: $showCreateSheet) {
    CollectionFormSheet(title: "New Collection") { name, isShareable in
        Task {
            do { try await collectionService.create(name: name, isShareable: isShareable) }
            catch { actionError = error.localizedDescription }
        }
    }
}
```

Replace with:
```swift
.sheet(isPresented: $showCreateSheet) {
    CollectionFormSheet(title: "New Collection") { name, description, isShareable in
        Task {
            do { try await collectionService.create(name: name, collectionDescription: description, isShareable: isShareable) }
            catch { actionError = error.localizedDescription }
        }
    }
}
```

- [ ] **Step 3: Update the edit sheet caller**

Find the edit sheet in `CollectionsView.body`:
```swift
.sheet(item: $editTarget) { target in
    CollectionFormSheet(
        title: "Edit Collection",
        initialName: target.name,
        initialShareable: target.isShareable
    ) { name, isShareable in
        Task {
            do { try await collectionService.update(id: target.id, name: name, isShareable: isShareable) }
            catch { actionError = error.localizedDescription }
        }
    }
}
```

Replace with:
```swift
.sheet(item: $editTarget) { target in
    CollectionFormSheet(
        title: "Edit Collection",
        initialName: target.name,
        initialDescription: target.collectionDescription ?? "",
        initialShareable: target.isShareable
    ) { name, description, isShareable in
        Task {
            do { try await collectionService.update(id: target.id, name: name, collectionDescription: description, isShareable: isShareable) }
            catch { actionError = error.localizedDescription }
        }
    }
}
```

- [ ] **Step 4: Ask user to build (Cmd+B)**

Ask the user: "Please do a Cmd+B — should build cleanly."

Wait for confirmation before continuing.

- [ ] **Step 5: Commit**

```bash
git add qwip/Views/CollectionsView.swift
git commit -m "feat: add description field to CollectionFormSheet"
```

---

### Task 5: Show description subtitle in `CollectionDetailView`

**Files:**
- Modify: `qwip/Views/CollectionDetailView.swift`

The subtitle section goes inside the `List` branch of the `Group`, as the first `Section` before the `ForEach`.

- [ ] **Step 1: Add description subtitle section**

In the `List` branch (currently starting at line 76), the `List` content is:
```swift
List {
    ForEach(displayEntries) { entry in
        ...
    }
}
```

Add a description section before the `ForEach`:
```swift
List {
    if case .collection(let c) = source,
       let desc = c.collectionDescription, !desc.isEmpty {
        Section {
            Text(desc)
                .font(.dmSans(13))
                .foregroundStyle(Color.brandPrimary.opacity(0.55))
                .listRowBackground(Color.brandSecondary)
        }
    }
    ForEach(displayEntries) { entry in
        ...
    }
}
```

- [ ] **Step 2: Ask user to build (Cmd+B)**

Ask the user: "Please do a Cmd+B — should build cleanly."

Wait for confirmation before continuing.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/CollectionDetailView.swift
git commit -m "feat: show collection description as subtitle in CollectionDetailView"
```

---

### Task 6: Manual verification

- [ ] **Create a collection with a description** — tap + in Collections tab, fill in name + description, save. Verify it appears in the API response (check that the subtitle shows in CollectionDetailView).
- [ ] **Edit a collection** — swipe to edit, verify description field is pre-populated, change it, save.
- [ ] **Clear a description** — edit a collection, delete the description text, save. Verify nil is sent (description subtitle disappears).
- [ ] **Collection with no description** — verify no subtitle section appears, no empty space.
