import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/app_database.dart';

/// Sync service for search history.
/// Pushes immediately after each search, pulls on app resume.
class SyncService {
  final UserDatabase _db;
  final SupabaseClient _supabase;

  SyncService({required UserDatabase db, required SupabaseClient supabase})
      : _db = db,
        _supabase = supabase;

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Push the most recent unsynced row immediately (fire-and-forget after search).
  Future<void> pushLatestSearch() async {
    if (_userId == null) return;
    try {
      final rows = await (_db.select(_db.searchHistory)
            ..where((t) => t.synced.equals(0))
            ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
            ..limit(1))
          .get();
      if (rows.isEmpty || rows.first.uuid.isEmpty) return;

      final row = rows.first;
      await _supabase.from('search_history').upsert({
        'id': row.uuid,
        'user_id': _userId,
        'query': row.query,
        'entry_id': row.entryId,
        'headword': row.headword,
        'searched_at': row.searchedAt,
      });

      await (_db.update(_db.searchHistory)..where((t) => t.id.equals(row.id)))
          .write(const SearchHistoryCompanion(synced: Value(1)));
    } catch (e) {
      debugPrint('Push search failed (will retry): $e');
    }
  }

  /// Push all local rows with synced=0 to Supabase.
  /// Preserves original searched_at timestamps for correct cross-device ordering.
  Future<int> pushAllUnsynced() async {
    if (_userId == null) return 0;

    final unsynced = await (_db.select(_db.searchHistory)
          ..where((t) => t.synced.equals(0))
          ..orderBy([(t) => OrderingTerm.asc(t.searchedAt)]))
        .get();

    if (unsynced.isEmpty) return 0;

    var pushed = 0;
    for (final row in unsynced) {
      if (row.uuid.isEmpty) continue;
      try {
        await _supabase.from('search_history').upsert({
          'id': row.uuid,
          'user_id': _userId,
          'query': row.query,
          'entry_id': row.entryId,
          'headword': row.headword,
          'searched_at': row.searchedAt,
        });

        // Mark as synced
        await (_db.update(_db.searchHistory)..where((t) => t.id.equals(row.id)))
            .write(const SearchHistoryCompanion(synced: Value(1)));
        pushed++;
      } catch (e) {
        // Skip failed rows, retry next sync cycle
        continue;
      }
    }
    return pushed;
  }

  /// Pull remote changes newer than last sync timestamp.
  Future<int> pullSearchHistory() async {
    if (_userId == null) return 0;

    final lastSyncAt = await _getLastSyncAt('search_history');

    var filter = _supabase
        .from('search_history')
        .select()
        .eq('user_id', _userId!);

    if (lastSyncAt != null) {
      filter = filter.gt('searched_at', lastSyncAt);
    }

    final rows = await filter.order('searched_at', ascending: false);
    if (rows.isEmpty) return 0;

    var pulled = 0;
    for (final row in rows) {
      // Check if we already have this record locally (by uuid)
      final uuid = row['id'] as String;
      final existing = await _db.customSelect(
        'SELECT id FROM search_history WHERE uuid = ?',
        variables: [Variable.withString(uuid)],
        readsFrom: {_db.searchHistory},
      ).get();

      if (existing.isEmpty) {
        await _db.into(_db.searchHistory).insert(
          SearchHistoryCompanion.insert(
            query: row['query'] as String,
            entryId: Value(row['entry_id'] as int?),
            headword: Value(row['headword'] as String?),
          ).copyWith(
            uuid: Value(uuid),
            searchedAt: Value(row['searched_at'] as String),
            synced: const Value(1), // came from remote, already synced
          ),
        );
        pulled++;
      }
    }

    // Update last sync timestamp
    if (rows.isNotEmpty) {
      await _setLastSyncAt('search_history', rows.first['searched_at'] as String);
    }

    return pulled;
  }

  /// Full sync: push unsynced local rows, then pull remote changes.
  Future<({int pushed, int pulled})> syncSearchHistory() async {
    final pushed = await pushAllUnsynced();
    final pulled = await pullSearchHistory();
    return (pushed: pushed, pulled: pulled);
  }

  Future<String?> _getLastSyncAt(String table) async {
    final rows = await _db.customSelect(
      'SELECT value FROM sync_meta WHERE key = ?',
      variables: [Variable.withString('${table}_last_sync_at')],
      readsFrom: {_db.syncMeta},
    ).get();
    return rows.isEmpty ? null : rows.first.data['value'] as String?;
  }

  Future<void> _setLastSyncAt(String table, String timestamp) async {
    await _db.into(_db.syncMeta).insertOnConflictUpdate(
      SyncMetaCompanion.insert(
        key: '${table}_last_sync_at',
        value: timestamp,
      ),
    );
  }
}
