# Lucide Icon Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all SF Symbol icons in spot visualizations and the profile section with Lucide image assets from Assets.xcassets.

**Architecture:** Lucide icons are stored as image sets in `Assets.xcassets` using the `ic_<lucide_name>` convention (underscores, no hyphens). All rendered with `.renderingMode(.template).resizable().scaledToFit().frame()` to support colour tinting. The `systemIcon` computed property on `SpotCategory`, `AccessType`, and `NoiseLevel` is renamed to `iconName` and returns asset names — all callsites in views follow.

**Tech Stack:** SwiftUI, Assets.xcassets image sets

---

## Prerequisites: Add 42 image assets to Assets.xcassets

Before running any tasks, export each icon from [lucide.dev](https://lucide.dev) as SVG or PDF and add it as an image set in `qwip/Assets.xcassets`. Name each set exactly as shown. In the asset inspector set **Render As: Template Image**.

| Asset name | Lucide icon | Used for |
|---|---|---|
| `ic_coffee` | `coffee` | cafe category, coffee amenity |
| `ic_laptop_2` | `laptop-2` | coworking |
| `ic_dumbbell` | `dumbbell` | gym |
| `ic_hotel` | `hotel` | hotel lobby |
| `ic_book_open` | `book-open` | library |
| `ic_utensils` | `utensils` | restaurant |
| `ic_map_pin` | `map-pin` | other category, address contact row, spots nearby stat |
| `ic_volume_x` | `volume-x` | quiet noise level |
| `ic_volume_1` | `volume-1` | moderate noise level |
| `ic_volume_2` | `volume-2` | lively noise level |
| `ic_check_circle` | `check-circle` | free access type |
| `ic_credit_card` | `credit-card` | purchase required access |
| `ic_key_round` | `key-round` | members only access |
| `ic_x` | `x` | spot detail dismiss button |
| `ic_heart` | `heart` | save spot (red = saved, brandPrimary = unsaved) |
| `ic_star` | `star` | ratings |
| `ic_share_2` | `share-2` | share action |
| `ic_route` | `route` | directions action |
| `ic_wifi` | `wifi` | wifi tag, filter pill |
| `ic_plug_zap` | `plug-zap` | power outlets tag |
| `ic_sun` | `sun` | outdoor seating amenity |
| `ic_paw_print` | `paw-print` | dog friendly amenity |
| `ic_users` | `users` | good for groups amenity |
| `ic_phone` | `phone` | phone contact row |
| `ic_globe` | `globe` | website contact row |
| `ic_arrow_up_right` | `arrow-up-right` | external link arrows (privacy policy, website) |
| `ic_arrow_right` | `arrow-right` | "View Spot" button arrow |
| `ic_check` | `check` | picker selected checkmark |
| `ic_user` | `user` | About You menu row, name row |
| `ic_settings` | `settings` | Preferences menu row |
| `ic_info` | `info` | About menu row, version row |
| `ic_circle_user` | `circle-user` | My Account menu row |
| `ic_chevron_right` | `chevron-right` | all navigation row arrows |
| `ic_briefcase` | `briefcase` | working style profile field |
| `ic_house` | `house` | home area profile field |
| `ic_building_2` | `building-2` | work area profile field |
| `ic_mail` | `mail` | email updates preference |
| `ic_sun_moon` | `sun-moon` | app theme preference |
| `ic_map` | `map` | map style preference |
| `ic_shield_check` | `shield-check` | privacy policy row |
| `ic_log_out` | `log-out` | sign out row |
| `ic_trash_2` | `trash-2` | delete account row |

---

## Task 1: Update model icon names (Spot.swift)

**Files:**
- Modify: `qwip/Models/Spot.swift`

- [ ] **Step 1: Rename `systemIcon` → `iconName` on `SpotCategory`, returning Lucide asset names**

In `qwip/Models/Spot.swift`, replace the `SpotCategory` computed property `systemIcon`:

```swift
var iconName: String {
    switch self {
    case .cafe:       return "ic_coffee"
    case .coworking:  return "ic_laptop_2"
    case .gym:        return "ic_dumbbell"
    case .hotelLobby: return "ic_hotel"
    case .library:    return "ic_book_open"
    case .restaurant: return "ic_utensils"
    case .other:      return "ic_map_pin"
    }
}
```

- [ ] **Step 2: Rename `systemIcon` → `iconName` on `AccessType`, returning Lucide asset names**

Replace the `AccessType` computed property:

```swift
var iconName: String {
    switch self {
    case .free:             return "ic_check_circle"
    case .purchaseRequired: return "ic_credit_card"
    case .membersOnly:      return "ic_key_round"
    }
}
```

- [ ] **Step 3: Rename `systemIcon` → `iconName` on `NoiseLevel`, returning Lucide asset names**

Replace the `NoiseLevel` computed property:

```swift
var iconName: String {
    switch self {
    case .quiet:    return "ic_volume_x"
    case .moderate: return "ic_volume_1"
    case .lively:   return "ic_volume_2"
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add qwip/Models/Spot.swift
git commit -m "refactor: rename systemIcon to iconName, return Lucide asset names"
```

---

## Task 2: Update SpotCard.swift (SpotAnnotationView, SpotCard, SpotRow)

**Files:**
- Modify: `qwip/Components/SpotCard.swift`

> Note: After Task 1, any remaining references to `.systemIcon` will produce a compile error — this task clears them all in this file.

- [ ] **Step 1: Update category icon in `SpotCard`**

In `SpotCard.body`, replace:

```swift
Image(systemName: spot.category.systemIcon)
    .font(.system(size: 17, weight: .semibold))
    .foregroundStyle(Color.brandPrimary)
```

with:

```swift
Image(spot.category.iconName)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 17, height: 17)
    .foregroundStyle(Color.brandPrimary)
```

- [ ] **Step 2: Update star rating in `SpotCard`**

Replace:

```swift
Image(systemName: "star.fill")
    .font(.system(size: 9))
    .foregroundStyle(.orange)
```

with:

```swift
Image("ic_star")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 9, height: 9)
    .foregroundStyle(.orange)
```

- [ ] **Step 3: Update category icon in `SpotRow`**

Replace:

```swift
Image(systemName: spot.category.systemIcon)
    .font(.system(size: 22, weight: .semibold))
    .foregroundStyle(Color.brandSecondary)
```

with:

```swift
Image(spot.category.iconName)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 22, height: 22)
    .foregroundStyle(Color.brandSecondary)
```

- [ ] **Step 4: Update star rating in `SpotRow`**

Replace:

```swift
Image(systemName: "star.fill")
    .font(.system(size: 9))
    .foregroundStyle(.orange)
```

with:

```swift
Image("ic_star")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 9, height: 9)
    .foregroundStyle(.orange)
```

- [ ] **Step 5: Update chevron in `SpotRow`**

Replace:

```swift
Image(systemName: "chevron.right")
    .font(.system(size: 11, weight: .bold))
    .foregroundStyle(Color.brandPrimary.opacity(0.25))
```

with:

```swift
Image("ic_chevron_right")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(Color.brandPrimary.opacity(0.25))
```

- [ ] **Step 6: Update category icon in `SpotAnnotationView`**

Replace:

```swift
Image(systemName: spot.category.systemIcon)
    .font(.system(size: isSelected ? 18 : 14, weight: .bold))
    .foregroundStyle(isSelected ? Color.brandPrimary : Color.brandSecondary)
```

with:

```swift
Image(spot.category.iconName)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: isSelected ? 18 : 14, height: isSelected ? 18 : 14)
    .foregroundStyle(isSelected ? Color.brandPrimary : Color.brandSecondary)
```

- [ ] **Step 7: Commit**

```bash
git add qwip/Components/SpotCard.swift
git commit -m "feat: use Lucide icons in SpotCard, SpotRow, SpotAnnotationView"
```

---

## Task 3: Update ProfileView.swift

**Files:**
- Modify: `qwip/Views/ProfileView.swift`

- [ ] **Step 1: Update `GlassIcon` to use asset images**

Replace the entire `GlassIcon` struct:

```swift
private struct GlassIcon: View {
    let iconName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
            Image(iconName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.white)
        }
    }
}
```

- [ ] **Step 2: Update `BigStatCard` to use asset images**

In `BigStatCard.body`, replace:

```swift
Image(systemName: icon)
    .font(.system(size: 18, weight: .bold))
    .foregroundStyle(iconColor)
```

with:

```swift
Image(icon)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 18, height: 18)
    .foregroundStyle(iconColor)
```

- [ ] **Step 3: Update `ProfileField.systemImage` → `iconName`**

In `ProfileField`, replace the `systemImage` computed property with:

```swift
var iconName: String {
    switch self {
    case .workingStyle: return "ic_briefcase"
    case .homeArea:     return "ic_house"
    case .workArea:     return "ic_building_2"
    }
}
```

- [ ] **Step 4: Update `menuRow` helper and its call sites**

Update the `menuRow` helper (the `GlassIcon` label has changed to `iconName:`):

```swift
private func menuRow(_ title: String, icon: String, color: Color, dest: ProfileDestination) -> some View {
    NavigationLink(value: dest) {
        HStack(spacing: 12) {
            GlassIcon(iconName: icon, color: color)
            Text(title)
                .font(.dmSans(14, weight: .semibold))
                .foregroundStyle(Color.brandPrimary)
            Spacer()
            Image("ic_chevron_right")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 11, height: 11)
                .foregroundStyle(Color.brandPrimary.opacity(0.25))
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
```

Update the four `menuRow` calls in `ProfileView.body`:

```swift
menuRow("About You",   icon: "ic_user",        color: Color.brandPrimary,   dest: .aboutYou)
menuRow("Preferences", icon: "ic_settings",     color: Color(hex: "5E6AD2"), dest: .preferences)
menuRow("About",       icon: "ic_info",         color: Color(hex: "34C759"), dest: .about)
menuRow("My Account",  icon: "ic_circle_user",  color: Color(hex: "FF9500"), dest: .myAccount)
```

Update the two `BigStatCard` calls:

```swift
BigStatCard(value: "\(savedSpotService.savedEntries.count)", label: "Saved Spots",  icon: "ic_heart",   iconColor: Color(hex: "e74c3c"))
BigStatCard(value: "\(store.spots.count)",                   label: "Spots Nearby", icon: "ic_map_pin", iconColor: Color.brandPrimary)
```

- [ ] **Step 5: Update `AboutYouView` icons**

In `AboutYouView.body`, update the name row `GlassIcon`:

```swift
GlassIcon(iconName: "ic_user", color: Color(hex: "5E6AD2"))
```

Replace the chevron in the name row button:

```swift
Image("ic_chevron_right")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(Color.brandPrimary.opacity(0.25))
```

In `profileFieldRow`, update the GlassIcon (uses `field.iconName` from Step 3):

```swift
GlassIcon(iconName: field.iconName, color: field.iconColor)
```

Replace the chevron in `profileFieldRow`:

```swift
Image("ic_chevron_right")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(Color.brandPrimary.opacity(0.25))
```

In `ProfileFieldPickerSheet.optionRow`, replace the checkmark:

```swift
Image("ic_check")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 10, height: 10)
    .foregroundStyle(Color.brandSecondary)
```

- [ ] **Step 6: Update `PreferencesView` GlassIcon calls**

```swift
GlassIcon(iconName: "ic_mail",     color: .brandPrimary)
GlassIcon(iconName: "ic_sun_moon", color: Color(hex: "5E6AD2"))
GlassIcon(iconName: "ic_map",      color: Color.brandPrimary)
```

- [ ] **Step 7: Update `AboutAppView` icons**

Replace GlassIcon calls:

```swift
GlassIcon(iconName: "ic_info",         color: Color(hex: "5E6AD2"))
GlassIcon(iconName: "ic_shield_check", color: Color(hex: "34C759"))
```

Replace the external link arrow:

```swift
Image("ic_arrow_up_right")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(Color.brandPrimary.opacity(0.25))
```

- [ ] **Step 8: Update `MyAccountView` icons**

Replace GlassIcon calls:

```swift
GlassIcon(iconName: "ic_log_out", color: Color(hex: "FF9500"))
GlassIcon(iconName: "ic_trash_2", color: Color(hex: "FF3B30"))
```

Replace both `Image(systemName: "chevron.right")` occurrences (sign out row, delete account row):

```swift
Image("ic_chevron_right")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(Color.brandPrimary.opacity(0.25))
```

- [ ] **Step 9: Commit**

```bash
git add qwip/Views/ProfileView.swift
git commit -m "feat: use Lucide icons throughout ProfileView and sub-views"
```

---

## Task 4: Update SpotDetailView.swift

**Files:**
- Modify: `qwip/Views/SpotDetailView.swift`

> Note: `TagChip`, `AmenityChip`, and `ContactRow` each take an `icon: String` parameter. After this task that string is a Lucide asset name, not a system name — the rendering inside each component is updated first (Steps 1–3), then the call sites (Steps 4–6).

- [ ] **Step 1: Update `TagChip` rendering**

In `TagChip.body`, replace:

```swift
Image(systemName: icon)
    .font(.system(size: 11, weight: .semibold))
    .foregroundStyle(active ? Color.brandPrimary : Color.brandPrimary.opacity(0.35))
```

with:

```swift
Image(icon)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(active ? Color.brandPrimary : Color.brandPrimary.opacity(0.35))
```

- [ ] **Step 2: Update `AmenityChip` rendering**

In `AmenityChip.body`, replace:

```swift
Image(systemName: icon)
    .font(.system(size: 11, weight: .semibold))
```

with:

```swift
Image(icon)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
```

- [ ] **Step 3: Update `ContactRow` rendering**

In `ContactRow.rowContent`, replace the icon image:

```swift
Image(icon)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 18, height: 18)
    .foregroundStyle(Color.brandPrimary)
    .frame(width: 24)
```

Replace the external link arrow:

```swift
Image("ic_arrow_up_right")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(Color.brandPrimary.opacity(0.4))
```

- [ ] **Step 4: Update `tagsSection` TagChip call sites**

```swift
TagChip(icon: "ic_wifi",    label: detail.wifiAvailable ? "Wi-Fi" : "No Wi-Fi",   active: detail.wifiAvailable)
TagChip(icon: "ic_plug_zap", label: detail.powerOutlets  ? "Power" : "No Power",  active: detail.powerOutlets)
if let noise = detail.noiseMatrix?.currentLevel(),
   let text = detail.noiseMatrix?.currentDisplayText() {
    TagChip(icon: noise.iconName, label: text, active: true)
}
TagChip(icon: detail.accessType.iconName, label: detail.accessType.displayName, active: true)
```

- [ ] **Step 5: Update `amenitiesSection` AmenityChip call sites**

```swift
if detail.outdoorSeating == true { AmenityChip(icon: "ic_sun",       label: "Outdoor Seating") }
if detail.allowsDogs == true     { AmenityChip(icon: "ic_paw_print", label: "Dog Friendly") }
if detail.servesCoffee == true   { AmenityChip(icon: "ic_coffee",    label: "Coffee") }
if detail.goodForGroups == true  { AmenityChip(icon: "ic_users",     label: "Good for Groups") }
```

- [ ] **Step 6: Update `contactSection` ContactRow call sites**

```swift
ContactRow(icon: "ic_map_pin", text: address, url: nil)
ContactRow(icon: "ic_phone",   text: phone,   url: URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))"))
ContactRow(icon: "ic_globe",   text: display, url: url)
```

- [ ] **Step 7: Update star rating in `headerSection`**

Replace:

```swift
Image(systemName: "star.fill")
    .font(.system(size: 11))
    .foregroundStyle(.orange)
```

with:

```swift
Image("ic_star")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(.orange)
```

- [ ] **Step 8: Update `actionsRow` icons**

Replace the share button icon:

```swift
Image("ic_share_2")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 22, height: 22)
    .foregroundStyle(Color.brandPrimary)
```

Replace the directions button icon:

```swift
Image("ic_route")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 22, height: 22)
    .foregroundStyle(Color.brandSecondary)
```

- [ ] **Step 9: Update `gradientHero` category icon**

Replace:

```swift
Image(systemName: detail.category.systemIcon)
    .font(.system(size: 34, weight: .semibold))
    .foregroundStyle(Color.brandSecondary)
```

with:

```swift
Image(detail.category.iconName)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 34, height: 34)
    .foregroundStyle(Color.brandSecondary)
```

- [ ] **Step 10: Update hero overlay buttons**

Replace the dismiss button icon:

```swift
Image("ic_x")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
    .foregroundStyle(Color.brandPrimary)
```

Replace the save button icon (remove `.contentTransition(.symbolEffect(.replace))` — that modifier only works with SF Symbols):

```swift
Image("ic_heart")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 13, height: 13)
    .foregroundStyle(savedSpotService.isSaved(detail.id) ? Color(hex: "e74c3c") : Color.brandPrimary)
```

- [ ] **Step 11: Commit**

```bash
git add qwip/Views/SpotDetailView.swift
git commit -m "feat: use Lucide icons throughout SpotDetailView"
```

---

## Task 5: Update MapView.swift

**Files:**
- Modify: `qwip/Views/MapView.swift`

> `FilterPill` and `NoisePill` (both defined in this file) pass icon strings to `Image(systemName:)`. After Task 1 renames `systemIcon` → `iconName`, these components must switch to asset rendering or they break. Steps 1–2 fix the components; Steps 3–6 update the spot preview tile.

- [ ] **Step 1: Update `FilterPill` icon rendering**

In `FilterPill.pill`, replace:

```swift
Image(systemName: icon)
    .font(.system(size: 11, weight: .bold))
```

with:

```swift
Image(icon)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 11, height: 11)
```

- [ ] **Step 2: Update `NoisePill` icon rendering**

In `NoisePill.body`, replace:

```swift
if let icon {
    Image(systemName: icon)
        .font(.system(size: 10, weight: .bold))
}
```

with:

```swift
if let icon {
    Image(icon)
        .renderingMode(.template)
        .resizable()
        .scaledToFit()
        .frame(width: 10, height: 10)
}
```

- [ ] **Step 3: Update `statChip` helper**

Replace the `Image(systemName: icon)` in `statChip`:

```swift
Image(icon)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 10, height: 10)
    .foregroundStyle(iconColor)
```

Update the three `statChip` call sites in `selectedSpotTile`:

```swift
statChip(icon: "ic_star", iconColor: .orange, value: spot.formattedRating, label: "RATING")
if let noise = spot.noiseMatrix?.currentLevel() {
    dividerLine()
    statChip(icon: noise.iconName, iconColor: Color.brandPrimary, value: noise.displayName, label: "USUALLY")
}
if spot.wifiAvailable {
    dividerLine()
    statChip(icon: "ic_wifi", iconColor: Color.brandPrimary, value: "Wi-Fi", label: "AVAIL")
}
```

- [ ] **Step 4: Update category icon in `selectedSpotTile`**

Replace:

```swift
Image(systemName: spot.category.systemIcon)
    .font(.system(size: 22, weight: .semibold))
    .foregroundStyle(Color.brandSecondary)
```

with:

```swift
Image(spot.category.iconName)
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 22, height: 22)
    .foregroundStyle(Color.brandSecondary)
```

- [ ] **Step 5: Update heart icon in `selectedSpotTile`**

Replace (also remove `.contentTransition(.symbolEffect(.replace))` — only works with SF Symbols):

```swift
Image("ic_heart")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 13, height: 13)
    .foregroundStyle(savedSpotService.isSaved(spot.id) ? Color(hex: "e74c3c") : Color.brandPrimary)
```

- [ ] **Step 6: Update "View Spot" arrow in `selectedSpotTile`**

Replace:

```swift
Image(systemName: "arrow.right")
    .font(.system(size: 13, weight: .bold))
```

with:

```swift
Image("ic_arrow_right")
    .renderingMode(.template)
    .resizable()
    .scaledToFit()
    .frame(width: 13, height: 13)
```

- [ ] **Step 7: Update `filterBarOverlay` caller for category filter pills**

In `filterBarOverlay`, the `ForEach(SpotCategory.allCases)` block passes the icon to `FilterPill`. Update it to use `iconName`:

```swift
FilterPill(
    title: category.displayName,
    icon: category.iconName,
    isActive: store.selectedCategory == category
)
```

- [ ] **Step 8: Commit**

```bash
git add qwip/Views/MapView.swift
git commit -m "feat: use Lucide icons in MapView spot preview, FilterPill, NoisePill"
```
