# Account Deletion with Reason — Design

**Date:** 2026-04-13

## Problem

The existing "Delete Account" button in My Account goes straight to a confirmation dialog and calls `DELETE /me` with no body. The endpoint now requires a `reason` field (min 1 char). We also want to capture why users are leaving before they delete.

## Goal

Insert a reason-selection sheet before the existing confirmation dialog. The reason is sent with the `DELETE /me` API call.

## Deletion Reasons

- "I don't use qwip anymore"
- "Found a better alternative"
- "Moving out of London"
- "Technical issues"
- "Other"

## UX Flow

1. User taps "Delete Account" in `MyAccountView`
2. `DeleteAccountReasonSheet` slides up as a `.sheet`
3. Sheet shows: title "Why are you leaving?", subtitle "Help us improve", 5 radio-button options, "Continue" button (disabled until a reason is selected)
4. User selects a reason → taps "Continue" → sheet dismisses
5. `MyAccountView.onChange(of: selectedDeletionReason)` fires → shows the existing `confirmationDialog`
6. User taps "Delete Account" in the dialog → calls `authService.deleteAccount(reason:)`
7. On 204: `supabase.auth.signOut()` is called (session clears, app returns to sign-in)
8. On error: existing `deleteError` alert shown

## Architecture

### `ProfileView.swift`

**`MyAccountView`** — two new state properties:
- `@State private var showingReasonSheet = false` — replaces `showingDeleteConfirmation` as the initial trigger
- `@State private var selectedDeletionReason: String? = nil` — set by the sheet closure; `onChange` fires `showingDeleteConfirmation = true`

The `showingDeleteConfirmation` / `confirmationDialog` / `deleteError` alert / `isDeleting` state all remain unchanged. The only change is that the button now sets `showingReasonSheet = true` instead of `showingDeleteConfirmation = true`, and a `.sheet(isPresented: $showingReasonSheet)` + `.onChange(of: selectedDeletionReason)` are added.

**`DeleteAccountReasonSheet`** — new private struct in `ProfileView.swift`:
- Styled identically to `ProfileFieldPickerSheet`: cream background, glass card, radio buttons (filled `brandPrimary` circle + white checkmark when selected)
- Navigation bar: title "Why are you leaving?", leading Cancel button (`dismiss()`)
- Subtitle below nav: "Help us improve"
- "Continue" button at bottom: disabled (`.opacity(0.4)`) until a reason is selected; on tap calls `onSelect(reason)` then dismisses
- No `NavigationStack` wrapper needed — presented as a sheet which provides its own nav context

### `AuthService.swift`

`deleteAccount(reason: String)` — adds `reason` parameter:
- Request body: `{"reason": "<selected reason>"}` with `Content-Type: application/json`
- 204 → call `supabase.auth.signOut()`
- Non-2xx → throw `AuthError.deleteAccountFailed(status)`

New private `DeleteMeBody: Encodable` struct with a single `reason: String` field.

## Error Handling

| HTTP status | Behaviour |
|-------------|-----------|
| 204 | Sign out, session clears, app returns to sign-in |
| 403 | `deleteAccountFailed(403)` → "Account deletion failed (server error 403). Please try again." |
| 422 | `deleteAccountFailed(422)` → same message (client-side reason validation prevents this in practice) |
| 500 | `deleteAccountFailed(500)` → same message |

## Files Changed

| File | Change |
|------|--------|
| `qwip/Views/ProfileView.swift` | Add `DeleteAccountReasonSheet`; update `MyAccountView` trigger logic |
| `qwip/Services/AuthService.swift` | Add `reason` param + body to `deleteAccount()`; add `DeleteMeBody` |

## Out of Scope

- Free-text "other" input field
- Analytics tracking of deletion reason
- Any changes outside `ProfileView.swift` and `AuthService.swift`
