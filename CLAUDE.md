# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open `qwip.xcodeproj` in Xcode. Build and run with Cmd+R (target: qwip, iOS Simulator or device).

**Config setup** (required, not committed):
- Copy `Config.example.swift` → `qwip/Services/Config.swift`
- Fill in `supabaseURL`, `supabaseAnonKey`, `googleIOSClientID`, `googleWebClientID`

**Tests:**
- Run all: Cmd+U in Xcode
- Run single test: click diamond next to test method in Xcode gutter

**Dependencies** (Swift Package Manager, no manual install needed):
- `supabase-swift` — auth, session, Keychain
- `GoogleSignIn-iOS` — Google OAuth

## Architecture

### State Management
All services use `@Observable` (iOS 17+ Observation framework — not `ObservableObject`). Injected via `@Environment` at the app root in `qwipApp.swift`. Views use `@Bindable` only when they need two-way bindings (e.g. `ProfileView`).

Key services:
- **`AuthService`** (`@MainActor`) — auth state machine, session, profile, OAuth flows
- **`SpotStore`** — spots list + category/filter state
- **`SavedSpotService`** — saved entries with optimistic updates
- **`CollectionService`** — user collections with optimistic updates
- **`LocationService`** — CLLocationManager wrapper

### Data Flow
```
Views → @Environment services → API Clients → FastAPI backend (Railway)
                                            ↘ Supabase (Auth + DB)
```
No network calls in views. Services own all async state.

### Optimistic Updates Pattern
`SavedSpotService` and `CollectionService` both use the same pattern: insert/remove immediately in local state, then sync with server. On failure: capture original state before change, revert to it. See `SavedSpotService.swift` for the canonical implementation.

### Auth Flow
`RootView` drives auth via `AppPhase` enum: `.splash → .signIn → .nameCollection → .main`

- **Google**: `GoogleSignIn` SDK → ID token + access token → Supabase `signInWithIdToken`
- **Email OTP**: `signInWithOTP(email:)` → user enters 6-digit code → `verifyOTP(email:token:)`
- Session restored on launch via explicit `restoreSession()` + `authStateChanges` stream

New email users without a display name land on `NameCollectionView` before `.main`.

### API Clients
- Base URL in `Config.swift` (`spotsvc.up.railway.app`)
- Auth: `Authorization: Bearer <supabase_access_token>` on all `/me/*` endpoints
- All API responses use snake_case → decoded with `.convertFromSnakeCase` strategy
- Each client defines its own typed error enum conforming to `LocalizedError`

### Navigation
- `ContentView` hosts a custom floating glass tab bar (Map / Saved / Profile)
- `MapView` presents `SpotDetailView` as a `.sheet(item:)`
- `SpotDetailView` presents `SaveToCollectionSheet` as a nested sheet
- `CollectionsView` uses `NavigationStack` with `NavigationLink` to `CollectionDetailView`

### Map
- Full-screen MapKit with client-side clustering (radius scales with zoom span)
- Custom `SpotAnnotationView` pins (green circle + SF symbol per category)
- Filter bar and bottom card drawer are overlay views, not sheets (avoids double-sheet conflicts)

## Key Conventions

- **No SwiftData** — all persistence via Supabase backend
- **No Combine** — use async/await + @Observable throughout
- **PBXFileSystemSynchronizedRootGroup** — Xcode auto-detects new files in the `qwip/` folder; no need to edit `.pbxproj` when adding Swift files
- **Brand colors**: `Color.brandPrimary` (#1f3d32 green), `Color.brandSecondary` (#FDFBF7 cream) — defined in `Extensions/Color+Brand.swift`
- **Custom fonts**: Funnel Display, Cormorant Garamond, DM Sans — registered at app init in `qwipApp.swift`, accessed via `Font+Brand.swift`
- **Glass UI**: `.ultraThinMaterial` + linear gradients + `brandPrimary` shadow at 15% opacity — used consistently throughout

## Reference Docs

- `claude/CONTEXT.md` — backend architecture, DB schema, RLS policies, API cost breakdown
- `claude/UI_SPEC.md` — design system spec (screens, colors, fonts)
- `markdown/auth-architecture.md` — auth flow diagrams
- `docs/superpowers/plans/` — feature implementation plans
