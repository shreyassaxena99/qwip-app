# UI Spec — qwip iOS App

## Brand
- Primary: #1f3d32 (forest green)
- Secondary: #FDFBF7 (cream)
- Use primary for nav bars, tab bars, buttons, active states
- Use secondary/cream as the main background throughout

## Screens to build

### 1. Map View (Home Tab)
- Full-screen Apple MapKit map
- Floating pill-shaped filter bar at top: All | Cafe | Coworking | Gym | Hotel | Library
- Custom map pins in primary green with a small icon per category
- Bottom sheet (draggable) showing a horizontal scroll of SpotCards for visible spots
- Each SpotCard: name, category icon, distance, is_open_now badge, rating

### 2. Spot Detail View
- Presented as a sheet from SpotCard tap
- Hero photo area at top (placeholder grey if no photo)
- Name, category, open/closed badge, rating, distance
- Curated tags row: WiFi, Power, Noise level, Access type
- Google amenities: outdoor seating, dog friendly, etc (only show if true)
- Address, phone, website (tappable)
- Hours section (expandable)
- "Get Directions" button (opens Apple Maps deeplink)
- Save/unsave heart button top right

### 3. Saved Spots Tab
- List view of saved spots
- Same SpotCard style as map bottom sheet
- Empty state: "No saved spots yet. Explore the map to find your next work spot."

### 4. Profile Tab
- Display name
- Email opt-in toggle
- Delete account option (destructive)

## Navigation
- TabView with 3 tabs: Map (house or map icon), Saved (heart), Profile (person)
- Tab bar background: primary green, icons cream

## Mock Data
- Create a MockSpotService with 6-8 hardcoded spots around London
- Spots should cover different categories
- Some open, some closed
- Varying distances, ratings

## Notes
- No login/auth screens needed
- No real API calls — all mock data
- Use SwiftUI throughout, minimum iOS 17
- No SwiftData usage
```
