# qwip

Find work-friendly spots in London — cafes, coworking spaces, libraries, hotels, and more.

## Stack

- **iOS** — SwiftUI, iOS 17+, Swift Package Manager
- **Auth** — Supabase Auth (email OTP + Google OAuth)
- **Backend** — FastAPI on Railway
- **Database** — Supabase (Postgres + RLS)

## Getting Started

### Prerequisites

- Xcode 15+
- A Supabase project
- A Google OAuth client (iOS + Web)

### Config

Copy the example config and fill in your credentials:

```bash
cp qwip/Services/Config.example.swift qwip/Services/Config.swift
```

Edit `Config.swift` and set:

```swift
static let supabaseURL = "https://your-project.supabase.co"
static let supabaseAnonKey = "your-anon-key"
static let googleIOSClientID = "your-ios-client-id"
static let googleWebClientID = "your-web-client-id"
```

### Build & Run

Open `qwip.xcodeproj` in Xcode and press `Cmd+R`. Dependencies are fetched automatically via Swift Package Manager.

### Tests

Press `Cmd+U` in Xcode to run all tests, or click the diamond next to any test method in the gutter to run individually.

## Architecture

### State Management

Services use `@Observable` (iOS 17 Observation framework). Injected via `@Environment` at the app root. No Combine, no ObservableObject.

Key services:

| Service | Responsibility |
|---|---|
| `AuthService` | Auth state, session, profile, OAuth flows |
| `SpotStore` | Spots list, category/filter state |
| `SavedSpotService` | Saved spots with optimistic updates |
| `CollectionService` | User collections with optimistic updates |
| `LocationService` | CLLocationManager wrapper |

### Data Flow

```
Views → @Environment services → API Clients → FastAPI (Railway)
                                            ↘ Supabase (Auth + DB)
```

No network calls in views — services own all async state.

### Auth Flow

```
splash → signIn → (email OTP stepper) → main
                ↘ (Google OAuth)      ↗
```

Session is restored on launch via `restoreSession()` + `authStateChanges` stream.

### Optimistic Updates

`SavedSpotService` and `CollectionService` update local state immediately, then sync to the server. On failure, the original state is restored. See `SavedSpotService.swift` for the reference implementation.

## Design System

- **Primary** — `#1f3d32` (forest green)
- **Secondary** — `#FDFBF7` (cream)
- **Fonts** — Funnel Display, Cormorant Garamond, DM Sans
- **Glass UI** — `.ultraThinMaterial` + linear gradients throughout

## Dependencies

- [`supabase-swift`](https://github.com/supabase/supabase-swift) — auth, session, Keychain storage
- [`GoogleSignIn-iOS`](https://github.com/google/GoogleSignIn-iOS) — Google OAuth
