import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/database/app_database.dart';
import 'package:deckionary/features/dictionary/domain/search_service.dart';
import 'package:deckionary/features/dictionary/providers/search_provider.dart';

import '../../../test_helpers.dart';

void main() {
  late DictionaryDatabase db;

  setUpAll(() {
    db = createTestDictDb();
  });

  tearDownAll(() async {
    await db.close();
  });

  // ── 1. lookupWord (exact match) ─────────────────────────────────────────

  group('lookupWord', () {
    test('returns entries for a real word', () async {
      final results = await db.lookupWord('hello');
      expect(results, isNotEmpty);
      expect(results.first['headword'], 'hello');
    });

    test('is case-insensitive', () async {
      final lower = await db.lookupWord('hello');
      final upper = await db.lookupWord('Hello');
      final mixed = await db.lookupWord('HELLO');

      expect(lower, isNotEmpty);
      expect(upper.length, lower.length);
      expect(mixed.length, lower.length);
    });

    test('returns empty for unknown word', () async {
      final results = await db.lookupWord('xyzzyplugh');
      expect(results, isEmpty);
    });
  });

  // ── 2. lookupVariant (variant spelling) ─────────────────────────────────

  group('lookupVariant', () {
    test('"organise" finds "organize" via variant table', () async {
      final results = await db.lookupVariant('organise');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['headword'] as String) == 'organize'),
        isTrue,
        reason: 'Should resolve variant "organise" to headword "organize"',
      );
    });

    test('returns empty for word not in variant table', () async {
      final results = await db.lookupVariant('xyzzyplugh');
      expect(results, isEmpty);
    });
  });

  // ── 3. fuzzyLookup (suffix stripping) ───────────────────────────────────

  group('fuzzyLookup', () {
    test('"tables" finds "table" via -s strip', () async {
      final results = await db.fuzzyLookup('tables');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['headword'] as String) == 'table'),
        isTrue,
      );
    });

    test('"carries" finds "carry" via -ies -> -y', () async {
      final results = await db.fuzzyLookup('carries');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['headword'] as String) == 'carry'),
        isTrue,
      );
    });

    test('"danced" finds "dance" via -ed -> -e', () async {
      final results = await db.fuzzyLookup('danced');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['headword'] as String) == 'dance'),
        isTrue,
      );
    });

    test('returns exact match if word is itself a headword', () async {
      // "running" is its own headword in OALD
      final results = await db.fuzzyLookup('running');
      expect(results, isNotEmpty);
      expect(results.first['headword'], 'running');
    });
  });

  // ── 4. searchPrefix ─────────────────────────────────────────────────────

  group('searchPrefix', () {
    test('"hel" returns entries starting with "hel"', () async {
      final results = await db.searchPrefix('hel', limit: 15);
      expect(results, isNotEmpty);
      for (final r in results) {
        expect(
          (r['headword'] as String).toLowerCase().startsWith('hel'),
          isTrue,
        );
      }
      // Should include common words like "hello", "help"
      final headwords = results.map((r) => r['headword'] as String).toSet();
      expect(headwords, contains('hello'));
      expect(headwords, contains('help'));
    });

    test('empty query returns empty', () async {
      final results = await db.searchPrefix('', limit: 15);
      expect(results, isEmpty);
    });

    test('deduplicates headwords', () async {
      final results = await db.searchPrefix('run', limit: 15);
      final headwords = results.map((r) => r['headword'] as String).toList();
      // Each headword should appear only once (deduplication)
      expect(headwords.toSet().length, headwords.length);
    });
  });

  // ── 5. fuzzySearch (Levenshtein) ────────────────────────────────────────

  group('fuzzySearch', () {
    test('"helo" (typo) finds "hello" within distance 1', () async {
      final results = await db.fuzzySearch('helo', limit: 10, maxDistance: 2);
      expect(results, isNotEmpty);
      expect(
        results.any((r) => (r['headword'] as String) == 'hello'),
        isTrue,
        reason: '"helo" should match "hello" via Levenshtein',
      );
    });

    test('query shorter than 3 chars returns empty', () async {
      final results = await db.fuzzySearch('he', limit: 10, maxDistance: 2);
      expect(results, isEmpty);
    });
  });

  // ── 6. searchDefinitions (FTS) ──────────────────────────────────────────

  group('searchDefinitions', () {
    test('"greeting" returns results with matching definitions', () async {
      final results = await db.searchDefinitions('greeting', limit: 15);
      expect(results, isNotEmpty);
      // "hello" should appear since its definition involves greeting
      final headwords = results.map((r) => r['headword'] as String).toSet();
      expect(
        headwords.contains('hello') || headwords.contains('hi'),
        isTrue,
        reason:
            'FTS for "greeting" should find words defined with "greeting"',
      );
    });

    test('empty query returns empty', () async {
      final results = await db.searchDefinitions('', limit: 15);
      expect(results, isEmpty);
    });
  });

  // ── 7. searchEntries (full pipeline) ────────────────────────────────────

  group('searchEntries', () {
    test('exact word "hello" returns headword-match results', () async {
      final results = await searchEntries(db, 'hello');
      expect(results, isNotEmpty);
      // First result should be an exact headword match
      expect(results.first.entry.headword, 'hello');
      expect(results.first.source, SearchMatchSource.headword);
    });

    test('typo "helo" returns results via fuzzy fallback', () async {
      final results = await searchEntries(db, 'helo');
      expect(results, isNotEmpty);
      // Should find "hello" through one of the fallback stages
      expect(
        results.any((r) => r.entry.headword == 'hello'),
        isTrue,
        reason: '"helo" should resolve to "hello" via fuzzy pipeline',
      );
    });

    test('empty query returns empty', () async {
      final results = await searchEntries(db, '');
      expect(results, isEmpty);
    });

    test('definition search appends FTS results', () async {
      // "animal" is a real word AND appears in many definitions.
      // The pipeline should return an exact headword match first,
      // then FTS matches for entries whose definitions mention "animal".
      final results = await searchEntries(db, 'animal');
      expect(results, isNotEmpty);
      // First result: exact headword match
      expect(results.first.entry.headword, 'animal');
      expect(results.first.source, SearchMatchSource.headword);
      // Should also have FTS results appended (definitions containing "animal")
      final ftsResults = results.where(
        (r) => r.source != SearchMatchSource.headword,
      );
      expect(ftsResults, isNotEmpty,
          reason: 'Should append FTS results for definition matches');
    });

    test('variant spelling resolves via pipeline', () async {
      // "organise" is not a headword, but is a variant of "organize"
      final results = await searchEntries(db, 'organise');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.entry.headword == 'organize'),
        isTrue,
        reason: 'Variant "organise" should resolve to "organize"',
      );
    });

    test('suffix-stripped word resolves correctly', () async {
      // "churches" is not a headword -> strip "es" -> "church"
      final results = await searchEntries(db, 'churches');
      expect(results, isNotEmpty);
      expect(
        results.any((r) => r.entry.headword == 'church'),
        isTrue,
        reason: '"churches" should resolve to "church" via suffix stripping',
      );
    });
  });
}
