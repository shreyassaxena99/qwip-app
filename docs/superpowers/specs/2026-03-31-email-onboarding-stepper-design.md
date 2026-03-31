# Email Onboarding Stepper

**Date:** 2026-03-31

## Problem

The email sign-in flow currently has two disconnected screens: an OTP verification view (presented as a `fullScreenCover` from `SignInView`) and a separate `NameCollectionView` phase in `RootView`. The name step should be folded into the OTP stepper as a seamless second step — but only for email users (Google provides the name automatically).

The non-obvious constraint: `OTPVerificationView` is a `fullScreenCover` on `SignInView`. When OTP is verified, the session is set and `RootView` transitions away from `SignInView`, which dismisses the cover mid-flow before the name step can show.

## Solution: Move the fullScreenCover to RootView

`RootView` owns the `fullScreenCover`. It persists through all phase transitions in the underlying ZStack. `SignInView` fires a callback after OTP is sent; `RootView` presents the two-step stepper. After both steps complete the cover dismisses to reveal `ContentView` already waiting underneath.

## Component Changes

| File | Change |
|------|--------|
| `RootView.swift` | Add `@State var pendingOTPEmail: String?`. Remove `needsDisplayName → NameCollectionView` branch. Add `.fullScreenCover` presenting `EmailOnboardingView`. Pass `onOTPSent` callback into `SignInView`. |
| `SignInView.swift` | Add `var onOTPSent: (String) -> Void`. Remove `@State var showOTP` and the existing `fullScreenCover`. Call `onOTPSent(email)` after `sendOTP` succeeds. |
| `EmailOnboardingView.swift` | **New file.** Two-step stepper (OTP → Name). Calls `onBack()` if user backs out of OTP step, `onComplete()` after name is saved. |
| `OTPVerificationView.swift` | Absorbed into `EmailOnboardingView` — its UI and logic move there. File deleted. |
| `NameCollectionView.swift` | Deleted. Name step lives in `EmailOnboardingView` only. |

## User-Facing Flow

```
SignInView (enter email)
  → sendOTP() succeeds
  → RootView sets pendingOTPEmail
  → fullScreenCover: EmailOnboardingView appears
      Step 1: OTP entry → verifyOTP() → session set (RootView transitions underneath, cover stays)
      Step 2: Name entry → updateProfile() → needsDisplayName = false
  → onComplete() → pendingOTPEmail = nil → cover dismisses
  → ContentView (already underneath)
```

Back button on Step 1 calls `onBack()` → `pendingOTPEmail = nil` → cover dismisses → user is back on `SignInView`.

No back button on Step 2: you can't un-verify an OTP.

## EmailOnboardingView Internals

```swift
enum Step { case otp, name }
@State private var step: Step = .otp
```

- **Step .otp** — OTP entry UI (six cells, verify button, resend). On success: `step = .name` with a slide-right transition.
- **Step .name** — Name entry UI (text field, continue button). On success: calls `onComplete()`.

Transition: `.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))`.

## Google Sign-In

Unaffected. `needsDisplayName` is already `false` for Google users because `userMetadata["name"]` is populated. The stepper is never presented.

## What Is Removed

- `NameCollectionView.swift` — deleted entirely.
- `needsDisplayName` branch in `RootView` — removed.
- `showOTP` state and `fullScreenCover` in `SignInView` — removed.
- `OTPVerificationView.swift` — absorbed into `EmailOnboardingView`, deleted.
