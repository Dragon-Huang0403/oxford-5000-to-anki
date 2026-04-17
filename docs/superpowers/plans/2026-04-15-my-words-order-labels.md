# My Words Order Labels Refactor

> **For agentic workers:** Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename FIFO/LIFO order labels to "Oldest"/"Newest" and make the word list display order follow the setting (Random keeps oldest-first display).

**Architecture:** String value rename across settings, DAO, providers, and UI. Backwards-compatible: existing users with stored 'fifo'/'lifo' values are mapped to new names in the settings getter.

**Tech Stack:** Dart/Flutter, Drift, Riverpod

---

### Task 1: Rename order values in settings DAO

**Files:**
- Modify: `app/lib/core/database/settings_dao.dart:121-126`

- [ ] **Step 1: Update getMyWordsOrder with backwards-compatible mapping**

```dart
  // ── My Words settings ───────────────────────────────────────────────────

  /// My Words ordering: 'oldest' (default), 'newest', or 'random'
  Future<String> getMyWordsOrder() async {
    final raw = await get('my_words_order');
    // Backwards compat: map old values
    return switch (raw) {
      'fifo' => 'oldest',
      'lifo' => 'newest',
      _ => raw ?? 'oldest',
    };
  }
  Future<void> setMyWordsOrder(String order) => set('my_words_order', order);
```

- [ ] **Step 2: Verify no other references to 'fifo'/'lifo' in settings_dao.dart**

Run: `cd app && grep -n "fifo\|lifo" lib/core/database/settings_dao.dart`
Expected: no results after the edit

---

### Task 2: Update vocabulary_list_dao order switches

**Files:**
- Modify: `app/lib/core/database/vocabulary_list_dao.dart:130-149, 185-214`

- [ ] **Step 1: Update `getEntries()` order switch**

Change lines 135-138:
```dart
    final orderClause = switch (order) {
      'newest' => 'ORDER BY added_at DESC',
      'random' => 'ORDER BY RANDOM()',
      _ => 'ORDER BY added_at ASC', // oldest (default)
    };
```

- [ ] **Step 2: Update `getEntries()` default parameter**

Change line 133:
```dart
    String order = 'oldest',
```

- [ ] **Step 3: Update `getNewEntryIds()` order switch**

Change lines 191-194:
```dart
    final orderClause = switch (order) {
      'newest' => 'ORDER BY vle.added_at DESC',
      'random' => 'ORDER BY RANDOM()',
      _ => 'ORDER BY vle.added_at ASC', // oldest (default)
    };
```

- [ ] **Step 4: Update `getNewEntryIds()` default parameter**

Change line 189:
```dart
    String order = 'oldest',
```

- [ ] **Step 5: Make `watchEntries()` order-aware**

Replace the current hardcoded `watchEntries` (lines 152-168):
```dart
  /// Watch all active entries (for reactive UI).
  /// Display order follows setting: oldest = ASC, newest = DESC.
  /// Random keeps oldest-first display (randomness only in queue selection).
  Stream<List<VocabularyListEntry>> watchEntries(
    String listId, {
    String order = 'oldest',
  }) {
    final orderClause = switch (order) {
      'newest' => 'ORDER BY added_at DESC',
      _ => 'ORDER BY added_at ASC', // oldest + random both show oldest-first
    };
    return _db
        .customSelect(
          '''SELECT * FROM vocabulary_list_entries
             WHERE list_id = ? AND deleted_at IS NULL
             $orderClause''',
          variables: [Variable.withString(listId)],
          readsFrom: {_db.vocabularyListEntries},
        )
        .watch()
        .map(
          (rows) =>
              rows.map((r) => _db.vocabularyListEntries.map(r.data)).toList(),
        );
  }
```

---

### Task 3: Update providers to pass order to watchEntries

**Files:**
- Modify: `app/lib/features/review/providers/my_words_providers.dart`

- [ ] **Step 1: Update myWordsEntriesProvider to watch order and pass to watchEntries**

```dart
/// Reactive stream of all entries in the My Words list.
final myWordsEntriesProvider = StreamProvider<List<VocabularyListEntry>>((
  ref,
) async* {
  final list = await ref.watch(myWordsListProvider.future);
  final order = await ref.watch(myWordsOrderProvider.future);
  final dao = ref.read(vocabularyListDaoProvider);
  yield* dao.watchEntries(list.id, order: order);
});
```

- [ ] **Step 2: Update myWordsOrderProvider doc comment**

```dart
/// My Words ordering: 'oldest', 'newest', or 'random'.
```

---

### Task 4: Update UI chip labels

**Files:**
- Modify: `app/lib/features/review/presentation/my_words_screen.dart:187-197`

- [ ] **Step 1: Replace chip values and labels**

```dart
                  ...{
                    'oldest': 'Oldest',
                    'newest': 'Newest',
                    'random': 'Random',
                  }.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: order.value == e.key,
                        onSelected: (_) =>
                            ref.read(myWordsOrderProvider.notifier).setOrder(e.key),
                      ),
                    ),
                  ),
```

---

### Task 5: Update review_session.dart default parameter

**Files:**
- Modify: `app/lib/features/review/domain/review_session.dart:151`

- [ ] **Step 1: Update default value**

Change line 151:
```dart
    String myWordsOrder = 'oldest',
```

---

### Task 6: Update spec to match implementation

**Files:**
- Modify: `docs/superpowers/specs/2026-04-15-my-words-design.md`

Already done in this conversation.

---

### Task 7: Verify and commit

- [ ] **Step 1: Run analyzer**

```bash
cd app && flutter analyze --fatal-warnings
```
Expected: No issues

- [ ] **Step 2: Search for any remaining 'fifo'/'lifo' references**

```bash
cd app && grep -rn "'fifo'\|'lifo'" lib/
```
Expected: No results

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "refactor: rename My Words order from FIFO/LIFO to Oldest/Newest"
```
