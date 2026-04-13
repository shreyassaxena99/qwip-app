# Auth Architecture

## Approach

Option B: AuthService singleton + Supabase Swift SDK.

A single `AuthService` class wraps all Supabase auth calls. Views only talk to `AuthService`, never to Supabase directly. `RootView` observes `AuthService.isAuthenticated` to drive the app phase.

## AuthService (@Observable)

```
AuthService
├── session: Session?          ← nil = not logged in
├── isAuthenticated: Bool      ← computed from session
├── signInWithApple()          ← native ASAuthorizationController sheet
├── signInWithGoogle()         ← GoogleSignIn-iOS SDK, then Supabase
├── sendOTP(email:)            ← triggers 6-digit code email
├── verifyOTP(email:token:)    ← confirms the code, sets session
├── restoreSession()           ← called once on launch, checks Keychain
└── signOut()
```

## Session Persistence

- Supabase Swift SDK automatically stores the session in the iOS Keychain
- Refresh token expiry set to 30 days (2592000 seconds) in Supabase dashboard
- On launch, `restoreSession()` checks the Keychain — if valid session exists, user goes straight to main with no sign-in prompt
- If the refresh token has expired (>30 days inactive), user is sent back to sign-in

## Sign-in methods

- **Apple**: native `ASAuthorizationController` → identity token → `supabase.auth.signInWithIdToken(credentials:)` with `.apple` provider
- **Google**: `GoogleSignIn-iOS` SDK → ID token → `supabase.auth.signInWithIdToken(credentials:)` with `.google` provider
- **Email OTP**: `supabase.auth.signInWithOTP(email:)` → navigates to `OTPVerificationView` → user enters 6-digit code → `supabase.auth.verifyOTP(email:token:)` → session set

Both Apple and Google use the native in-app approach (no browser redirect). The user never leaves the app.

## Email OTP — unified sign in + sign up

Supabase automatically creates an account on first OTP sign-in if the email doesn't exist, or signs the user in if it does. No separate sign-up screen needed.
