# Auth — iOS Code Structure

## New Swift Packages (add via SPM)

- `supabase-swift` — official Supabase iOS SDK (Keychain persistence, token refresh, all auth calls)
- `GoogleSignIn-iOS` — Google's native SDK for getting the ID token before handing to Supabase

## New Files

### `Services/SupabaseClient.swift`
A single shared `supabase` client instance containing your project URL and anon key. Imported wherever Supabase is needed.

### `Services/AuthService.swift`
The `@Observable` singleton. Owns all auth state and wraps every Supabase auth call. No view ever calls Supabase directly.

### `Views/OTPVerificationView.swift`
Shown after the user submits their email. Contains:
- 6-digit code input field
- "Verify" button that calls `AuthService.verifyOTP(email:token:)`
- Resend code option
- Back button to return to sign-in

## Modified Files

### `qwipApp.swift`
- Create `AuthService` instance
- Inject into environment via `.environment(authService)`
- Call `authService.restoreSession()` on launch

### `Views/RootView.swift`
- Remove `@State private var phase: AppPhase`
- Observe `@Environment(AuthService.self)` instead
- Derive phase from `authService.isAuthenticated` — splash still shows briefly on first launch
- On successful auth, `isAuthenticated` flips to `true` and `RootView` automatically transitions to `.main`

### `Views/SignInView.swift`
- Wire "Continue with Apple" button → `authService.signInWithApple()`
- Wire "Continue with Google" button → `authService.signInWithGoogle()`
- Wire email "Continue" button → `authService.sendOTP(email:)` → navigate to `OTPVerificationView`
- Add navigation state to push `OTPVerificationView` after OTP is sent

## Supabase credentials needed in the app

These go in a config file (xcconfig or Info.plist, never committed to git):

- `SUPABASE_URL` — your project URL (e.g. `https://xxxx.supabase.co`)
- `SUPABASE_ANON_KEY` — your project's public anon key
- `GOOGLE_IOS_CLIENT_ID` — the iOS OAuth client ID from Google Cloud Console
