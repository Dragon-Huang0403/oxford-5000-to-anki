import 'dart:io';
import 'package:background_downloader/background_downloader.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;

import 'package:deckionary/core/audio/audio_download_manager.dart';
import 'package:deckionary/core/audio/audio_service.dart';
import 'package:deckionary/core/audio/download_dispatcher.dart';

import 'audio_service_test.dart'; // buildTar, buildManifest, createTestAudioDb

// ---------------------------------------------------------------------------
// Mock DownloadDispatcher (callback-based, matching real API)
// ---------------------------------------------------------------------------

class MockDownloadDispatcher implements DownloadDispatcher {
  final enqueuedTasks = <DownloadTask>[];
  final _activeTasks = <Task>[];
  int resetCount = 0;

  TaskStatusCallback? _statusCallback;

  @override
  Future<bool> enqueue(DownloadTask task) async {
    enqueuedTasks.add(task);
    _activeTasks.add(task);
    return true;
  }

  @override
  Future<int> reset(String group) async {
    resetCount++;
    _activeTasks.clear();
    return enqueuedTasks.length;
  }

  @override
  Future<List<Task>> allTasks(String group) async =>
      List.unmodifiable(_activeTasks);

  @override
  Future<void> configure({int maxConcurrent = 3}) async {}

  @override
  void configureGroupNotification({
    required String group,
    TaskNotification? running,
    TaskNotification? complete,
    TaskNotification? error,
    bool progressBar = false,
  }) {}

  @override
  void registerStatusCallback(String group, TaskStatusCallback callback) {
    _statusCallback = callback;
  }

  @override
  void unregisterCallbacks(String group) {
    _statusCallback = null;
  }

  /// Simulate a task completing: invoke registered callback.
  void completeTask(String filename) {
    final task = enqueuedTasks.firstWhere((t) => t.filename == filename);
    _activeTasks.remove(task);
    _statusCallback?.call(TaskStatusUpdate(task, TaskStatus.complete));
  }

  /// Simulate a task failing.
  void failTask(String filename) {
    final task = enqueuedTasks.firstWhere((t) => t.filename == filename);
    _activeTasks.remove(task);
    _statusCallback?.call(TaskStatusUpdate(task, TaskStatus.failed));
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Mock HTTP client that serves only the manifest.
http.Client manifestClient(List<String> packNames) {
  final manifest = buildManifest(packNames);
  return http_testing.MockClient((request) async {
    if (request.url.path.endsWith('manifest.json')) {
      return http.Response(manifest, 200);
    }
    return http.Response('Not found', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AudioDb db;
  late AudioService service;
  late MockDownloadDispatcher dispatcher;
  late AudioDownloadManager manager;
  late Directory tmpDir;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AudioDb.forTesting(NativeDatabase.memory());
    await db.init();
    service = AudioService(db: db);
    dispatcher = MockDownloadDispatcher();
    tmpDir = await Directory.systemTemp.createTemp('adm_test_');

    final packNames = ['pack_00.tar', 'pack_01.tar'];
    final client = manifestClient(packNames);

    manager = AudioDownloadManager(
      service,
      db,
      dispatcher,
      clientFactory: () => client,
    );
    manager.stagingPathOverride = tmpDir.path;
  });

  tearDown(() async {
    manager.dispose();
    await db.close();
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('startDownload', () {
    test('enqueues remaining packs from manifest', () async {
      final downloadFuture = manager.startDownload();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(dispatcher.enqueuedTasks, hasLength(2));
      expect(
        dispatcher.enqueuedTasks.map((t) => t.filename),
        containsAll(['pack_00.tar', 'pack_01.tar']),
      );

      for (final name in ['pack_00.tar', 'pack_01.tar']) {
        final tar = buildTar({
          '${name}_audio.mp3': Uint8List.fromList([1, 2]),
        });
        File('${tmpDir.path}/$name').writeAsBytesSync(tar);
        dispatcher.completeTask(name);
      }

      await downloadFuture;
      expect(await db.getCompletedPacks(), {'pack_00.tar', 'pack_01.tar'});
    });

    test('skips already-completed packs', () async {
      await db.markPackComplete('pack_00.tar');

      final downloadFuture = manager.startDownload();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(dispatcher.enqueuedTasks, hasLength(1));
      expect(dispatcher.enqueuedTasks.first.filename, 'pack_01.tar');

      final tar = buildTar({
        'b.mp3': Uint8List.fromList([2]),
      });
      File('${tmpDir.path}/pack_01.tar').writeAsBytesSync(tar);
      dispatcher.completeTask('pack_01.tar');

      await downloadFuture;
      expect(await db.getCompletedPacks(), {'pack_00.tar', 'pack_01.tar'});
    });

    test('fires progress callback', () async {
      final progressCalls = <(int, int)>[];
      manager.onProgress = (completed, total, _, _, _, _) {
        progressCalls.add((completed, total));
      };

      final downloadFuture = manager.startDownload();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(progressCalls, isNotEmpty);
      expect(progressCalls.first, (0, 2));

      final tar = buildTar({
        'a.mp3': Uint8List.fromList([1]),
      });
      File('${tmpDir.path}/pack_00.tar').writeAsBytesSync(tar);
      dispatcher.completeTask('pack_00.tar');

      await Future.delayed(const Duration(milliseconds: 50));
      expect(progressCalls.last.$1, 1);

      File('${tmpDir.path}/pack_01.tar').writeAsBytesSync(tar);
      dispatcher.completeTask('pack_01.tar');
      await downloadFuture;

      expect(progressCalls.last, (2, 2));
    });

    test('returns immediately when all packs already completed', () async {
      await db.markPackComplete('pack_00.tar');
      await db.markPackComplete('pack_01.tar');

      await manager.startDownload();

      expect(dispatcher.enqueuedTasks, isEmpty);
    });
  });

  group('cancelDownload', () {
    test('resets dispatcher and cleans staging dir', () async {
      final downloadFuture = manager.startDownload();
      await Future.delayed(const Duration(milliseconds: 50));

      File('${tmpDir.path}/pack_00.tar').writeAsBytesSync([1, 2, 3]);

      await manager.cancelDownload();

      expect(dispatcher.resetCount, 1);
      final staged = tmpDir.listSync().whereType<File>();
      expect(staged, isEmpty);

      await downloadFuture;
    });
  });

  group('circuit breaker', () {
    test('completes round after 5 consecutive failures', () async {
      final packNames = List.generate(
        10,
        (i) => 'pack_${i.toString().padLeft(2, '0')}.tar',
      );
      final client = manifestClient(packNames);
      final testDispatcher = MockDownloadDispatcher();
      final testManager = AudioDownloadManager(
        service,
        db,
        testDispatcher,
        clientFactory: () => client,
      );
      testManager.stagingPathOverride = tmpDir.path;

      final downloadFuture = testManager.startDownload();
      await Future.delayed(const Duration(milliseconds: 50));

      // Fail 5 packs consecutively — circuit breaker fires
      for (var i = 0; i < 5; i++) {
        testDispatcher.failTask('pack_${i.toString().padLeft(2, '0')}.tar');
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Circuit breaker should have called reset and unblocked _allDone
      await Future.delayed(const Duration(milliseconds: 50));
      expect(testDispatcher.resetCount, greaterThanOrEqualTo(1));

      // Cancel to avoid retry round backoff delays
      await testManager.cancelDownload();
      testManager.dispose();

      try {
        await downloadFuture;
      } catch (_) {
        // Expected — may throw after retry rounds
      }
    });
  });

  group('recoverPendingWork', () {
    test('extracts staged tar files from previous session', () async {
      final tar = buildTar({
        'recovered.mp3': Uint8List.fromList([7, 8, 9]),
      });
      File('${tmpDir.path}/pack_00.tar').writeAsBytesSync(tar);
      await db.markPackComplete('pack_01.tar');

      await manager.recoverPendingWork();

      expect(await db.getCompletedPacks(), contains('pack_00.tar'));
      expect(await db.get('recovered.mp3'), Uint8List.fromList([7, 8, 9]));
      expect(File('${tmpDir.path}/pack_00.tar').existsSync(), isFalse);
    });

    test('deletes staged tar for already-completed pack', () async {
      await db.markPackComplete('pack_00.tar');
      File('${tmpDir.path}/pack_00.tar').writeAsBytesSync([1, 2, 3]);
      await db.markPackComplete('pack_01.tar');

      await manager.recoverPendingWork();

      expect(File('${tmpDir.path}/pack_00.tar').existsSync(), isFalse);
    });
  });
}
