# Share Spot — Design Spec

**Date:** 2026-03-16

## Summary

Replace the Save button in `SpotDetailView`'s actions row with a Share button. Save remains accessible via the existing heart icon in the navigation bar toolbar. Share uses SwiftUI's native `ShareLink` with a plain `String` payload.

## Scope

- `qwip/Views/SpotDetailView.swift` only — no new files or types.

## Actions Row Change

The `actionsRow` currently has two buttons: Save (left, glass style) and Directions (right, filled green). The Save button is replaced with a `ShareLink` styled identically to the old Save button (glass background, same padding, same font). Directions is unchanged.

```
[ Share ]  [ Directions ]
```

## Share Content

A computed property `shareText: String` on `SpotDetailView` builds the payload. Lines are joined with `\n`; if `displayAddress` is nil the address line is omitted entirely with no extra blank line:

```
<spot name>
<address if present>
https://maps.google.com/?q=<lat>,<lon>
```

- **Address line:** `detail.displayAddress` — defined on `SpotDetail` in `Spot.swift` as `formattedAddress ?? shortAddress`. Both fields are `String?` (decoded with `decodeIfPresent`), so `displayAddress` can legitimately be nil. May be a full street address (e.g. `"1 Endell St, London WC2H 9HA"`) — that is intentional.
- **Coordinates:** 4 decimal places via `String(format: "%.4f", ...)`, e.g. `https://maps.google.com/?q=51.5136,-0.1340`. Spots with zero coordinates (e.g. bad data) will produce `?q=0.0000,0.0000` — acceptable; no special-casing required.

Example (address present):
```
Workshop Coffee
1 Endell St, London WC2H 9HA
https://maps.google.com/?q=51.5136,-0.1340
```

Example (no address):
```
Workshop Coffee
https://maps.google.com/?q=51.5136,-0.1340
```

## Share Button Appearance

Mirrors the existing Save button layout exactly — same `VStack(spacing: 7)`, `.frame(maxWidth: .infinity)`, `.padding(.vertical, 18)`, placed inside the `ShareLink`'s `label:` closure. Add `.contentShape(Rectangle())` to ensure the full card area is tappable (not just the icon/text):

- Icon: `square.and.arrow.up`, size 22, semibold, `Color.brandPrimary`
- Label text: "Share", dmSans 12 bold, `Color.brandPrimary`
- Background: `glassBackground(cornerRadius: 16)` — a free function in `SpotCard.swift`, already imported and used throughout `SpotDetailView`
- `.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))`
- No `.disabled` modifier — Share remains tappable even while a save/unsave network call is in flight (deliberate; the existing Save button uses `.disabled(isSaving)` but Share has no async work of its own)

## Toolbar

The heart icon (`heart` / `heart.fill`) in the top-right toolbar remains untouched. Save/unsave is still fully functional from there.

## Out of Scope

- qwip deep links (not supported yet)
- Per-spot share previews / custom `Transferable` types
- Share from map card / saved spots list
