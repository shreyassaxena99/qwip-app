# Profile — Onboarding Answers Edit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load the user's onboarding answers from the backend on profile view open and allow editing each via a sheet picker.

**Architecture:** `UserProfileAPIClient` gets a `fetchProfile()` method that returns a `UserProfile` struct. `ProfileView` loads the profile in a `.task`, displays values in a new "About You" `GlassCard`, and presents a `ProfileFieldPickerSheet` for in-place edits with optimistic updates and error revert. No new files — all additions go into the two existing files.

**Tech Stack:** SwiftUI (`@State`, `.sheet(item:)`, `.task`), `async/await`, `UserProfileAPIClient` (existing), `AuthService` (existing)

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Modify | `qwip/Services/UserProfileAPIClient.swift` | Add `UserProfile` struct, `fetchProfile()`, `ProfileError.fetchFailed` |
| Modify | `qwip/Views/ProfileView.swift` | Add `ProfileField` enum, new state, `.task` load, "About You" card, `ProfileFieldPickerSheet`, `save()`, `saveError` alert |

---

### Task 1: Add `UserProfile` and `fetchProfile()` to `UserProfileAPIClient`

**Files:**
- Modify: `qwip/Services/UserProfileAPIClient.swift`

- [ ] **Step 1: Add `UserProfile` struct above `UserProfileAPIClient`**

Insert this block immediately before `struct UserProfileAPIClient {` (currently line 3):

```swift
struct UserProfile {
    var workingStyle: String?
    var homeArea: String?
    var workArea: String?
}
```

- [ ] **Step 2: Add `fetchProfile()` method inside `UserProfileAPIClient`**

Add after the closing brace of `fetchExists()` (after line 19), still inside the struct:

```swift
    /// Fetches the full onboarding profile. Returns a UserProfile with nil fields if `exists == false`.
    /// Throws ProfileError.fetchFailed on network or server errors.
    static func fetchProfile(userId: String, token: String) async throws -> UserProfile {
        guard let url = URL(string: "\(baseURL)/users/profile/\(userId)") else {
            throw ProfileError.fetchFailed(0)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw ProfileError.fetchFailed(status) }
        struct ProfileResponse: Decodable {
            let exists: Bool
            let workingStyle: String?
            let homeArea: String?
            let workArea: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let body = try decoder.decode(ProfileResponse.self, from: data)
        return UserProfile(
            workingStyle: body.workingStyle,
            homeArea: body.homeArea,
            workArea: body.workArea
        )
    }
```

- [ ] **Step 3: Add `fetchFailed` case to `ProfileError`**

Replace the existing `ProfileError` enum (currently at the bottom of the file):

```swift
enum ProfileError: LocalizedError {
    case saveFailed(Int)
    case fetchFailed(Int)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let code):  return "Profile save failed (server error \(code))."
        case .fetchFailed(let code): return "Couldn't load profile (server error \(code))."
        }
    }
}
```

- [ ] **Step 4: Build in Xcode (Cmd+B)**

Expected: clean build. `UserProfile`, `fetchProfile()`, `ProfileError.fetchFailed` all compile.

- [ ] **Step 5: Commit**

```bash
git add qwip/Services/UserProfileAPIClient.swift
git commit -m "feat: add UserProfile model and fetchProfile to UserProfileAPIClient"
```

---

### Task 2: Add `ProfileField` enum, state, `.task`, and "About You" card to ProfileView

**Files:**
- Modify: `qwip/Views/ProfileView.swift`

- [ ] **Step 1: Add `ProfileField` enum before `struct ProfileView`**

Insert this block immediately before `struct ProfileView: View {` (currently line 3):

```swift
private enum ProfileField: Identifiable {
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

    var systemImage: String {
        switch self {
        case .workingStyle: return "briefcase.fill"
        case .homeArea:     return "house.fill"
        case .workArea:     return "building.2.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .workingStyle: return Color(hex: "5E6AD2")
        case .homeArea:     return Color(hex: "34C759")
        case .workArea:     return Color.brandPrimary
        }
    }
}
```

- [ ] **Step 2: Add new `@State` properties to `ProfileView`**

In `ProfileView`, after the existing `@State private var isDeleting = false` line, add:

```swift
    @State private var workingStyle: String? = nil
    @State private var homeArea: String? = nil
    @State private var workArea: String? = nil
    @State private var isLoadingProfile = true
    @State private var editingField: ProfileField? = nil
    @State private var saveError: String? = nil
```

- [ ] **Step 3: Add the "About You" GlassCard to the body**

In `ProfileView.body`, inside the `VStack(spacing: 16)`, add this block **between** the Stats `HStack` and the `GlassCard(header: "Preferences")`:

```swift
                    // MARK: About You
                    GlassCard(header: "About You") {
                        profileFieldRow(.workingStyle)
                        Divider().overlay(Color.brandPrimary.opacity(0.08)).padding(.leading, 44)
                        profileFieldRow(.homeArea)
                        Divider().overlay(Color.brandPrimary.opacity(0.08)).padding(.leading, 44)
                        profileFieldRow(.workArea)
                    }
```

- [ ] **Step 4: Add the `profileFieldRow` computed method**

Add this private method to `ProfileView`, alongside `profileHeader`:

```swift
    private func profileFieldRow(_ field: ProfileField) -> some View {
        Button {
            editingField = field
        } label: {
            HStack {
                Label {
                    Text(field.question)
                        .font(.dmSans(14, weight: .bold))
                        .foregroundStyle(Color.brandPrimary)
                } icon: {
                    GlassIcon(systemName: field.systemImage, color: field.iconColor)
                }
                Spacer()
                if isLoadingProfile {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.brandPrimary.opacity(0.15))
                        .frame(width: 60, height: 12)
                } else {
                    let value: String? = {
                        switch field {
                        case .workingStyle: return workingStyle
                        case .homeArea:     return homeArea
                        case .workArea:     return workArea
                        }
                    }()
                    Text(value ?? "–")
                        .font(.dmSans(13))
                        .foregroundStyle(Color.brandPrimary.opacity(value != nil ? 0.5 : 0.3))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingProfile)
    }
```

- [ ] **Step 5: Add `.task`, `.sheet`, and `saveError` alert to the ScrollView modifier chain**

In `ProfileView.body`, the `ScrollView` currently has `.background(...)`, `.navigationTitle(...)` etc. chained onto it. Add three more modifiers after the last existing `.alert("Edit Name", ...)`:

```swift
            .task {
                guard let session = authService.session else {
                    isLoadingProfile = false
                    return
                }
                if let profile = try? await UserProfileAPIClient.fetchProfile(
                    userId: session.user.id.uuidString,
                    token: session.accessToken
                ) {
                    workingStyle = profile.workingStyle
                    homeArea     = profile.homeArea
                    workArea     = profile.workArea
                }
                isLoadingProfile = false
            }
            .sheet(item: $editingField) { field in
                let current: String? = {
                    switch field {
                    case .workingStyle: return workingStyle
                    case .homeArea:     return homeArea
                    case .workArea:     return workArea
                    }
                }()
                ProfileFieldPickerSheet(field: field, currentValue: current) { newValue in
                    save(field: field, newValue: newValue)
                }
            }
            .alert("Couldn't Save", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
```

- [ ] **Step 6: Add the `save()` method to `ProfileView`**

Add this private method alongside `profileFieldRow` and `profileHeader`:

```swift
    private func save(field: ProfileField, newValue: String) {
        let oldValue: String? = {
            switch field {
            case .workingStyle: return workingStyle
            case .homeArea:     return homeArea
            case .workArea:     return workArea
            }
        }()
        // Optimistic update
        switch field {
        case .workingStyle: workingStyle = newValue
        case .homeArea:     homeArea = newValue
        case .workArea:     workArea = newValue
        }
        // Dismiss sheet
        editingField = nil
        // Persist
        Task {
            do {
                guard let session = authService.session else { return }
                try await UserProfileAPIClient.saveProfile(
                    userId: session.user.id.uuidString,
                    token: session.accessToken,
                    workingStyle: field == .workingStyle ? newValue : nil,
                    homeArea:     field == .homeArea     ? newValue : nil,
                    workArea:     field == .workArea     ? newValue : nil
                )
            } catch {
                // Revert on failure
                switch field {
                case .workingStyle: workingStyle = oldValue
                case .homeArea:     homeArea = oldValue
                case .workArea:     workArea = oldValue
                }
                saveError = error.localizedDescription
            }
        }
    }
```

- [ ] **Step 7: Build in Xcode (Cmd+B)**

Expected: clean build. The "About You" card compiles; the `.task`, `.sheet`, and alert all compile.

- [ ] **Step 8: Commit**

```bash
git add qwip/Views/ProfileView.swift
git commit -m "feat: add About You card and profile field loading to ProfileView"
```

---

### Task 3: Add `ProfileFieldPickerSheet` to ProfileView

**Files:**
- Modify: `qwip/Views/ProfileView.swift`

- [ ] **Step 1: Add `ProfileFieldPickerSheet` at the bottom of `ProfileView.swift`**

After the closing brace of `GlassIcon` (the last private struct in the file), add:

```swift
// MARK: - Profile Field Picker Sheet

private struct ProfileFieldPickerSheet: View {
    let field: ProfileField
    let currentValue: String?
    var onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(field.options.enumerated()), id: \.offset) { index, option in
                            if index > 0 {
                                Divider().overlay(Color.brandPrimary.opacity(0.07))
                            }
                            optionRow(option)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(glassBackground(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                }
                .padding(.bottom, 40)
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle(field.question)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func optionRow(_ option: String) -> some View {
        let selected = currentValue == option
        return Button {
            guard !selected else { return }
            onSave(option)
        } label: {
            HStack {
                Text(option)
                    .font(.dmSans(14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.brandPrimary.opacity(selected ? 0 : 0.2), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(selected ? Color.brandPrimary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build in Xcode (Cmd+B)**

Expected: clean build. `ProfileFieldPickerSheet` compiles; sheet presents correctly from the `.sheet(item: $editingField)` modifier added in Task 2.

- [ ] **Step 3: Commit**

```bash
git add qwip/Views/ProfileView.swift
git commit -m "feat: add ProfileFieldPickerSheet for onboarding answer editing"
```

---

### Task 4: Manual verification

- [ ] **Step 1: Run on simulator (Cmd+R), sign in with email, open Profile tab**

Verify:
- "About You" card appears between Stats and Preferences
- Values load from the server and populate after a brief placeholder animation
- If the user hasn't completed onboarding, all three rows show "–"

- [ ] **Step 2: Tap a row**

Verify the sheet slides up with the question as the nav title and the correct options listed. The previously-saved value should be pre-highlighted.

- [ ] **Step 3: Select a different option**

Verify the sheet dismisses immediately, the row updates to the new value, and the change persists after closing and re-opening Profile.

- [ ] **Step 4: Tap the already-selected option**

Verify nothing happens (no dismiss, no save).
