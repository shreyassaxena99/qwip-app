# Account Deletion with Reason — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert a reason-selection sheet before the account deletion confirmation, and send the selected reason to `DELETE /me`.

**Architecture:** Two files change. `AuthService.deleteAccount()` gains a `reason: String` parameter and a JSON body. `MyAccountView` in `ProfileView.swift` gets a new state-driven sheet (`DeleteAccountReasonSheet`) that collects the reason before triggering the existing confirmation dialog. `DeleteAccountReasonSheet` is a new private struct in `ProfileView.swift`, styled identically to the existing `ProfileFieldPickerSheet`.

**Tech Stack:** SwiftUI (`@Observable`, iOS 17+), URLSession, Supabase auth

---

### Task 1: Add `reason` parameter and request body to `AuthService.deleteAccount()`

**Files:**
- Modify: `qwip/Services/AuthService.swift`

No meaningful unit test for a network call. Verification is manual (see Step 3).

- [ ] **Step 1: Add `DeleteMeBody` and update `deleteAccount()`**

In `AuthService.swift`, replace the existing `deleteAccount()` implementation and add the `DeleteMeBody` struct. The new function must:
- Accept `reason: String`
- Encode a JSON body `{"reason": "<reason>"}` with `Content-Type: application/json`
- On 204: call `supabase.auth.signOut()`
- On non-2xx: throw `AuthError.deleteAccountFailed(status)`

Replace lines 216–228 (the `deleteAccount` function) with:

```swift
func deleteAccount(reason: String) async throws {
    guard let token = supabase.auth.currentSession?.accessToken else {
        throw AuthError.notAuthenticated
    }
    let url = URL(string: "https://spotsvc.up.railway.app/me")!
    var req = URLRequest(url: url)
    req.httpMethod = "DELETE"
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONEncoder().encode(DeleteMeBody(reason: reason))
    let (_, response) = try await URLSession.shared.data(for: req)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200...299).contains(status) else { throw AuthError.deleteAccountFailed(status) }
    try await supabase.auth.signOut()
}
```

Add `DeleteMeBody` in the `// MARK: - Profile request/response` section, alongside `PatchMeBody` (around line 233):

```swift
private struct DeleteMeBody: Encodable {
    let reason: String
}
```

- [ ] **Step 2: Confirm the project builds**

Open `qwip.xcodeproj` and build (Cmd+B). The compiler will flag all call sites of the old `deleteAccount()` — there is one in `MyAccountView` (Task 2 will fix it). Note the error but don't fix it yet; proceed to Task 2.

- [ ] **Step 3: Commit**

```bash
git add qwip/Services/AuthService.swift
git commit -m "feat: add reason param and JSON body to deleteAccount()"
```

---

### Task 2: Add `DeleteAccountReasonSheet` and update `MyAccountView`

**Files:**
- Modify: `qwip/Views/ProfileView.swift`

No meaningful unit test for a SwiftUI sheet flow. Verification is manual (see Step 3).

- [ ] **Step 1: Update `MyAccountView`**

Replace the entire `private struct MyAccountView: View` block (lines 431–522) with the version below. Changes from the original:
- Two new state properties: `showingReasonSheet` and `selectedDeletionReason`
- Delete button sets `showingReasonSheet = true` (was `showingDeleteConfirmation = true`)
- New `.sheet(isPresented: $showingReasonSheet)` presenting `DeleteAccountReasonSheet`
- New `.onChange(of: selectedDeletionReason)` that fires `showingDeleteConfirmation = true`
- `confirmationDialog` action calls `authService.deleteAccount(reason: selectedDeletionReason ?? "")` (was no-argument)

```swift
private struct MyAccountView: View {
    @Environment(AuthService.self) var authService
    @Environment(\.signOut) var signOut
    @State private var showingReasonSheet = false
    @State private var selectedDeletionReason: String? = nil
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    Button { signOut() } label: {
                        HStack {
                            Label {
                                Text("Sign Out")
                                    .font(.dmSans(14, weight: .bold))
                                    .foregroundStyle(Color.brandPrimary)
                            } icon: {
                                GlassIcon(iconName: "ic_log_out", color: Color(hex: "FF9500"))
                            }
                            Spacer()
                            Image("ic_chevron_right")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 11, height: 11)
                                .foregroundStyle(Color.brandPrimary.opacity(0.25))
                        }
                    }
                    .buttonStyle(.plain)

                    Divider().overlay(Color.brandBorder).padding(.leading, 44)

                    Button(role: .destructive) {
                        showingReasonSheet = true
                    } label: {
                        HStack {
                            Label {
                                Text("Delete Account")
                                    .font(.dmSans(14, weight: .bold))
                            } icon: {
                                GlassIcon(iconName: "ic_trash_2", color: Color(hex: "FF3B30"))
                            }
                            Spacer()
                            if isDeleting {
                                ProgressView().scaleEffect(0.8).tint(Color.brandPrimary.opacity(0.4))
                            } else {
                                Image("ic_chevron_right")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 11, height: 11)
                                    .foregroundStyle(Color.brandPrimary.opacity(0.25))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.brandSecondary.ignoresSafeArea())
        .navigationTitle("My Account")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingReasonSheet) {
            DeleteAccountReasonSheet { reason in
                selectedDeletionReason = reason
            }
        }
        .onChange(of: selectedDeletionReason) { _, reason in
            guard reason != nil else { return }
            showingDeleteConfirmation = true
        }
        .confirmationDialog("Delete Account?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                isDeleting = true
                Task {
                    do {
                        try await authService.deleteAccount(reason: selectedDeletionReason ?? "")
                    } catch {
                        deleteError = error.localizedDescription
                    }
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all saved spots. This action cannot be undone.")
        }
        .alert("Couldn't Delete Account", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }
}
```

- [ ] **Step 2: Add `DeleteAccountReasonSheet`**

Append the following private struct to `ProfileView.swift`, after the `MyAccountView` closing brace and before `// MARK: - Glass Card`:

```swift
// MARK: - Delete Account Reason Sheet

private struct DeleteAccountReasonSheet: View {
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: String? = nil

    private let reasons = [
        "I don't use qwip anymore",
        "Found a better alternative",
        "Moving out of London",
        "Technical issues",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Help us improve")
                        .font(.dmSans(14))
                        .foregroundStyle(Color.brandPrimary.opacity(0.5))
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(reasons.enumerated()), id: \.offset) { index, reason in
                            if index > 0 {
                                Divider().overlay(Color.brandBorder)
                            }
                            reasonRow(reason)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(glassBackground(cornerRadius: 20))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: Color.brandPrimary.opacity(0.08), radius: 24, x: 0, y: 8)
                    .padding(.horizontal, 24)

                    Button {
                        guard let reason = selectedReason else { return }
                        onSelect(reason)
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.dmSans(14, weight: .black))
                            .tracking(0.3)
                            .foregroundStyle(Color.brandSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.brandPrimary.opacity(selectedReason != nil ? 1 : 0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedReason == nil)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
                .padding(.bottom, 40)
            }
            .background(Color.brandSecondary.ignoresSafeArea())
            .navigationTitle("Why are you leaving?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Cancel")
                                .font(.dmSans(15))
                        }
                        .foregroundStyle(Color.brandPrimary)
                    }
                }
            }
        }
    }

    private func reasonRow(_ reason: String) -> some View {
        let selected = selectedReason == reason
        return Button {
            selectedReason = reason
        } label: {
            HStack {
                Text(reason)
                    .font(.dmSans(14, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                Spacer()
                ZStack {
                    Circle()
                        .stroke(selected ? Color.clear : Color.brandBorder, lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if selected {
                        Circle()
                            .fill(Color.brandPrimary)
                            .frame(width: 22, height: 22)
                        Image("ic_check")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 10, height: 10)
                            .foregroundStyle(Color.brandSecondary)
                    }
                }
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

- [ ] **Step 3: Build and verify**

Build in Xcode (Cmd+B). Fix any compile errors.

Then manually test the full flow:

1. **Reason sheet appears:** Profile → My Account → tap "Delete Account" → `DeleteAccountReasonSheet` slides up with title "Why are you leaving?" and 5 options.
2. **Continue disabled:** "Continue" button is dimmed (opacity 0.4) before any selection.
3. **Radio selection:** Tapping a reason fills the circle with green and highlights the row. Tapping another reason moves the selection.
4. **Continue enabled:** After selecting a reason, "Continue" button is fully opaque.
5. **Confirmation dialog:** Tapping "Continue" dismisses the sheet and immediately shows the "Delete Account?" confirmation dialog.
6. **Cancel paths:** Tapping the "Cancel" toolbar button dismisses the sheet with no side effects; tapping "Cancel" in the confirmation dialog cancels with no side effects.
7. **Deletion:** Tapping "Delete Account" in the dialog triggers the spinner, calls the API with the reason in the body, and on success signs out and returns to the sign-in screen.

- [ ] **Step 4: Commit**

```bash
git add qwip/Views/ProfileView.swift
git commit -m "feat: add reason selection sheet before account deletion"
```
