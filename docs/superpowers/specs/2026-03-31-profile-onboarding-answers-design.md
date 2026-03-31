# Profile — Onboarding Answers Edit Design

**Date:** 2026-03-31

## Goal

Load and display the user's onboarding answers (working_style, home_area, work_area) on the profile screen, and allow editing each via a sheet picker.

## Endpoints

**GET /users/profile/{user_id}** — called on profile view appear. Returns:
```json
{
  "exists": true,
  "user_id": "...",
  "working_style": "...",
  "home_area": "...",
  "work_area": "..."
}
```
If `exists` is false the other fields are null. Auth token must match the user_id (403 otherwise).

**POST /users/profile** — already used by onboarding. Same call for saving edits. Only include fields being updated (omit = unchanged). Requires `user_id` in the body.

## Component Changes

| File | Change |
|---|---|
| `qwip/Services/UserProfileAPIClient.swift` | Add `UserProfile` struct and `fetchProfile()` static method |
| `qwip/Views/ProfileView.swift` | Add profile state, `.task` load, "About You" card, sheet presentation, `ProfileFieldPickerSheet` private struct |

No new files.

## Data Model

```swift
struct UserProfile {
    var workingStyle: String?
    var homeArea: String?
    var workArea: String?
}

enum ProfileField: Identifiable {
    case workingStyle, homeArea, workArea
    var id: Self { self }

    var question: String {
        switch self {
        case .workingStyle: return "How do you work?"
        case .homeArea:     return "Where do you live in London?"
        case .workArea:     return "Where do you work in London?"
        }
    }

    var options: [String] {
        switch self {
        case .workingStyle:
            return ["Fully remote", "Office-based", "Freelance / self-employed", "Student", "Other"]
        case .homeArea, .workArea:
            return ["North London", "West London", "North West London", "East London",
                    "South East London", "South West London", "Central London", "Outside London"]
        }
    }
}
```

`ProfileField` is the sheet's `Identifiable` item — `editingField: ProfileField?` drives `.sheet(item:)`.

## UserProfileAPIClient — new method

```swift
static func fetchProfile(userId: String, token: String) async throws -> UserProfile
```

Decodes the full response. If `exists == false`, returns a `UserProfile` with all-nil fields (not an error). Throws on network/server errors.

New error case: `ProfileError.fetchFailed(Int)`.

## ProfileView — new state

```swift
@State private var workingStyle: String? = nil
@State private var homeArea: String? = nil
@State private var workArea: String? = nil
@State private var isLoadingProfile = true
@State private var editingField: ProfileField? = nil
@State private var saveError: String? = nil
```

`.task` on the view calls `fetchProfile()` and populates the three state values. Sets `isLoadingProfile = false` when done (success or failure — on failure values stay nil and rows show "–").

## "About You" GlassCard

Sits between Stats and Preferences sections. Three rows:

```
About You
├── How do you work?       Fully remote  ›
├── ─────────────────────────────────────
├── Where do you live?     North London  ›
├── ─────────────────────────────────────
└── Where do you work?     –             ›
```

Each row shows the question label (left) and current value or "–" (right) with a chevron. While `isLoadingProfile` is true, the value is replaced with a short placeholder bar (opacity 0.15, 60pt wide). Tapping a row sets `editingField` to the corresponding `ProfileField` case.

## ProfileFieldPickerSheet

Private struct presented via `.sheet(item: $editingField)`.

- Header: question string from `ProfileField`
- Radio-button list: same `optionRow` style as `OnboardingView` (glass card, checkmark circle)
- Currently selected option is pre-highlighted on open
- Deselection is not supported — tapping the already-selected option does nothing. The backend cannot unset a field (omitted = unchanged), so radio buttons in the profile sheet are single-select only.
- On selection of a *different* option:
  1. Capture previous value
  2. Update local state optimistically
  3. Dismiss sheet (`editingField = nil`)
  4. Call `UserProfileAPIClient.saveProfile(...)` passing the new value for just this field, nil for the other two (so they're omitted from the request body and left unchanged on the server)
  5. On failure: set `saveError`, revert local state to captured value

## Error Handling

- **Load failure:** silent — rows show "–", no alert (user can still edit)
- **Save failure:** `saveError` alert fires, local state reverts to pre-edit value

## Notes

- The `saveError` alert is on `ProfileView` (not the sheet) — the sheet dismisses before the async save completes, so errors surface after dismissal.
- Options are defined on `ProfileField.options` — no duplication with `OnboardingView`'s local arrays (they just happen to have the same values).
