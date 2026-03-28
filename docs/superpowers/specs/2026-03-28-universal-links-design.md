# Universal Links — iOS Implementation Spec

**Date:** 2026-03-28
**Scope:** Handle `https://qwip.co.uk/collections/{id}` Universal Links, navigating to the correct `CollectionDetailView` including when the app cold-starts unauthenticated.

## Context

The AASA file is already hosted at `https://qwip.co.uk/.well-known/apple-app-site-association` mapping `/collections/*` to app ID `XV9269Z98G.com.qwipuk.qwip`. The Associated Domains entitlement (`applinks:qwip.co.uk`) is already configured in Xcode. This spec covers the Swift implementation only.

## Architecture

### AppRouter

New `@Observable` class holding app-level navigation state:

```swift
// qwip/Services/AppRouter.swift
@Observable
final class AppRouter {
    var pendingCollectionId: String? = nil
}
```

Instantiated once in `qwipApp` as `@State private var appRouter = AppRouter()` and injected via `.environment(appRouter)` on `RootView`. Lives above `RootView` so the pending ID persists through the entire auth flow (splash → sign-in → main).

### URL Routing (`qwipApp`)

The existing `onOpenURL` is extended to distinguish Google OAuth callbacks from Universal Links:

- Google OAuth URLs use the `com.googleusercontent.apps.*` custom scheme → forwarded to `GIDSignIn.sharedInstance.handle(url)` as before
- Universal Links arrive as `https://qwip.co.uk/collections/{id}` → set `appRouter.pendingCollectionId = id`

The two cases are mutually exclusive by scheme.

### Tab Switching (`ContentView`)

`ContentView` reads `appRouter` from the environment. When `pendingCollectionId` becomes non-nil, it switches `selectedTab` to `1` (the Saved/Collections tab) using the two-parameter iOS 17 `onChange` form:

```swift
.onChange(of: appRouter.pendingCollectionId) { _, id in
    if id != nil { selectedTab = 1 }
}
```

### Deep Link Navigation (`CollectionsView`)

`CollectionsView` gains:

1. `@State private var navPath = NavigationPath()` — drives the `NavigationStack`
2. `NavigationStack(path: $navPath)` replacing the current `NavigationStack`
3. A `CollectionDestination` enum (defined in `CollectionsView.swift`) to unify both navigation targets under a single `Hashable` type:

```swift
private enum CollectionDestination: Hashable {
    case favourites
    case collection(Collection)
}
```

4. Both `NavigationLink`s converted to value-based form — `NavigationLink(value: CollectionDestination.favourites)` and `NavigationLink(value: CollectionDestination.collection(collection))` — with a single `navigationDestination(for: CollectionDestination.self)` that switches on the value and renders the appropriate `CollectionDetailView(source:)`.

5. `Collection` must gain `Hashable` conformance (synthesized — all fields are already `Hashable`).

6. A `handlePendingDeepLink()` helper called from three triggers (all using the two-parameter iOS 17 `onChange` form):
   - `.onChange(of: appRouter.pendingCollectionId) { _, _ in handlePendingDeepLink() }` — fires when a link arrives while collections are already loaded
   - `.onChange(of: collectionService.collections) { _, _ in handlePendingDeepLink() }` — fires when collections finish loading after a cold-start link
   - `.onAppear { handlePendingDeepLink() }` — handles the case where both the pending ID and collections are already set when the view first mounts

`handlePendingDeepLink()` looks up the collection by ID in `collectionService.collections`. If found, appends `CollectionDestination.collection(collection)` to `navPath` and clears `appRouter.pendingCollectionId`. If not found (collections still loading), it no-ops and waits for the next trigger.

## Files Changed

| File | Change |
|------|--------|
| `qwip/Services/AppRouter.swift` | New file |
| `qwip/Models/Collection.swift` | Add `Hashable` conformance |
| `qwip/qwipApp.swift` | Add `@State appRouter`, extend `onOpenURL`, inject into environment |
| `qwip/ContentView.swift` | Add `@Environment(AppRouter.self)`, add `.onChange` for tab switching |
| `qwip/Views/CollectionsView.swift` | Add `CollectionDestination` enum, `navPath`, programmatic `NavigationStack`, deep link handler |

## Edge Cases

- **Collection not found:** If the ID doesn't match any loaded collection (deleted, wrong ID), `handlePendingDeepLink()` no-ops and the pending ID is left set until collections reload. If it still doesn't match after load, the pending ID is never cleared and the user lands on the Saved tab list. Consider clearing the pending ID after a load completes with no match.
- **Already on Saved tab:** Tab switch to index 1 is idempotent.
- **Back navigation:** User can navigate back normally; `navPath` manages the stack.
- **Multiple links:** If a second link fires while already on a collection, `navPath` appends again (standard stack behaviour).
- **Cold-start unauthenticated:** `pendingCollectionId` is set during `onOpenURL`, survives splash → sign-in → `ContentView` mount. `onAppear` trigger in `CollectionsView` fires once the view renders and handles navigation if collections are already loaded; `onChange(of: collectionService.collections)` handles if they're still loading.
