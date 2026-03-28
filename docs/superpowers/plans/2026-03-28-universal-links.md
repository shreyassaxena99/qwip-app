# Universal Links Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Handle `https://qwip.co.uk/collections/{id}` Universal Links by navigating to the matching `CollectionDetailView`, surviving the full auth flow including cold-start when unauthenticated.

**Architecture:** An `AppRouter` @Observable service holds a `pendingCollectionId` at the app root. `onOpenURL` in `qwipApp` sets it for Universal Links and forwards Google OAuth URLs as before. `ContentView` switches to the Saved tab when a pending ID appears; `CollectionsView` drives a `NavigationPath` and resolves the pending ID to a collection once loaded.

**Tech Stack:** Swift 6, SwiftUI (iOS 17+), Swift Testing framework (`import Testing`), `@Observable` (Observation framework)

**Spec:** `docs/superpowers/specs/2026-03-28-universal-links-design.md`

---

### Task 1: Add `Hashable` to `Collection` and verify with a test

**Files:**
- Modify: `qwip/Models/Collection.swift`
- Test: `qwipTests/qwipTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `qwipTests` struct in `qwipTests/qwipTests.swift`:

```swift
@Test func collectionIsHashable() {
    let a = Collection(
        id: "abc", name: "Test", isShareable: false, spotCount: 1,
        createdAt: Date(), updatedAt: Date()
    )
    let b = Collection(
        id: "abc", name: "Test", isShareable: false, spotCount: 1,
        createdAt: a.createdAt, updatedAt: a.updatedAt
    )
    var set = Set<Collection>()
    set.insert(a)
    set.insert(b)
    #expect(set.count == 1)
}
```

- [ ] **Step 2: Run the test to verify it fails**

In Xcode: Cmd+U. Expected: compile error — `Collection` does not conform to `Hashable`.

- [ ] **Step 3: Add `Hashable` conformance**

`qwip/Models/Collection.swift` — change the conformance list:

```swift
struct Collection: Identifiable, Codable, Hashable {
```

No custom `hash(into:)` needed — all fields (`String`, `Bool`, `Int`, `Date`) are already `Hashable`, so synthesis works.

- [ ] **Step 4: Run the test to verify it passes**

Cmd+U. Expected: all tests pass including `collectionIsHashable`.

- [ ] **Step 5: Commit**

```bash
git add qwip/Models/Collection.swift qwipTests/qwipTests.swift
git commit -m "feat: add Hashable conformance to Collection"
```

---

### Task 2: Create `AppRouter` with URL parsing

**Files:**
- Create: `qwip/Services/AppRouter.swift`
- Test: `qwipTests/qwipTests.swift`

- [ ] **Step 1: Write failing tests**

Add a new test struct at the bottom of `qwipTests/qwipTests.swift`:

```swift
struct AppRouterTests {

    @Test func parsesValidCollectionURL() {
        let url = URL(string: "https://qwip.co.uk/collections/abc-123")!
        #expect(AppRouter.collectionId(from: url) == "abc-123")
    }

    @Test func ignoresNonCollectionURL() {
        let url = URL(string: "https://qwip.co.uk/spots/xyz")!
        #expect(AppRouter.collectionId(from: url) == nil)
    }

    @Test func ignoresGoogleOAuthURL() {
        let url = URL(string: "com.googleusercontent.apps.12345:/oauth2callback")!
        #expect(AppRouter.collectionId(from: url) == nil)
    }

    @Test func parsesCollectionIdWithTrailingPath() {
        // Defensive: only the first path component after /collections/ is the ID
        let url = URL(string: "https://qwip.co.uk/collections/abc-123/extra")!
        #expect(AppRouter.collectionId(from: url) == "abc-123")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Cmd+U. Expected: compile error — `AppRouter` does not exist.

- [ ] **Step 3: Implement `AppRouter`**

Create `qwip/Services/AppRouter.swift`:

```swift
import Observation

@Observable
final class AppRouter {
    var pendingCollectionId: String? = nil

    /// Extracts a collection ID from a Universal Link URL.
    /// Returns nil for Google OAuth callbacks or any unrecognised URL.
    static func collectionId(from url: URL) -> String? {
        guard url.scheme == "https",
              url.host == "qwip.co.uk" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2,
              components[0] == "collections",
              !components[1].isEmpty else { return nil }
        return components[1]
    }
}
```

- [ ] **Step 4: Run to verify tests pass**

Cmd+U. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add qwip/Services/AppRouter.swift qwipTests/qwipTests.swift
git commit -m "feat: add AppRouter with Universal Link URL parsing"
```

---

### Task 3: Wire `AppRouter` into `qwipApp`

**Files:**
- Modify: `qwip/qwipApp.swift`

`qwipApp.swift` currently has:
```swift
@State private var authService = AuthService()
// ...
.environment(authService)
.onOpenURL { url in
    GIDSignIn.sharedInstance.handle(url)
}
```

- [ ] **Step 1: Add `appRouter` state and environment injection**

Add `@State private var appRouter = AppRouter()` directly after the `authService` line:

```swift
@State private var authService = AuthService()
@State private var appRouter = AppRouter()
```

Add `.environment(appRouter)` directly after `.environment(authService)` on `RootView`:

```swift
RootView()
    .environment(authService)
    .environment(appRouter)
    .task { ... }
    .onOpenURL { ... }
```

- [ ] **Step 2: Extend `onOpenURL` to handle Universal Links**

Replace the existing `onOpenURL` closure:

```swift
.onOpenURL { url in
    if url.scheme?.hasPrefix("com.googleusercontent.apps") == true {
        GIDSignIn.sharedInstance.handle(url)
    } else if let id = AppRouter.collectionId(from: url) {
        appRouter.pendingCollectionId = id
    }
}
```

- [ ] **Step 3: Build to verify no compile errors**

Cmd+B. Expected: builds cleanly.

- [ ] **Step 4: Commit**

```bash
git add qwip/qwipApp.swift
git commit -m "feat: inject AppRouter and route Universal Links in qwipApp"
```

---

### Task 4: Switch to Saved tab in `ContentView`

**Files:**
- Modify: `qwip/ContentView.swift`

`ContentView` currently has `@State private var selectedTab = 0` and a `.task` but no reference to `AppRouter`.

- [ ] **Step 1: Add `@Environment(AppRouter.self)` to `ContentView`**

Add after the existing `@State` declarations:

```swift
@Environment(AppRouter.self) var appRouter
```

- [ ] **Step 2: Add `.onChange` to switch tabs**

Add after the existing `.task` modifier in `body`:

```swift
.onChange(of: appRouter.pendingCollectionId) { _, id in
    if id != nil {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            selectedTab = 1
        }
    }
}
```

- [ ] **Step 3: Build to verify no compile errors**

Cmd+B. Expected: builds cleanly.

- [ ] **Step 4: Commit**

```bash
git add qwip/ContentView.swift
git commit -m "feat: switch to Saved tab on incoming Universal Link"
```

---

### Task 5: Programmatic navigation in `CollectionsView`

**Files:**
- Modify: `qwip/Views/CollectionsView.swift`

This is the largest change. Current state:
- `NavigationStack` with no path binding
- Two inline `NavigationLink { CollectionDetailView(source:) }` closures
- No `AppRouter` reference

- [ ] **Step 1: Add `CollectionDestination` enum and `navPath` state**

At the top of the `CollectionsView` struct body, after existing `@State` declarations:

```swift
@Environment(AppRouter.self) var appRouter
@State private var navPath = NavigationPath()

private enum CollectionDestination: Hashable {
    case favourites
    case collection(Collection)
}
```

- [ ] **Step 2: Bind `NavigationStack` to `navPath`**

Change:
```swift
NavigationStack {
```
To:
```swift
NavigationStack(path: $navPath) {
```

- [ ] **Step 3: Convert `NavigationLink`s to value-based**

Replace the Favourites `NavigationLink`:
```swift
// Before:
NavigationLink {
    CollectionDetailView(source: .favourites)
} label: {
    CollectionRow(name: "Favourite Spots", icon: "star.fill", count: favouriteCount)
}

// After:
NavigationLink(value: CollectionDestination.favourites) {
    CollectionRow(name: "Favourite Spots", icon: "star.fill", count: favouriteCount)
}
```

Replace the collection `NavigationLink` inside `ForEach` — keep the `.swipeActions` attached:
```swift
// Before:
NavigationLink {
    CollectionDetailView(source: .collection(collection))
} label: {
    CollectionRow(...)
}
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) { deleteTarget = collection } label: {
        Label("Delete", systemImage: "trash")
    }
    Button { editTarget = collection } label: {
        Label("Edit", systemImage: "pencil")
    }
    .tint(.gray)
}

// After (swipeActions must stay on the NavigationLink):
NavigationLink(value: CollectionDestination.collection(collection)) {
    CollectionRow(...)
}
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) { deleteTarget = collection } label: {
        Label("Delete", systemImage: "trash")
    }
    Button { editTarget = collection } label: {
        Label("Edit", systemImage: "pencil")
    }
    .tint(.gray)
}
```

- [ ] **Step 4: Add `navigationDestination`**

Chain on the `Group` alongside `.refreshable` and `.navigationTitle` (i.e. inside the `NavigationStack` content closure, as a modifier on the `Group`):

```swift
.navigationDestination(for: CollectionDestination.self) { destination in
    switch destination {
    case .favourites:
        CollectionDetailView(source: .favourites)
    case .collection(let collection):
        CollectionDetailView(source: .collection(collection))
    }
}
```

- [ ] **Step 5: Add deep link handler and triggers**

Add a private method at the bottom of the `CollectionsView` struct (before the closing `}`):

```swift
private func handlePendingDeepLink() {
    guard let id = appRouter.pendingCollectionId,
          let collection = collectionService.collections.first(where: { $0.id == id })
    else { return }
    navPath.append(CollectionDestination.collection(collection))
    appRouter.pendingCollectionId = nil
}
```

Add three modifiers after `.navigationDestination`:

```swift
.onAppear { handlePendingDeepLink() }
.onChange(of: appRouter.pendingCollectionId) { _, _ in handlePendingDeepLink() }
.onChange(of: collectionService.collections) { _, _ in handlePendingDeepLink() }
```

- [ ] **Step 6: Build to verify no compile errors**

Cmd+B. Expected: builds cleanly.

- [ ] **Step 7: Commit**

```bash
git add qwip/Views/CollectionsView.swift
git commit -m "feat: programmatic navigation in CollectionsView for Universal Links"
```

---

### Task 6: Manual verification

- [ ] **Scenario A — App already open, signed in:**
  1. Run app in Simulator, sign in, reach main screen
  2. In Safari, open `https://qwip.co.uk/collections/{real-collection-id}`
  3. Expected: app comes to foreground, switches to Saved tab, pushes the matching collection

- [ ] **Scenario B — Cold start, signed in (session restored):**
  1. Quit app from Simulator
  2. Open `https://qwip.co.uk/collections/{id}` in Safari
  3. Expected: splash → main → Saved tab → collection detail

- [ ] **Scenario C — Cold start, not signed in:**
  1. Sign out of app, quit from Simulator
  2. Open `https://qwip.co.uk/collections/{id}` in Safari
  3. Expected: splash → sign-in → main → Saved tab → collection detail

- [ ] **Scenario D — Invalid / deleted collection ID:**
  1. Open `https://qwip.co.uk/collections/does-not-exist`
  2. Expected: app switches to Saved tab, lands on collection list (no crash, no navigation)
