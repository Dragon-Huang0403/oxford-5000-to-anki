import 'package:drift/drift.dart';
import 'app_database.dart';

/// Data access for search history
class SearchHistoryDao {
  final UserDatabase _db;

  SearchHistoryDao(this._db);

  /// Add a search to history
  Future<void> addSearch(String query, {int? entryId, String? headword}) async {
    await _db.into(_db.searchHistory).insert(
      SearchHistoryCompanion.insert(
        query: query,
        entryId: Value(entryId),
        headword: Value(headword),
      ),
    );

    // Keep only last 100 entries
    await _db.customStatement('''
      DELETE FROM search_history WHERE id NOT IN (
        SELECT id FROM search_history ORDER BY searched_at DESC LIMIT 100
      )
    ''');
  }

  /// Get recent searches (most recent first)
  Future<List<SearchHistoryData>> getRecent({int limit = 50}) async {
    final rows = await (_db.select(_db.searchHistory)
          ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
          ..limit(limit))
        .get();
    return rows;
  }

  /// Clear all search history
  Future<void> clearAll() async {
    await _db.delete(_db.searchHistory).go();
  }
}
