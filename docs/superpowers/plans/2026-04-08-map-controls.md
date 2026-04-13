# Map Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a liquid glass controls panel (location, 3D view, compass) to the top-right of MapView, below the filter bar.

**Architecture:** All three controls are custom SwiftUI buttons inside a single `GlassEffectContainer` panel, overlaid in MapView's existing ZStack at `(top: 54, trailing: 11)`. Two new `@State` vars track 3D mode and map heading; a third tracks the current `MapCamera` for pitch/heading operations. The compass animates in/out based on heading.

**Tech Stack:** SwiftUI, MapKit (`MapCamera`, `MapCameraPosition`, `MKCoordinateRegion`), iOS 26 Liquid Glass (`GlassEffectContainer`, `.glassEffect`), SF Symbols (`safari` for compass), custom SVG imagesets (Lucide navigation + box)

---

### File Map

| File | Action | Responsibility |
|---|---|---|
| `qwip/Assets.xcassets/ic_navigation.imageset/` | Create | Lucide navigation SVG asset |
| `qwip/Assets.xcassets/ic_box.imageset/` | Create | Lucide box SVG asset |
| `qwip/Views/MapView.swift` | Modify | State vars, camera tracking, helper functions, overlay view, map style toggle |

---

### Task 1: Add Lucide SVG assets to the asset catalog

**Files:**
- Create: `qwip/Assets.xcassets/ic_navigation.imageset/ic_navigation.svg`
- Create: `qwip/Assets.xcassets/ic_navigation.imageset/Contents.json`
- Create: `qwip/Assets.xcassets/ic_box.imageset/ic_box.svg`
- Create: `qwip/Assets.xcassets/ic_box.imageset/Contents.json`

- [ ] **Step 1: Create the navigation SVG**

Create `qwip/Assets.xcassets/ic_navigation.imageset/ic_navigation.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <polygon points="3 11 22 2 13 21 11 13 3 11"/>
</svg>
```

- [ ] **Step 2: Create the navigation imageset Contents.json**

Create `qwip/Assets.xcassets/ic_navigation.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "ic_navigation.svg",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

- [ ] **Step 3: Create the box SVG**

Create `qwip/Assets.xcassets/ic_box.imageset/ic_box.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/>
  <polyline points="3.27 6.96 12 12.01 20.73 6.96"/>
  <line x1="12" y1="22.08" x2="12" y2="12"/>
</svg>
```

- [ ] **Step 4: Create the box imageset Contents.json**

Create `qwip/Assets.xcassets/ic_box.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "ic_box.svg",
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add qwip/Assets.xcassets/ic_navigation.imageset/ qwip/Assets.xcassets/ic_box.imageset/
git commit -m "feat: add Lucide navigation and box SVG assets"
```

---

### Task 2: Add state vars and update camera tracking

**Files:**
- Modify: `qwip/Views/MapView.swift`

- [ ] **Step 1: Add three new `@State` properties to `MapView`**

After `@State private var showFilters = false` (line ~28), add:

```swift
@State private var is3DEnabled: Bool = false
@State private var mapHeading: Double = 0
@State private var currentCamera: MapCamera? = nil
```

- [ ] **Step 2: Update the existing `.onMapCameraChange(frequency: .onEnd)` to capture `currentCamera`**

In `mapLayer`, add `currentCamera = context.camera` as the first line of the existing `.onEnd` closure:

```swift
.onMapCameraChange(frequency: .onEnd) { context in
    currentCamera = context.camera
    mapSpan = context.region.span
    // Clear selected spot if it's now merged into a cluster
    if let selected = selectedSpot {
        let visible = clusters.contains { $0.spots.count <= 2 && $0.spots.contains { $0.id == selected.id } }
        if !visible { withAnimation { selectedSpot = nil } }
    }
}
```

- [ ] **Step 3: Add a `.continuous` camera change handler for real-time heading updates**

Directly after the `.onMapCameraChange(frequency: .onEnd)` block in `mapLayer`, add:

```swift
.onMapCameraChange(frequency: .continuous) { context in
    mapHeading = context.camera.heading
}
```

- [ ] **Step 4: Commit**

```bash
git add qwip/Views/MapView.swift
git commit -m "feat: track map heading and current camera for controls overlay"
```

---

### Task 3: Add control action helper functions

**Files:**
- Modify: `qwip/Views/MapView.swift` (`// MARK: - Helpers` section)

- [ ] **Step 1: Add `snapToUserLocation()` in `// MARK: - Helpers`**

```swift
private func snapToUserLocation() {
    guard let location = locationService.userLocation else { return }
    withAnimation(.easeInOut(duration: 0.8)) {
        position = .region(MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 500,
            longitudinalMeters: 500
        ))
    }
}
```

- [ ] **Step 2: Add `toggle3D()` in `// MARK: - Helpers`**

```swift
private func toggle3D() {
    is3DEnabled.toggle()
    guard let cam = currentCamera else { return }
    withAnimation(.easeInOut(duration: 0.6)) {
        position = .camera(MapCamera(
            centerCoordinate: cam.centerCoordinate,
            distance: cam.distance,
            heading: cam.heading,
            pitch: is3DEnabled ? 45 : 0
        ))
    }
}
```

- [ ] **Step 3: Add `resetNorth()` in `// MARK: - Helpers`**

```swift
private func resetNorth() {
    guard let cam = currentCamera else { return }
    withAnimation(.easeInOut(duration: 0.5)) {
        position = .camera(MapCamera(
            centerCoordinate: cam.centerCoordinate,
            distance: cam.distance,
            heading: 0,
            pitch: cam.pitch
        ))
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add qwip/Views/MapView.swift
git commit -m "feat: add snapToUserLocation, toggle3D, and resetNorth helpers"
```

---

### Task 4: Build the controls overlay and wire into ZStack

**Files:**
- Modify: `qwip/Views/MapView.swift`

- [ ] **Step 1: Add `mapControlsOverlay` computed var**

Add after the `filterBarOverlay` computed var (after `// MARK: - Filter Bar`), before `// MARK: - Selected Spot Preview`:

```swift
// MARK: - Map Controls

private var mapControlsOverlay: some View {
    VStack {
        HStack {
            Spacer()
            GlassEffectContainer(spacing: 0) {
                VStack(spacing: 0) {
                    // Location button
                    Button(action: snapToUserLocation) {
                        Image("ic_navigation")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 17, height: 17)
                            .foregroundStyle(Color.primary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 22, height: 1)

                    // 3D toggle button
                    Button(action: toggle3D) {
                        Image("ic_box")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 17, height: 17)
                            .foregroundStyle(is3DEnabled ? Color.brandSecondary : Color.primary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(is3DEnabled ? Color.brandPrimary : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: is3DEnabled)

                    // Compass — only visible when map is rotated from north
                    if abs(mapHeading) > 0.5 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 22, height: 1)
                            .transition(.opacity)

                        Button(action: resetNorth) {
                            Image(systemName: "safari")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(Color.primary)
                                .rotationEffect(.degrees(-mapHeading))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .padding(5)
            }
            .glassEffect(in: .roundedRectangle(cornerRadius: 16))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: abs(mapHeading) > 0.5)
            .padding(.trailing, 11)
        }
        Spacer()
    }
    .padding(.top, 54)
}
```

- [ ] **Step 2: Add `mapControlsOverlay` to the ZStack in `body`**

Update the `ZStack` in `var body` to include `mapControlsOverlay` after `filterBarOverlay`:

```swift
ZStack(alignment: .top) {
    mapLayer
    filterBarOverlay
    mapControlsOverlay
    selectedSpotPreview
    if store.isLoading && store.spots.isEmpty {
        loadingOverlay
    }
}
```

- [ ] **Step 3: Update `.mapStyle` in `mapLayer` to react to `is3DEnabled`**

Replace:

```swift
.mapStyle(.standard(
    elevation: .flat,
    emphasis: .muted,
    pointsOfInterest: .excludingAll,
    showsTraffic: false
))
```

With:

```swift
.mapStyle(.standard(
    elevation: is3DEnabled ? .realistic : .flat,
    emphasis: .muted,
    pointsOfInterest: .excludingAll,
    showsTraffic: false
))
```

- [ ] **Step 4: Build in Xcode (Cmd+B) — confirm no compiler errors**

- [ ] **Step 5: Manual smoke test on simulator**

Set simulator location via **Features > Location > Custom Location** (use `51.5220, -0.0950` for central London).

Verify:
1. Controls panel appears top-right, below filter bar, with liquid glass background
2. **Location button**: tap → camera animates to current location at ~500m zoom
3. **3D button**: tap → button fills `brandPrimary` green, map tilts to 45° pitch and switches to realistic elevation; tap again → button clears, map returns flat
4. **Compass**: rotate map with two-finger rotate gesture → compass appears with animated slide-in; `safari` needle rotates to reflect heading; tap → map snaps back to north, compass hides

- [ ] **Step 6: Commit**

```bash
git add qwip/Views/MapView.swift
git commit -m "feat: add liquid glass map controls overlay (location, 3D, compass)"
```
