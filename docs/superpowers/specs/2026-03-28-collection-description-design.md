# Collection Description Field — iOS Implementation Spec

**Date:** 2026-03-28
**Scope:** Add optional `description` field to collections — model, API client, service, create/edit form, and display as subtitle in `CollectionDetailView`.

## Context

The backend has added a nullable `description: String?` to all collection response types and to the create/edit request bodies (max 500 chars). This spec covers the iOS-side changes only.

## Naming Note

`description` is a reserved property name in Swift (`CustomStringConvertible`). The model uses `collectionDescription: String?` with a `CodingKeys` enum mapping it to the JSON key `"description"`. All local state vars in views use `descriptionText` for the same reason.

## Files Changed

| File | Change |
|------|--------|
| `qwip/Models/Collection.swift` | Add `var collectionDescription: String?` with `CodingKeys` mapping to `"description"` |
| `qwip/Services/CollectionAPIClient.swift` | Add `description` to request bodies and function signatures |
| `qwip/Services/CollectionService.swift` | Add `collectionDescription` to `create`/`update` signatures; preserve it in all stub construction and `incrementSpotCount` |
| `qwip/Views/CollectionsView.swift` | Add description `TextField` to `CollectionFormSheet`; update `onSave` callback and callers; expand sheet detent |
| `qwip/Views/CollectionDetailView.swift` | Show description as subtitle at top of list |

## Architecture

### Model

```swift
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

Note: the decoder uses `.convertFromSnakeCase`, but `CodingKeys` takes priority when present — the explicit mapping to `"description"` ensures correct JSON round-tripping.

### API Client

Request bodies send `description` (the JSON key) using the encoder's `.convertToSnakeCase` strategy, so the struct fields are named `description: String?`:

```swift
private struct CreateCollectionBody: Encodable {
    let name: String
    let description: String?
    let isShareable: Bool
}

private struct UpdateCollectionBody: Encodable {
    let name: String
    let description: String?   // send nil to clear
    let isShareable: Bool
}
```

Function signatures updated:

```swift
func createCollection(name: String, description: String?, isShareable: Bool) async throws -> Collection
func updateCollection(id: String, name: String, description: String?, isShareable: Bool) async throws -> Collection
```

### CollectionService

`create` and `update` gain `collectionDescription: String?` parameter.

**`create` stub construction:**
```swift
let stub = Collection(id: stubId, name: name, collectionDescription: collectionDescription,
                      isShareable: isShareable, spotCount: 0, createdAt: .now, updatedAt: .now)
```

**`update` optimistic stub construction:**
```swift
collections[index] = Collection(id: old.id, name: name, collectionDescription: collectionDescription,
                                isShareable: isShareable, spotCount: old.spotCount,
                                createdAt: old.createdAt, updatedAt: .now)
```

**`incrementSpotCount` helper** — preserve existing description:
```swift
collections[index] = Collection(
    id: old.id, name: old.name, collectionDescription: old.collectionDescription,
    isShareable: old.isShareable, spotCount: max(0, old.spotCount + delta),
    createdAt: old.createdAt, updatedAt: old.updatedAt
)
```

### CollectionFormSheet

`onSave` callback changes from `(String, Bool) -> Void` to `(String, String?, Bool) -> Void` (name, description, isShareable).

New state: `@State private var descriptionText: String`, initialised from `initialDescription: String = ""` parameter.

New `Section` added between name and shareable sections:

```swift
Section {
    TextField("Description (optional)", text: $descriptionText)
        .font(.dmSans(15))
        .foregroundStyle(Color.brandPrimary)
        .submitLabel(.next)
}
```

On save, empty string maps to `nil`:
```swift
let desc = descriptionText.trimmingCharacters(in: .whitespaces)
onSave(trimmedName, desc.isEmpty ? nil : desc, isShareable)
```

Sheet detent updated to `.medium, .large` (was `.medium` only — third section would clip on smaller devices).

Both callers in `CollectionsView` updated:
- Create sheet: `onSave` closure passes `description` to `collectionService.create(name:collectionDescription:isShareable:)`
- Edit sheet: `initialDescription: target.collectionDescription ?? ""` passed to `CollectionFormSheet`; `onSave` closure passes `description` to `collectionService.update(id:name:collectionDescription:isShareable:)`

### CollectionDetailView — Subtitle

First `Section` in the `List`, before the spots `ForEach`, only for `.collection` with non-empty description:

```swift
if case .collection(let c) = source,
   let desc = c.collectionDescription, !desc.isEmpty {
    Section {
        Text(desc)
            .font(.dmSans(13))
            .foregroundStyle(Color.brandPrimary.opacity(0.55))
            .listRowBackground(Color.brandSecondary)
    }
}
```

Not shown on `.favourites`, loading, error, or empty states.

## Testing

- Update `collectionDecodesFromJSON`: add `"description": null` to JSON, assert `collection.collectionDescription == nil`
- Add `collectionDecodesDescription`: JSON with `"description": "Morning cafes"`, assert `collection.collectionDescription == "Morning cafes"`
- Add `collectionDescriptionEmptyStringBecomesNil`: verify trimmed empty string produces `nil` in `onSave` (pure logic test, no view needed)

## Edge Cases

- **Null/absent description from server:** decodes as `nil`, subtitle section not shown
- **Empty string input:** trimmed to `nil` before sending — never sends `""` to the API
- **Long description:** wraps naturally in detail view; no client-side character limit (backend enforces 500)
