# Collection Description Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the optional `description` field (max 500 chars) through the API client, service, create/edit form, and display it as a subtitle in `CollectionDetailView`.

**Architecture:** `collectionDescription: String?` already exists in the `Collection` model and `CollectionService` signatures. The remaining work flows through three layers: `CollectionAPIClient` request bodies → `CollectionFormSheet` UI → `CollectionDetailView` subtitle section.

**Tech Stack:** Swift 6, SwiftUI (iOS 17+), Swift Testing (`import Testing`, `@Test`, `#expect`), `@Observable`

**Spec:** `docs/superpowers/specs/2026-03-28-collection-description-design.md`

**Note:** User handles all builds (Cmd+B) and test runs (Cmd+U). Do not ask them to run builds or tests — just implement and commit.

---

## Already Done

- `qwip/Models/Collection.swift` — `collectionDescription: String?` with `CodingKeys` mapping to `"description"` ✓
- `qwipTests/qwipTests.swift` — `collectionDecodesFromJSON`, `collectionDecodesNullDescription`, `collectionDecodesDescription` tests ✓
- `CollectionService` — `create` and `update` already accept `collectionDescription: String?` ✓; `incrementSpotCount` already preserves it ✓

---

### Task 1: Add missing description decoding test

**Files:**
- Modify: `qwipTests/qwipTests.swift`

- [ ] **Step 1: Add test for absent description key**

In `qwipTests.swift`, add this test to the `qwipTests` struct after `collectionDecodesDescription`:

```swift
@Test func collectionMissingDescriptionDecodesNil() throws {
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
    let collection = try makeDecoder().decode(Collection.self, from: json)
    #expect(collection.collectionDescription == nil)
}
```

This verifies that older API responses without a `"description"` key decode without error.

- [ ] **Step 2: Commit**

```bash
git add qwipTests/qwipTests.swift
git commit -m "test: verify missing description key decodes to nil"
```

---

### Task 2: Update `CollectionAPIClient` request bodies and method signatures

**Files:**
- Modify: `qwip/Services/CollectionAPIClient.swift`

- [ ] **Step 1: Update request body structs**

Replace:
```swift
private struct CreateCollectionBody: Encodable { let name: String; let isShareable: Bool }
private struct UpdateCollectionBody: Encodable { let name: String; let isShareable: Bool }
```
With:
```swift
private struct CreateCollectionBody: Encodable {
    let name: String
    let description: String?
    let isShareable: Bool
}
private struct UpdateCollectionBody: Encodable {
    let name: String
    let description: String?
    let isShareable: Bool
}
```

The encoder uses `.convertToSnakeCase` but `description` stays `"description"` — no `CodingKeys` needed.

- [ ] **Step 2: Update `createCollection` signature and body**

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

- [ ] **Step 3: Update `updateCollection` signature and body**

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

- [ ] **Step 4: Commit**

```bash
git add qwip/Services/CollectionAPIClient.swift
git commit -m "feat: add description to CollectionAPIClient request bodies"
```

---

### Task 3: Thread `collectionDescription` through `CollectionService` to the API client

**Files:**
- Modify: `qwip/Services/CollectionService.swift`

The `create` and `update` methods already accept `collectionDescription: String?` but pass it to neither the API client nor the optimistic stub. Fix both.

- [ ] **Step 1: Update `create` API client call**

In `CollectionService.create`, replace:
```swift
let real = try await CollectionAPIClient.shared.createCollection(name: name, isShareable: isShareable)
```
With:
```swift
let real = try await CollectionAPIClient.shared.createCollection(
    name: name, description: collectionDescription, isShareable: isShareable)
```

- [ ] **Step 2: Update `update` API client call**

In `CollectionService.update`, replace:
```swift
let updated = try await CollectionAPIClient.shared.updateCollection(id: id, name: name, isShareable: isShareable)
```
With:
```swift
let updated = try await CollectionAPIClient.shared.updateCollection(
    id: id, name: name, description: collectionDescription, isShareable: isShareable)
```

- [ ] **Step 3: Commit**

```bash
git add qwip/Services/CollectionService.swift
git commit -m "feat: thread collectionDescription through CollectionService to API client"
```

---

### Task 4: Update `CollectionFormSheet` and its callers in `CollectionsView`

**Files:**
- Modify: `qwip/Views/CollectionsView.swift`

`CollectionFormSheet` lives at the bottom of this file. Two callers are in `CollectionsView.body`: the create sheet and the edit sheet.

- [ ] **Step 1: Replace `CollectionFormSheet`**

Replace the entire `CollectionFormSheet` struct (starting at `struct CollectionFormSheet: View`) with:

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
                    TextField("Description (optional)", text: $descriptionText, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.dmSans(15))
                        .foregroundStyle(Color.brandPrimary)
                        .onChange(of: descriptionText) { _, new in
                            if new.count > 500 { descriptionText = String(new.prefix(500)) }
                        }
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
                        let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
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

Replace:
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
With:
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

Replace:
```swift
.sheet(item: $editTarget) { target in
    CollectionFormSheet(
        title: "Edit Collection",
        initialName: target.name,
        initialShareable: target.isShareable
    ) { name, isShareable in
        Task {
            do { try await collectionService.update(id: target.id, name: name, collectionDescription: nil, isShareable: isShareable) }
            catch { actionError = error.localizedDescription }
        }
    }
}
```
With:
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

- [ ] **Step 4: Commit**

```bash
git add qwip/Views/CollectionsView.swift
git commit -m "feat: add description field to CollectionFormSheet"
```

---

### Task 5: Show description subtitle in `CollectionDetailView`

**Files:**
- Modify: `qwip/Views/CollectionDetailView.swift`

The description section goes at the top of the `List`, before the spots `ForEach`. The `List` is in the `else` branch at the end of the `Group` in `body`.

- [ ] **Step 1: Add description section to the List**

In `CollectionDetailView.body`, find the `List` block:
```swift
List {
    ForEach(displayEntries) { entry in
```

Add the description section before `ForEach`:
```swift
List {
    if case .collection(let c) = source,
       let desc = c.collectionDescription, !desc.isEmpty {
        Section {
            Text(desc)
                .font(.dmSans(14))
                .foregroundStyle(Color.brandPrimary.opacity(0.55))
                .padding(.vertical, 4)
                .listRowBackground(Color.brandSecondary)
                .listRowSeparator(.hidden)
        }
    }
    ForEach(displayEntries) { entry in
```

- [ ] **Step 2: Commit**

```bash
git add qwip/Views/CollectionDetailView.swift
git commit -m "feat: show collection description subtitle in CollectionDetailView"
```
