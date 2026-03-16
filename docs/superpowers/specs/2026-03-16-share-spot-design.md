# Share Spot — Design Spec

**Date:** 2026-03-16

## Summary

Replace the Save button in `SpotDetailView`'s actions row with a Share button. Save remains accessible via the existing heart icon in the navigation bar toolbar. Share uses SwiftUI's native `ShareLink` with a plain `String` payload.

## Scope

- `qwip/Views/SpotDetailView.swift` only — no new files or types.

## Actions Row Change

The `actionsRow` currently has two buttons: Save (left, glass style) and Directions (right, filled green). The Save button is replaced with a `ShareLink` styled identically to the old Save button (glass background, same padding, same font).

```
[ Share ]  [ Directions ]
```

## Share Content

A computed property `shareText: String` on `SpotDetailView` builds the payload:

```
<spot name>
<address>           ← omitted if displayAddress is nil
https://maps.google.com/?q=<latitude>,<longitude>
```

Example:
```
Workshop Coffee
Soho, London
https://maps.google.com/?q=51.5136,-0.1340
```

The Google Maps URL uses `detail.latitude` and `detail.longitude`.

## Share Button Appearance

Matches the existing Save button style:
- Icon: `square.and.arrow.up` (SF Symbols), size 22, semibold
- Label: "Share", dmSans 12 bold
- Background: `glassBackground(cornerRadius: 16)`
- No disabled state needed (share is always available)

## Toolbar

The heart icon (`heart` / `heart.fill`) in the top-right toolbar remains untouched. Save/unsave is still fully functional from there.

## Out of Scope

- qwip deep links (not supported yet)
- Per-spot share previews / custom `Transferable` types
- Share from map card / saved spots list
