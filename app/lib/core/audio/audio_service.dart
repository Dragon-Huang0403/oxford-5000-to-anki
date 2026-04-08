import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Local SQLite database for cached audio BLOBs.
/// Same schema as the server's audio_files table.
class AudioDb {
  late final GeneratedDatabase _db;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/audio.db');
    _db = _RawDb(NativeDatabase(file));
    await _db.customStatement('''
      CREATE TABLE IF NOT EXISTS audio_files (
        filename TEXT PRIMARY KEY,
        data BLOB NOT NULL
      )
    ''');
    _initialized = true;
  }

  Future<Uint8List?> get(String filename) async {
    await init();
    final rows = await _db.customSelect(
      'SELECT data FROM audio_files WHERE filename = ?',
      variables: [Variable.withString(filename)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data['data'] as Uint8List;
  }

  Future<void> put(String filename, Uint8List data) async {
    await init();
    await _db.customInsert(
      'INSERT OR REPLACE INTO audio_files (filename, data) VALUES (?, ?)',
      variables: [Variable.withString(filename), Variable.withBlob(data)],
    );
  }

  Future<({int fileCount, int sizeBytes})> stats() async {
    await init();
    final countRow = await _db.customSelect('SELECT COUNT(*) as c FROM audio_files').getSingle();
    final sizeRow = await _db.customSelect('SELECT COALESCE(SUM(LENGTH(data)), 0) as s FROM audio_files').getSingle();
    return (
      fileCount: countRow.data['c'] as int,
      sizeBytes: sizeRow.data['s'] as int,
    );
  }

  Future<void> clear() async {
    await init();
    await _db.customStatement('DELETE FROM audio_files');
    await _db.customStatement('VACUUM');
  }

  Future<void> close() async {
    if (_initialized) await _db.close();
  }
}

class _RawDb extends GeneratedDatabase {
  _RawDb(super.e);
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {});
}

/// Audio service: plays from local audio.db, fetches from API on cache miss.
class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final AudioDb audioDB = AudioDb();

  String apiBaseUrl = 'http://localhost:8000/api';

  AudioService();

  /// Play audio by filename. Checks local DB first, fetches from API if missing.
  Future<void> play(String filename) async {
    if (filename.isEmpty) return;

    try {
      // Check local audio.db
      var data = await audioDB.get(filename);

      if (data == null) {
        // Fetch from API, store in audio.db
        final response = await http.get(Uri.parse('$apiBaseUrl/audio/$filename'));
        if (response.statusCode == 200) {
          data = response.bodyBytes;
          await audioDB.put(filename, data);
        } else {
          debugPrint('AudioService: server returned ${response.statusCode} for $filename');
          return;
        }
      }

      // Write to temp file and play (just_audio needs a file path or URL)
      final dir = await getApplicationDocumentsDirectory();
      final tmpFile = File('${dir.path}/_audio_playback.mp3');
      await tmpFile.writeAsBytes(data);
      await _player.setFilePath(tmpFile.path);
      await _player.play();
    } catch (e) {
      debugPrint('AudioService: error $filename: $e');
    }
  }

  /// Play pronunciation for an entry.
  Future<void> playPronunciation(
    List<Map<String, dynamic>> pronunciations, {
    String dialect = 'us',
  }) async {
    if (pronunciations.isEmpty) return;
    final pron = pronunciations.where((p) => p['dialect'] == dialect).firstOrNull ??
        pronunciations.first;
    final audioFile = pron['audio_file'] as String? ?? '';
    if (audioFile.isNotEmpty) await play(audioFile);
  }

  /// Download ALL audio via batch tar endpoint, storing each file in audio.db.
  Future<void> downloadAll({
    required void Function(int downloaded, int total, int bytesDownloaded) onProgress,
  }) async {
    const batchSize = 5000;
    var offset = 0;
    var totalFiles = 0;
    var downloadedSoFar = 0;
    var bytesTotal = 0;

    while (true) {
      final url = '$apiBaseUrl/audio-batch?offset=$offset&limit=$batchSize';
      debugPrint('AudioService: batch offset=$offset');

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('Batch download failed: ${response.statusCode}');
      }

      // http package lowercases header names
      totalFiles = int.parse(response.headers['x-total-files'] ?? response.headers['X-Total-Files'] ?? '0');
      final batchCount = int.parse(response.headers['x-batch-count'] ?? response.headers['X-Batch-Count'] ?? '0');
      if (batchCount == 0) break;

      // Parse tar and store each file in audio.db
      final extracted = await _extractTarToDb(response.bodyBytes);
      downloadedSoFar += extracted;
      bytesTotal += response.bodyBytes.length;

      onProgress(downloadedSoFar, totalFiles, bytesTotal);

      offset += batchSize;
      if (batchCount < batchSize) break;
    }
  }

  /// Parse tar archive and insert each file into audio.db.
  Future<int> _extractTarToDb(Uint8List tarBytes) async {
    var count = 0;
    var pos = 0;

    while (pos + 512 <= tarBytes.length) {
      final header = tarBytes.sublist(pos, pos + 512);
      if (header.every((b) => b == 0)) break;

      final nameBytes = header.sublist(0, 100);
      var nameEnd = nameBytes.indexOf(0);
      if (nameEnd == -1) nameEnd = 100;
      final filename = String.fromCharCodes(nameBytes.sublist(0, nameEnd)).trim();

      final rawSizeBytes = header.sublist(124, 136);
      final sizeStr = String.fromCharCodes(rawSizeBytes).replaceAll(RegExp(r'[\x00 ]'), '');
      final fileSize = sizeStr.isNotEmpty ? int.tryParse(sizeStr, radix: 8) ?? 0 : 0;

      pos += 512;

      if (filename.isNotEmpty && fileSize > 0 && pos + fileSize <= tarBytes.length) {
        final data = Uint8List.sublistView(tarBytes, pos, pos + fileSize);
        await audioDB.put(filename, data);
        count++;
      }

      pos += (fileSize + 511) & ~511;
    }

    return count;
  }

  /// Cache stats from audio.db.
  Future<({int fileCount, int sizeBytes})> getCacheStats() => audioDB.stats();

  /// Clear all cached audio.
  Future<void> clearCache() => audioDB.clear();

  Future<void> stop() async => await _player.stop();

  void dispose() {
    _player.dispose();
    audioDB.close();
  }
}
