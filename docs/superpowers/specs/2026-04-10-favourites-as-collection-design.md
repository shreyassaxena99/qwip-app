# Design: Favourite Spots as a System Collection

**Date:** 2026-04-10
**Status:** Approved — awaiting backend implementation

## Background

Previously, "Favourite Spots" was a client-side concept only: saved spots with no collection membership (`collectionIds.isEmpty`) were displayed as favourites. This imposed a mutual exclusion — a spot could not be in Favourites and a custom collection simultaneously.

This design removes that constraint by making Favourite Spots a real, system-managed collection. Every user gets one automatically. Collections are now purely additive on top of Favourites.

## Mental Model

- **Saving a spot** = adding it to Favourite Spots
- **Adding to a collection** = also putting it somewhere more specific (Favourites membership unchanged)
- **Swipe-delete in Favourites** = fully unsave (removed from Favourites and all other collections)
- **Swipe-delete in another collection** = removed from that collection only; spot stays in Favourites

Matches the Google Maps / Apple Maps pattern.

## Behaviour Rules

- Every user has exactly one default collection (`is_default = true`), named "Favourite Spots"
- The default collection is non-deletable and non-renameable (enforced at API level)
- The default collection is excluded from the SaveToCollectionSheet — Favourites membership is controlled by the heart button only
- If a user swipes-delete from Favourites and the spot is in other collections, show a confirmation dialog: *"This will remove it from Favourite Spots and any collections it's in."*
- If the spot is only in Favourites (no custom collections), swipe straight through with no dialog

---

## 1. Database

### Schema change

```sql
ALTER TABLE collections
  ADD COLUMN is_default BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE collections
  ADD CONSTRAINT one_default_per_user
  UNIQUE (user_id, is_default) WHERE (is_default = TRUE);
```

### Signup trigger update

The trigger that inserts into `profiles` on new user creation also creates the default collection:

```sql
INSERT INTO collections (user_id, name, is_default)
VALUES (NEW.id, 'Favourite Spots', TRUE);
```

### One-time migration for existing users

1. For each existing user, insert a default collection row into `collections`
2. For each row in `saved_spots` for that user, insert a corresponding row into `collection_spots` pointing to the new default collection

`saved_spots` table is kept intact during this migration — not dropped yet.

---

## 2. Backend API Changes

### Endpoints that change

| Endpoint | Change |
|---|---|
| `GET /me/collections` | Includes the default collection (`is_default: true`). Default collection always returned first. |
| `POST /me/saved-spots` | Also inserts a `collection_spots` row for the default collection (idempotent — no-op if already present). |
| `DELETE /me/saved-spots/{spotId}` | Cascades: deletes from `saved_spots` AND all `collection_spots` rows for this spot. |
| `PATCH /me/collections/{id}` | Returns HTTP 400 if the target collection has `is_default = true`. |
| `DELETE /me/collections/{id}` | Returns HTTP 400 if the target collection has `is_default = true`. |

### Endpoints with no changes

- `POST /me/collections` — cannot create a collection with `is_default = true` (column defaults to false, not settable via API)
- `POST /me/collections/{id}/spots` — unchanged; adds to a custom collection (Favourites membership unaffected)
- `DELETE /me/collections/{id}/spots/{spotId}` — unchanged; removes from custom collection only, spot stays saved

### `SavedSpotEntry.collectionIds` response field

Continues to exclude the default collection. Membership in Favourites is implied by the spot appearing in saved entries at all. This keeps the iOS `SaveToCollectionSheet` logic simple.

---

## 3. iOS Changes

### `Collection` model
Add `isDefault: Bool` decoded from `is_default`.

### `CollectionsView`
- Remove hardcoded "Favourite Spots" row
- Find the default collection from `collectionService.collections` where `isDefault == true` and pin it first
- `favouriteCount` comes from `defaultCollection.spotCount` instead of counting `collectionIds.isEmpty`

### `CollectionSource` enum
Remove the `.favourites` case entirely. Everything becomes `.collection(Collection)`. Views check `collection.isDefault` for special behaviour.

### `CollectionDetailView`
- The `.favourites` branch in `displayEntries`, `loadEntries`, and `removeButton` collapses into the `.collection` branch
- Special behaviour for `isDefault` collections:
  - No edit or share toolbar buttons
  - Swipe-delete calls `savedSpotService.unsave` (not `collectionService.removeSpot`)
  - Show confirmation dialog if `entry.collectionIds` is non-empty

### `SaveToCollectionSheet`
Filter out `isDefault == true` collections from the displayed list. No other changes.

### `SavedSpotService`
No logic changes. `savedEntries` and `isSaved` continue to work identically.

---

## Implementation Order

1. **DB migration** — add `is_default` column, update signup trigger, backfill existing users
2. **Backend API** — enforce 400s on default collection, update cascade behaviour on unsave, return `is_default` in collections response
3. **iOS** — implement against updated API (separate implementation plan to be written)

---

## Migration Strategy for Existing Beta Users

### What the migration must do

For each existing user:
1. Insert one row into `collections` with `is_default = TRUE, name = 'Favourite Spots'`
2. For every row in `saved_spots` for that user, insert a corresponding row into `collection_spots` linking the spot to the new default collection

The backfill must cover **all** saved spots — not just those without custom collections. Under the new model, every saved spot belongs to Favourites regardless of custom collection membership.

### Risk: old iOS app + new backend

This is a breaking change for the iOS client. After the backend migration:

- `GET /me/collections` returns the default collection. The old iOS app renders it as a regular collection — with swipe-to-delete and edit actions visible. The backend returns HTTP 400 for those attempts, which surfaces as a generic error alert. Annoying but not data-destroying.
- `DELETE /me/saved-spots/{spotId}` now cascades through all `collection_spots`. The old app already calls this for unsaving, so behaviour is consistent — no regression.

### Recommended approach: coordinated release

Since the app is in beta:
1. Notify testers ahead of time to expect a required update
2. Deploy backend migration + new iOS build simultaneously (or iOS first, then backend within minutes)
3. The new iOS app handles `is_default` correctly from day one — no degraded state

Avoid deploying the backend migration without the iOS update live, as the window where old clients hit the new API is the only real risk period.

### Migration SQL

Run all steps in one transaction in the Supabase SQL editor.

> **Before running:** verify that your `collection_spots` table uses `collection_id` and `spot_id` as column names — these are inferred from the API layer and may differ slightly.

```sql
BEGIN;

-- ── Step 1: Add is_default column ────────────────────────────────────────────
ALTER TABLE collections
  ADD COLUMN is_default BOOLEAN NOT NULL DEFAULT FALSE;

-- ── Step 2: Partial unique index (one default collection per user) ────────────
-- Postgres partial unique constraints require CREATE UNIQUE INDEX, not
-- ALTER TABLE ADD CONSTRAINT ... UNIQUE WHERE
CREATE UNIQUE INDEX one_default_per_user
  ON collections (user_id)
  WHERE is_default = TRUE;

-- ── Step 3: Create default collection for every existing user ─────────────────
INSERT INTO collections (user_id, name, is_default, is_shareable, spot_count)
SELECT id, 'Favourite Spots', TRUE, FALSE, 0
FROM profiles;

-- ── Step 4: Backfill collection_spots ────────────────────────────────────────
-- Every saved spot goes into the user's new default collection.
-- Covers all saved spots regardless of whether they're in custom collections.
INSERT INTO collection_spots (collection_id, spot_id)
SELECT c.id, ss.spot_id
FROM collections c
JOIN saved_spots ss ON ss.user_id = c.user_id
WHERE c.is_default = TRUE
ON CONFLICT DO NOTHING;

-- ── Step 5: Correct spot_count on default collections ────────────────────────
UPDATE collections c
SET spot_count = (
  SELECT COUNT(*)
  FROM collection_spots cs
  WHERE cs.collection_id = c.id
)
WHERE c.is_default = TRUE;

COMMIT;
```

### Updated signup trigger

Replace the existing `handle_new_user` function so new users automatically get a default collection at signup:

```sql
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'User')
  );

  INSERT INTO public.collections (user_id, name, is_default, is_shareable, spot_count)
  VALUES (NEW.id, 'Favourite Spots', TRUE, FALSE, 0);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

The trigger itself (`on_auth_user_created`) does not need to change — only the function body.
