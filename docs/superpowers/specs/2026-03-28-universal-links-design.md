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

`ContentView` observes `appRouter.pendingCollectionId`. When it becomes non-nil, it switches `selectedTab` to `1` (the Saved/Collections tab). No animation — the tab switch is part of the collection navigation.

### Deep Link Navigation (`CollectionsView`)

`CollectionsView` gains:

1. `@State private var navPath = NavigationPath()` — drives the `NavigationStack`
2. `NavigationStack(path: $navPath)` replacing the current `NavigationStack`
3. `navigationDestination(for: Collection.self)` replacing inline `NavigationLink` closures
4. A `handlePendingDeepLink()` helper called from two `.onChange` handlers:
   - `.onChange(of: appRouter.pendingCollectionId)` — fires when a link arrives while collections are already loaded
   - `.onChange(of: collectionService.collections)` — fires when collections finish loading after a cold-start link

`handlePendingDeepLink()` looks up the collection by ID in `collectionService.collections`. If found, appends it to `navPath` and clears `appRouter.pendingCollectionId`. If not found (e.g. collections still loading), it no-ops and waits for the next trigger.

## Files Changed

| File | Change |
|------|--------|
| `qwip/Services/AppRouter.swift` | New file |
| `qwip/qwipApp.swift` | Add `@State appRouter`, extend `onOpenURL`, inject into environment |
| `qwip/ContentView.swift` | Add `@Environment(AppRouter.self)`, add `.onChange` for tab switching |
| `qwip/Views/CollectionsView.swift` | Add `navPath`, convert to programmatic `NavigationStack`, add deep link handler |

## Edge Cases

- **Collection not found:** If the ID doesn't match any loaded collection (deleted, wrong ID), the pending ID is cleared silently and the user lands on the Saved tab list.
- **Already on Saved tab:** Tab switch to index 1 is idempotent.
- **Back navigation:** User can navigate back normally; `navPath` manages the stack.
- **Multiple links:** If a second link fires while already on a collection, `navPath` appends again (standard stack behaviour).
