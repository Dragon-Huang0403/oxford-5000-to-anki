# My Words — Custom Word List Feature

## Summary

A single "My Words" list that lets users curate words for review alongside the existing CEFR/Oxford filter system. Words added to My Words are treated as priority — they're drawn first when building the review queue, with remaining slots filled by the filter.

## Data Model

### Schema changes (migration v7)

**`vocabulary_lists`** — reshape existing unused table:

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | PK |
| name | TEXT | "My Words" |
| description | TEXT | Default '' |
| created_at | TEXT | ISO8601 |
| updated_at | TEXT | ISO8601 |
| deleted_at | TEXT? | Soft delete |
| synced | INTEGER | 0/1 |

Dropped from current schema: `is_preset`, `preset_type`.

**`vocabulary_list_entries`** — reshape existing unused table:

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT (UUID) | PK |
| list_id | TEXT | FK to vocabulary_lists |
| entry_id | INTEGER | FK to dictionary entries |
| headword | TEXT | Denormalized |
| pos | TEXT | Part of speech (new) |
| added_at | TEXT | For FIFO/LIFO ordering |
| updated_at | TEXT | Sync tracking (new) |
| deleted_at | TEXT? | Soft delete (new) |
| synced | INTEGER | 0/1 (new) |

**Settings key:** `my_words_order` — `"oldest"` / `"newest"` / `"random"` (default: `"oldest"`)

**Auto-creation:** Single "My Words" list created lazily on first access.

### Supabase migration

New remote tables `vocabulary_lists` and `vocabulary_list_entries` mirroring local schema. RLS policies matching existing `review_cards`/`search_history` pattern.

## Queue Integration

### New card selection (replaces current single-source flow)

**My Words first, filter fills remaining:**

```
budget = newCardsPerDay - countNewLearnedToday()

myWordsIds = getNewEntryIdsFromMyWords(limit: budget)  // ordered by oldest/newest/random
remaining  = budget - myWordsIds.length
filterIds  = getNewEntryIds(filter, limit: remaining, excludeIds: myWordsIds)

newCardIds = myWordsIds + filterIds
```

### Dedup rule

My Words takes precedence. A word in both My Words and the filter range is drawn from the My Words source. The filter source excludes any entryIds already claimed by My Words.

**Rationale:** My Words = explicit user intent. If a user added a word, they want it prioritized regardless of whether it also matches a filter.

### Due cards

Unchanged. Once a review card exists, it's just a due card — source doesn't matter.

### Backwards compatibility

If My Words is empty, 100% of budget goes to filter. Identical to current behavior.

## My Words Screen

Accessible from ReviewHomeScreen (button alongside "Learned Words" / "Study Words").

### Layout

1. **App bar:** "My Words" + word count
2. **Search bar:** "Search to add words..." — uses existing dictionary search, results show with "+ Add" button
3. **Order selector:** 3 chips (Oldest / Newest / Random), persisted to settings
4. **Import banner:** "Import from search history" — opens bottom sheet:
   - Recent unique searches (from `SearchHistoryDao.getRecentUnique()`)
   - Checkboxes for individual selection + "Select all" toggle
   - "Add selected" button
   - Only shows entries with non-null `entryId`
5. **Word list:** Scrollable entries showing headword, pos, CEFR badge
   - Display order follows the order setting: Oldest = `added_at` ASC, Newest = `added_at` DESC. Random keeps oldest-first display (randomness only affects queue selection, not list display).
   - Tap x to remove (removes from list AND deletes review card if one exists)

## Entry Points for Adding Words

### 1. Dictionary entry header

"+ My Words" button next to CEFR/Oxford badges. Toggles to checkmark "In My Words" when already added. Tap when added removes the word (same behavior as My Words screen removal).

### 2. Search history (long-press)

Long-press a history item with non-null `entryId` shows context menu with "Add to My Words".

### 3. My Words screen search

Inline dictionary search with "+ Add" button on results.

## Removal Behavior

Remove from list **and** delete the review card if one exists (soft-delete both). No dialog — single action. Deletes the card regardless of whether it originated from My Words or filter.

If the word also exists in the filter range, it may reappear as a new card from the filter source in the future. This is acceptable — the user can narrow their filter if unwanted.

## DAO: VocabularyListDao

```
getOrCreateMyWordsList() → VocabularyList
addEntry(listId, entryId, headword, pos) → void
removeEntry(id) → void  // soft-deletes entry + review card
getEntries(listId, {order}) → List<VocabularyListEntry>
getNewEntryIds(listId, {limit, excludeIds}) → List<int>
containsEntry(listId, entryId) → bool
countEntries(listId) → int
watchEntries(listId) → Stream<List<VocabularyListEntry>>
```

## Riverpod Providers

- `myWordsListProvider` — the single list ID (cached, auto-creates on first access)
- `myWordsEntriesProvider` — reactive list of entries
- `myWordsContainsProvider(entryId)` — quick lookup for add/added state
- `myWordsCountProvider` — for badge display
- `myWordsOrderProvider` — current ordering setting

## Sync

Same pattern as all other tables:
- Push: on insert/update/remove, set `synced = 0`, fire-and-forget to Supabase
- Pull: on app resume, pull since last timestamp, upsert locally, last-write-wins by `updated_at`
- Add both tables to existing `TableSync` mapping

## Out of Scope

- Multiple lists (schema supports it, UI is single list only)
- Sharing/export/import lists between users
- Converting filters into VocabularyList rows
- Manual drag-to-reorder (order is global FIFO/LIFO/random setting)
- SyncQueue table cleanup (separate task)

## Key Files to Modify

- `app/lib/core/database/user_tables.dart` — reshape VocabularyLists/VocabularyListEntries
- `app/lib/core/database/app_database.dart` — migration v7
- `app/lib/core/database/app_database.g.dart` — regenerate
- New: `app/lib/core/database/vocabulary_list_dao.dart`
- `app/lib/features/review/domain/review_session.dart` — queue integration
- `app/lib/features/review/providers/review_providers.dart` — new providers
- New: `app/lib/features/review/presentation/my_words_screen.dart`
- `app/lib/features/review/presentation/review_home_screen.dart` — add My Words button
- `app/lib/features/dictionary/presentation/widgets/entry_card.dart` — add "+ My Words" button
- `app/lib/features/dictionary/presentation/widgets/search_history_list.dart` — long-press to add
- `supabase/migrations/` — new migration for remote tables
- `app/lib/core/sync/table_sync.dart` — register new tables
