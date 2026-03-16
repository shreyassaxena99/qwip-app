# Share Spot Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Save button in `SpotDetailView`'s actions row with a Share button that shares the spot's name, address, and a Google Maps link via the iOS share sheet.

**Architecture:** Single-file change in `SpotDetailView.swift`. Add a `shareText` computed property that builds a plain `String` payload, then swap the Save `Button` in `actionsRow` for a `ShareLink` using that payload. The toolbar heart icon and all save/unsave logic remain untouched.

**Tech Stack:** SwiftUI `ShareLink` (iOS 16+), SF Symbols, existing `glassBackground` helper from `SpotCard.swift`.

---

## Chunk 1: Share button implementation

### Task 1: Add `shareText` computed property and swap Save for ShareLink

**Files:**
- Modify: `qwip/Views/SpotDetailView.swift`

**Background:**
- `SpotDetailView` is in `qwip/Views/SpotDetailView.swift`
- `detail` is of type `SpotDetail` — it has `name: String`, `displayAddress: String?`, `latitude: Double`, `longitude: Double`
- `glassBackground(cornerRadius:)` is a free function defined in `qwip/Components/SpotCard.swift` — no import needed, it's in the same module
- The existing Save button lives inside the `actionsRow` computed property (around line 282–303)
- `isSaving` and `toggleSave()` are still needed — the toolbar heart icon uses them; do NOT remove them

- [ ] **Step 1: Add `shareText` computed property**

In `SpotDetailView`, add the following computed property in the `// MARK: - Helpers` section (after `toggleSave`, before `sectionHeader`):

```swift
private var shareText: String {
    var lines = [detail.name]
    if let address = detail.displayAddress { lines.append(address) }
    let lat = String(format: "%.4f", detail.latitude)
    let lon = String(format: "%.4f", detail.longitude)
    lines.append("https://maps.google.com/?q=\(lat),\(lon)")
    return lines.joined(separator: "\n")
}
```

- [ ] **Step 2: Replace the Save button with a `ShareLink` in `actionsRow`**

Find the Save button block inside `actionsRow` (the one that calls `toggleSave()` and has the `heart` icon). Replace it entirely with:

```swift
// Share
ShareLink(item: shareText) {
    VStack(spacing: 7) {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.brandPrimary)
        Text("Share")
            .font(.dmSans(12, weight: .bold))
            .foregroundStyle(Color.brandPrimary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background(glassBackground(cornerRadius: 16))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

The result should be an `HStack` with ShareLink on the left and the Directions button (unchanged) on the right.

- [ ] **Step 3: Build and verify**

Build the app in Xcode (⌘B). Confirm:
- No compile errors
- The actions row shows "Share" (left) and "Directions" (right)
- The toolbar heart icon still toggles save/unsave correctly
- Tapping Share opens the iOS share sheet with text in the format:
  ```
  <spot name>
  <address>
  https://maps.google.com/?q=<lat>,<lon>
  ```
- For a spot with no address, the address line is absent (no blank line)
- Share is tappable while a save/unsave call is in flight

- [ ] **Step 4: Commit**

```bash
git add qwip/Views/SpotDetailView.swift
git commit -m "feat: replace Save button in actions row with Share"
```
