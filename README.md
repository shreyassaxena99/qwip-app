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
- [`stripe-ios-spm`](https://github.com/stripe/stripe-ios-spm) — native card checkout for pod reservations

## Pod reservations

The Pods tab and the map load bookable pods from qwipsvc. Signed-in users use `GET /api/app-reservations/pods`, which includes the 50p/hour Test Pod; signed-out users see the public catalogue without it. Westfield remains £15/hour in both the app and website. The map resolves each pod's address with MapKit and shows an orange pod marker; tapping it opens the reservation screen. Booking uses the existing availability, hold creation, and status endpoints. Stripe PaymentSheet confirms the server-created PaymentIntent; only the qwipsvc webhook marks a reservation paid and sends the access code by email. The authenticated booking owner can also fetch the code on booking details until the scheduled end; the app never receives a Stripe secret key. A check-in photo can be taken from 15 minutes before start until the scheduled end and is stored privately by qwipsvc.

Deploy the new public pod-list endpoint in qwipsvc before shipping the app update. The app uses the same live Stripe account as the website. For a test checkout, use matching Stripe test keys and a test-mode qwipsvc environment.
