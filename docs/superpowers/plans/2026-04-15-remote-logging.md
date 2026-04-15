# Remote Logging & Device ID Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full observability to Deckionary -- crash reporting via Sentry, queryable diagnostic logs via Supabase, persistent device ID, and a hidden in-app log viewer.

**Architecture:** Talker as the unified logging API with a custom observer that fans out to Sentry (all levels as breadcrumbs/exceptions) and an in-memory buffer that batch-flushes to a Supabase `app_logs` table. Device ID is a UUID v4 stored in the existing settings table. `TalkerScreen` is hidden behind a long-press on the version text in Settings.

**Tech Stack:** talker_flutter, talker_riverpod_logger, sentry_flutter, Supabase, existing uuid package

**Spec:** `docs/superpowers/specs/2026-04-15-remote-logging-design.md`

---

## File Structure

### New files
| File | Responsibility |
|------|---------------|
| `app/lib/core/logging/logging_service.dart` | Global Talker instance, provider, device ID initialization |
| `app/lib/core/logging/sentry_talker_observer.dart` | TalkerObserver that routes to Sentry + log flush buffer |
| `app/lib/core/logging/log_flush_service.dart` | In-memory buffer, 30-min timer, batch flush to Supabase |
| `supabase/migrations/20260416000000_create_app_logs.sql` | app_logs table + indexes + pg_cron cleanup |
| `app/test/core/logging/log_flush_service_test.dart` | Tests for buffer/flush logic |

### Modified files
| File | Change |
|------|--------|
| `app/pubspec.yaml` | Add talker_flutter, talker_riverpod_logger, sentry_flutter |
| `app/lib/core/config.dart` | Add `sentryDsn` constant from env |
| `app/lib/core/database/settings_dao.dart` | Add `getDeviceId()` / `setDeviceId()` |
| `app/lib/main.dart` | SentryFlutter.init wrapping, Talker init, device ID, TalkerRiverpodObserver |
| `app/lib/features/settings/presentation/settings_screen.dart` | Long-press on version text → TalkerScreen |
| `app/lib/core/audio/audio_service.dart` | debugPrint → talker |
| `app/lib/core/audio/audio_provider.dart` | debugPrint → talker |
| `app/lib/core/network/http_retry.dart` | debugPrint → talker |
| `app/lib/core/auth/auth_service.dart` | debugPrint → talker |
| `app/lib/core/sync/settings_sync.dart` | debugPrint → talker |
| `app/lib/core/sync/review_sync.dart` | debugPrint → talker |
| `app/lib/core/sync/vocabulary_list_sync.dart` | debugPrint → talker |
| `app/lib/core/update/update_service.dart` | debugPrint → talker |
| `app/lib/core/update/play_store_update_service.dart` | debugPrint → talker |
| `app/lib/app.dart` | debugPrint → talker |

---

### Task 1: Add Dependencies

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Add packages to pubspec.yaml**

In `app/pubspec.yaml`, add under `dependencies:` after the `# Utilities` section:

```yaml
  # Logging & monitoring
  talker_flutter: any
  talker_riverpod_logger: any
  sentry_flutter: any
```

- [ ] **Step 2: Run flutter pub get**

```bash
cd app && flutter pub get
```

Expected: Resolves successfully, no version conflicts.

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "deps: add talker_flutter, talker_riverpod_logger, sentry_flutter"
```

---

### Task 2: Add Sentry DSN Config

**Files:**
- Modify: `app/lib/core/config.dart`

- [ ] **Step 1: Add sentryDsn constant**

Add to the end of `app/lib/core/config.dart`:

```dart
const sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: '', // set via --dart-define for dev/prod
);
```

Follows the same pattern as `supabaseAnonKey` -- empty default means disabled when not configured.

- [ ] **Step 2: Verify no compile errors**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: No new warnings or errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/config.dart
git commit -m "config: add SENTRY_DSN environment variable"
```

---

### Task 3: Device ID in SettingsDao

**Files:**
- Modify: `app/lib/core/database/settings_dao.dart`
- Test: `app/test/core/database/settings_dao_test.dart`

- [ ] **Step 1: Write the failing tests**

Add this group at the end of the `main()` function in `app/test/core/database/settings_dao_test.dart`:

```dart
  group('device ID', () {
    test('getDeviceId returns null when not set', () async {
      expect(await dao.getDeviceId(), isNull);
    });

    test('setDeviceId then getDeviceId returns stored value', () async {
      await dao.setDeviceId('test-device-123');
      expect(await dao.getDeviceId(), 'test-device-123');
    });

    test('setDeviceId does not trigger onSettingChanged', () async {
      final calls = <(String, String)>[];
      dao.onSettingChanged = (key, value) => calls.add((key, value));
      await dao.setDeviceId('device-abc');
      expect(calls, isEmpty);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd app && flutter test test/core/database/settings_dao_test.dart
```

Expected: FAIL -- `getDeviceId` and `setDeviceId` not defined.

- [ ] **Step 3: Implement getDeviceId and setDeviceId**

Add to `app/lib/core/database/settings_dao.dart`, at the end of the class before the closing `}`:

```dart
  // ── Device identification ─────────────────────────────────────────────

  static const _deviceIdKey = 'device_id';

  /// Returns the persistent device ID, or null if not yet generated.
  Future<String?> getDeviceId() => get(_deviceIdKey);

  /// Stores the device ID. Bypasses onSettingChanged since device_id
  /// is local-only and should never sync.
  Future<void> setDeviceId(String id) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: _deviceIdKey, value: id),
        );
  }
```

Note: `setDeviceId` writes directly to DB without calling `onSettingChanged`, because device_id is local-only and must not sync to Supabase settings.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd app && flutter test test/core/database/settings_dao_test.dart
```

Expected: All tests pass, including the new device ID group.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/database/settings_dao.dart app/test/core/database/settings_dao_test.dart
git commit -m "feat: add device ID get/set to SettingsDao"
```

---

### Task 4: Create Logging Service

**Files:**
- Create: `app/lib/core/logging/logging_service.dart`

- [ ] **Step 1: Create the logging service file**

Create `app/lib/core/logging/logging_service.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config.dart';
import '../database/settings_dao.dart';
import 'log_flush_service.dart';
import 'sentry_talker_observer.dart';

/// Global Talker instance. Starts as console-only; replaced in [initLogging]
/// with the fully configured instance (Sentry + flush observers).
Talker globalTalker = Talker();

/// Global log flush service. Null if sync is disabled.
LogFlushService? globalLogFlushService;

/// Riverpod provider for the Talker instance.
final talkerProvider = Provider<Talker>((ref) => globalTalker);

/// Riverpod provider for the device ID (already resolved at startup).
late final String globalDeviceId;
final deviceIdProvider = Provider<String>((ref) => globalDeviceId);

/// Resolves or creates the persistent device ID from the settings table.
Future<String> _resolveDeviceId(SettingsDao dao) async {
  final existing = await dao.getDeviceId();
  if (existing != null) return existing;
  final id = const Uuid().v4();
  await dao.setDeviceId(id);
  return id;
}

/// Initializes logging: device ID, Sentry scope, Talker with observers, flush service.
///
/// Call after [initDatabases] and sync services init complete, but BEFORE
/// [runApp] so that [TalkerRiverpodObserver] captures the final Talker.
Future<void> initLogging({
  required SettingsDao settingsDao,
  SupabaseClient? supabaseClient,
}) async {
  // 1. Device ID
  globalDeviceId = await _resolveDeviceId(settingsDao);

  // 2. Log flush service (only if Supabase is available)
  if (supabaseClient != null) {
    globalLogFlushService = LogFlushService(
      supabase: supabaseClient,
      deviceId: globalDeviceId,
    );
    globalLogFlushService!.init();
  }

  // 3. Sentry — configure scope with device ID
  if (sentryDsn.isNotEmpty) {
    Sentry.configureScope((scope) {
      scope.setTag('device_id', globalDeviceId);
      scope.setTag('platform', defaultTargetPlatform.name);
    });
  }

  // 4. Talker — replace the console-only default with fully configured instance
  globalTalker = Talker(
    observers: [
      SentryTalkerObserver(flushService: globalLogFlushService),
    ],
  );
}
```

**Important:** `globalTalker` starts as a plain `Talker()` (console-only) so it's usable before `initLogging` runs. `initLogging` replaces it with the fully configured instance. All init must complete BEFORE `runApp()` so that `TalkerRiverpodObserver` captures the final `globalTalker` reference (see Task 8).

- [ ] **Step 2: Verify no compile errors**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: May show errors for missing `SentryTalkerObserver` and `LogFlushService` -- those are created in Tasks 5 and 6. That's fine for now; this file compiles once those are added.

- [ ] **Step 3: Commit**

```bash
git add app/lib/core/logging/logging_service.dart
git commit -m "feat: add logging service with Talker init and device ID"
```

---

### Task 5: Create Sentry Talker Observer

**Files:**
- Create: `app/lib/core/logging/sentry_talker_observer.dart`

- [ ] **Step 1: Create the observer file**

Create `app/lib/core/logging/sentry_talker_observer.dart`:

```dart
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import '../config.dart';
import 'log_flush_service.dart';

/// Routes Talker log events to Sentry and the log flush buffer.
class SentryTalkerObserver extends TalkerObserver {
  final LogFlushService? _flushService;

  SentryTalkerObserver({LogFlushService? flushService})
      : _flushService = flushService;

  bool get _sentryEnabled => sentryDsn.isNotEmpty;

  @override
  void onError(TalkerError err) {
    if (_sentryEnabled) {
      Sentry.captureException(err.error, stackTrace: err.stackTrace);
    }
    _flushService?.addError(
      message: err.message,
      error: err.error.toString(),
      stackTrace: err.stackTrace?.toString(),
    );
  }

  @override
  void onException(TalkerException exception) {
    if (_sentryEnabled) {
      Sentry.captureException(
        exception.exception,
        stackTrace: exception.stackTrace,
      );
    }
    _flushService?.addError(
      message: exception.message,
      error: exception.exception.toString(),
      stackTrace: exception.stackTrace?.toString(),
    );
  }

  @override
  void onLog(TalkerLog log) {
    if (_sentryEnabled) {
      Sentry.addBreadcrumb(Breadcrumb(
        message: log.message,
        level: _mapLevel(log.logLevel),
        timestamp: DateTime.now(),
      ));
    }
    // Only buffer non-debug logs for Supabase flush
    if (log.logLevel != LogLevel.debug) {
      _flushService?.addLog(
        level: log.logLevel.name,
        message: log.message,
      );
    }
  }

  SentryLevel _mapLevel(LogLevel level) {
    return switch (level) {
      LogLevel.error => SentryLevel.error,
      LogLevel.warning => SentryLevel.warning,
      LogLevel.info => SentryLevel.info,
      _ => SentryLevel.debug,
    };
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/lib/core/logging/sentry_talker_observer.dart
git commit -m "feat: add SentryTalkerObserver for log routing"
```

---

### Task 6: Create Log Flush Service

**Files:**
- Create: `app/lib/core/logging/log_flush_service.dart`
- Create: `app/test/core/logging/log_flush_service_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `app/test/core/logging/log_flush_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/logging/log_flush_service.dart';

void main() {
  late LogFlushService service;
  late List<List<Map<String, dynamic>>> insertedBatches;

  setUp(() {
    insertedBatches = [];
    service = LogFlushService.forTesting(
      deviceId: 'test-device-id',
      onFlush: (batch) async => insertedBatches.add(batch),
    );
  });

  tearDown(() {
    service.dispose();
  });

  group('buffer management', () {
    test('addLog buffers entries', () {
      service.addLog(level: 'info', message: 'test message');
      expect(service.bufferLength, 1);
    });

    test('addError buffers error entries', () {
      service.addError(
        message: 'error msg',
        error: 'SomeException',
        stackTrace: '#0 main',
      );
      expect(service.bufferLength, 1);
      // Verify the buffered entry has error fields
    });

    test('flush sends buffer and clears it', () async {
      service.addLog(level: 'info', message: 'msg1');
      service.addLog(level: 'warning', message: 'msg2');
      expect(service.bufferLength, 2);

      await service.flush();

      expect(service.bufferLength, 0);
      expect(insertedBatches.length, 1);
      expect(insertedBatches[0].length, 2);
      expect(insertedBatches[0][0]['message'], 'msg1');
      expect(insertedBatches[0][0]['level'], 'info');
      expect(insertedBatches[0][0]['device_id'], 'test-device-id');
      expect(insertedBatches[0][1]['message'], 'msg2');
    });

    test('flush is no-op when buffer is empty', () async {
      await service.flush();
      expect(insertedBatches, isEmpty);
    });

    test('flush retains buffer on failure', () async {
      service = LogFlushService.forTesting(
        deviceId: 'test-device-id',
        onFlush: (_) async => throw Exception('network error'),
      );
      service.addLog(level: 'info', message: 'will retry');

      await service.flush();

      // Buffer should still contain the entry for retry
      expect(service.bufferLength, 1);
      expect(insertedBatches, isEmpty);
    });
  });

  group('auto-flush on threshold', () {
    test('flushes when buffer reaches 50 entries', () async {
      for (int i = 0; i < 50; i++) {
        service.addLog(level: 'info', message: 'msg $i');
      }
      // Give async flush a tick to complete
      await Future.delayed(Duration.zero);

      expect(insertedBatches.length, 1);
      expect(insertedBatches[0].length, 50);
      expect(service.bufferLength, 0);
    });
  });

  group('log entry fields', () {
    test('addLog includes required fields', () async {
      service.addLog(level: 'warning', message: '[SYNC] push failed');
      await service.flush();

      final entry = insertedBatches[0][0];
      expect(entry['device_id'], 'test-device-id');
      expect(entry['level'], 'warning');
      expect(entry['message'], '[SYNC] push failed');
      expect(entry.containsKey('created_at'), isTrue);
      expect(entry.containsKey('app_version'), isTrue);
      expect(entry.containsKey('platform'), isTrue);
    });

    test('addError includes error and stack_trace', () async {
      service.addError(
        message: 'sync crash',
        error: 'FormatException: bad data',
        stackTrace: '#0 SyncService.push',
      );
      await service.flush();

      final entry = insertedBatches[0][0];
      expect(entry['level'], 'error');
      expect(entry['error'], 'FormatException: bad data');
      expect(entry['stack_trace'], '#0 SyncService.push');
    });
  });
}
```

- [ ] **Step 2: Create the log flush service implementation**

Create `app/lib/core/logging/log_flush_service.dart`:

```dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../build_info.dart';

/// Buffers log entries in memory and batch-flushes to Supabase.
///
/// Flush triggers: every 30 minutes, on app resume, or buffer >= 50 entries.
class LogFlushService with WidgetsBindingObserver {
  final String _deviceId;
  final Future<void> Function(List<Map<String, dynamic>> batch) _insertBatch;
  final List<Map<String, dynamic>> _buffer = [];
  Timer? _timer;

  static const _flushThreshold = 50;
  static const _flushInterval = Duration(minutes: 30);

  /// Production constructor — flushes to Supabase.
  LogFlushService({
    required SupabaseClient supabase,
    required String deviceId,
  })  : _deviceId = deviceId,
        _insertBatch = ((batch) => supabase.from('app_logs').insert(batch));

  /// Test constructor — uses a custom flush callback.
  LogFlushService.forTesting({
    required String deviceId,
    required Future<void> Function(List<Map<String, dynamic>> batch) onFlush,
  })  : _deviceId = deviceId,
        _insertBatch = onFlush;

  /// Number of buffered entries (exposed for testing).
  int get bufferLength => _buffer.length;

  /// Start the periodic flush timer and lifecycle observer.
  void init() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Add an info/warning log entry to the buffer.
  void addLog({required String level, required String message}) {
    _buffer.add(_makeEntry(level: level, message: message));
    _flushIfThresholdReached();
  }

  /// Add an error log entry to the buffer.
  void addError({
    required String message,
    String? error,
    String? stackTrace,
  }) {
    _buffer.add(_makeEntry(
      level: 'error',
      message: message,
      error: error,
      stackTrace: stackTrace,
    ));
    _flushIfThresholdReached();
  }

  Map<String, dynamic> _makeEntry({
    required String level,
    required String message,
    String? error,
    String? stackTrace,
  }) {
    // Extract tag from message if it follows the [TAG] pattern
    String? tag;
    var msg = message;
    final tagMatch = RegExp(r'^\[(\w+)\]\s*').firstMatch(message);
    if (tagMatch != null) {
      tag = tagMatch.group(1);
      msg = message.substring(tagMatch.end);
    }

    return {
      'device_id': _deviceId,
      'level': level,
      'tag': tag,
      'message': msg,
      'error': error,
      'stack_trace': stackTrace,
      'app_version': appVersion,
      'platform': Platform.operatingSystem,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  void _flushIfThresholdReached() {
    if (_buffer.length >= _flushThreshold) {
      flush();
    }
  }

  /// Flush the buffer to Supabase. Safe to call at any time.
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.of(_buffer);
    _buffer.clear();
    try {
      await _insertBatch(batch);
    } catch (_) {
      // Put entries back for retry on next flush
      _buffer.insertAll(0, batch);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      flush();
    }
  }

  /// Stop the timer and observer. Attempts a final flush.
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
```

- [ ] **Step 3: Run tests**

```bash
cd app && flutter test test/core/logging/log_flush_service_test.dart
```

Expected: All tests pass.

- [ ] **Step 4: Run full test suite**

```bash
cd app && flutter test
```

Expected: All existing tests still pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/logging/log_flush_service.dart app/test/core/logging/log_flush_service_test.dart
git commit -m "feat: add LogFlushService with batch buffer and auto-flush"
```

---

### Task 7: Supabase Migration

**Files:**
- Create: `supabase/migrations/20260416000000_create_app_logs.sql`

- [ ] **Step 1: Create the migration file**

Create `supabase/migrations/20260416000000_create_app_logs.sql`:

```sql
-- Diagnostic log table for remote observability.
-- Logs are write-only from clients, queried from Supabase dashboard.
-- Auto-cleaned after 7 days via pg_cron.

CREATE TABLE app_logs (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  device_id  TEXT        NOT NULL,
  user_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  level      TEXT        NOT NULL,
  tag        TEXT,
  message    TEXT        NOT NULL,
  error      TEXT,
  stack_trace TEXT,
  app_version TEXT,
  platform   TEXT,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_app_logs_device ON app_logs(device_id, created_at DESC);
CREATE INDEX idx_app_logs_level  ON app_logs(level, created_at DESC);

-- Allow any client to insert logs (including unauthenticated).
-- No SELECT/UPDATE/DELETE from client — query from dashboard only.
ALTER TABLE app_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_insert" ON app_logs FOR INSERT WITH CHECK (true);

-- Auto-delete logs older than 7 days (runs daily at 03:00 UTC).
SELECT cron.schedule(
  'clean-old-app-logs',
  '0 3 * * *',
  $$DELETE FROM app_logs WHERE created_at < now() - interval '7 days'$$
);
```

- [ ] **Step 2: Verify migration applies cleanly**

```bash
cd /Users/xuanlong/personal/oxford-5000-to-anki && supabase db reset
```

Expected: All migrations apply successfully. If `pg_cron` is not enabled on local Supabase, the `cron.schedule` call may fail locally -- that's acceptable since pg_cron is available on hosted Supabase. If it fails locally, wrap the cron line in a `DO $$ BEGIN ... EXCEPTION WHEN OTHERS THEN NULL; END $$;` block.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260416000000_create_app_logs.sql
git commit -m "db: add app_logs table with 7-day auto-cleanup"
```

---

### Task 8: Wire Up main.dart

**Files:**
- Modify: `app/lib/main.dart`

The key architectural change: move ALL initialization (databases, sync, logging) into `main()` BEFORE `runApp()`. This ensures `globalTalker` is fully configured when `TalkerRiverpodObserver` captures its reference. The `AppLoader` widget is removed -- the native splash screen covers the brief init time.

- [ ] **Step 1: Update main.dart with Sentry and Talker initialization**

Replace the entire contents of `app/lib/main.dart` with:

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_riverpod_logger/talker_riverpod_logger.dart';
import 'package:window_manager/window_manager.dart';
import 'firebase_options.dart';
import 'core/config.dart';
import 'core/database/database_provider.dart';
import 'core/database/settings_dao.dart';
import 'core/logging/logging_service.dart';
import 'app.dart';

/// Whether Firebase + Supabase auth/sync is available.
/// False until Firebase project is configured.
bool syncEnabled = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
  }

  // Initialize databases + sync services before runApp so that
  // globalTalker is fully configured when TalkerRiverpodObserver captures it.
  try {
    await Future.wait([initDatabases(), _initSyncServices()]);
    await initLogging(
      settingsDao: SettingsDao(globalUserDb),
      supabaseClient: syncEnabled ? Supabase.instance.client : null,
    );
  } catch (e) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(child: Text('Failed to start: $e')),
      ),
    ));
    return;
  }

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.environment = kDebugMode ? 'development' : 'production';
      },
      appRunner: () => _runApp(),
    );
  } else {
    _runApp();
  }
}

Future<void> _initSyncServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '43742335452-ef9piond4ujid0ulcf3695857s938urc.apps.googleusercontent.com',
      );
      syncEnabled = true;
    }
  } catch (e, st) {
    globalTalker.warning('[INIT] sync services not available: $e');
  }
}

void _runApp() {
  runApp(ProviderScope(
    observers: [TalkerRiverpodObserver(talker: globalTalker)],
    child: const DeckionaryApp(),
  ));
}
```

Key changes from original `main.dart`:
1. All init moved to `main()` before `runApp()` -- ensures `globalTalker` is fully configured
2. `AppLoader` removed -- native splash screen covers the brief init time
3. Sentry wraps `_runApp()` via `SentryFlutter.init(appRunner:)` -- only if DSN configured
4. `TalkerRiverpodObserver` added to `ProviderScope.observers`
5. Error in init → fallback error UI (same behavior as old AppLoader's FutureBuilder error case)
6. `_initSyncServices()` catches its own errors internally (sync failure is non-fatal)

Note: The `DeckionaryApp` widget (in `app.dart`) is used directly, bypassing the old `AppLoader`. Any code that imports `main.dart` for `syncEnabled` still works.

- [ ] **Step 2: Verify compilation**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/main.dart
git commit -m "feat: wire up Sentry, Talker, and device ID in main.dart"
```

---

### Task 9: In-App Log Viewer

**Files:**
- Modify: `app/lib/features/settings/presentation/settings_screen.dart`

- [ ] **Step 1: Add long-press gesture on version text**

In `app/lib/features/settings/presentation/settings_screen.dart`:

Add imports at the top:
```dart
import 'package:talker_flutter/talker_flutter.dart';
import '../../../core/logging/logging_service.dart';
```

Replace the version text `Center` widget (lines 146-151):
```dart
            Center(
              child: Text(
                'v$appVersion${isDevBuild ? '-dev' : ''} · ${buildCommit.length > 7 ? buildCommit.substring(0, 7) : buildCommit}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
```

With:
```dart
            Center(
              child: GestureDetector(
                onLongPress: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TalkerScreen(talker: globalTalker),
                  ),
                ),
                child: Text(
                  'v$appVersion${isDevBuild ? '-dev' : ''} · ${buildCommit.length > 7 ? buildCommit.substring(0, 7) : buildCommit}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ),
```

- [ ] **Step 2: Verify compilation**

```bash
cd app && flutter analyze --fatal-warnings
```

Expected: No errors.

- [ ] **Step 3: Manual test**

Run the app, go to Settings, long-press the version text at the bottom. The Talker log viewer screen should open showing recent logs.

- [ ] **Step 4: Commit**

```bash
git add app/lib/features/settings/presentation/settings_screen.dart
git commit -m "feat: add hidden log viewer via long-press on version text"
```

---

### Task 10: Migrate debugPrint to Talker

**Files:**
- Modify: 12 files (listed below)

For each file: add `import '../logging/logging_service.dart';` (adjusting relative path), replace `debugPrint(...)` with appropriate `globalTalker.info/error/warning(...)`, and change `catch (e)` to `catch (e, st)` in error blocks.

- [ ] **Step 1: Migrate core/auth/auth_service.dart**

Replace `debugPrint` calls. The info-level `[AUTH]` messages stay as info. The catch block already uses `catch (e, st)`.

```dart
// Replace:
debugPrint('[AUTH] Starting Google Sign-In...');
// With:
globalTalker.info('[AUTH] Starting Google Sign-In...');

// (same for all other debugPrint calls in info flow)

// In catch block, replace:
debugPrint('[AUTH] Sign in failed: $e');
debugPrint('[AUTH] Stack trace: $st');
// With:
globalTalker.error('[AUTH] Sign in failed', e, st);
```

Add import: `import '../logging/logging_service.dart';`

- [ ] **Step 2: Migrate core/audio/audio_service.dart**

Add import: `import '../logging/logging_service.dart';`

All `[AudioDL]` prefixed debugPrint calls → `globalTalker.info('[AudioDL] ...')`.

For the catch block in `play()` (line ~309), change:
```dart
} catch (e) {
  debugPrint('AudioService: error $filename: $e');
}
```
to:
```dart
} catch (e, st) {
  globalTalker.error('[AUDIO] error $filename', e, st);
}
```

For the catch block in `downloadAll()` pack loop (line ~501), change:
```dart
} catch (e) {
  debugPrint('[AudioDL] pack $packName: error ...: $e');
```
to:
```dart
} catch (e, st) {
  globalTalker.error('[AudioDL] pack $packName: error after ${packSw.elapsedMilliseconds}ms', e, st);
```

For the non-200 status code log (line ~295):
```dart
debugPrint('AudioService: server returned ${response.statusCode} for $filename');
```
→
```dart
globalTalker.warning('[AUDIO] server returned ${response.statusCode} for $filename');
```

All other `debugPrint` in info flow → `globalTalker.info(...)`.

- [ ] **Step 3: Migrate core/audio/audio_provider.dart**

Add import: `import '../logging/logging_service.dart';`

```dart
// Replace (line ~120):
debugPrint('OfflineAudioNotifier: download failed: $e');
// With:
globalTalker.error('[AudioDL] download failed', e);

// Replace (line ~149):
debugPrint('OfflineAudioNotifier: clearCache failed: $e');
// With:
globalTalker.error('[AudioDL] clearCache failed', e);
```

Change both `catch (e)` to `catch (e, st)` and pass `st` as third arg.

- [ ] **Step 4: Migrate core/network/http_retry.dart**

Add import: `import '../logging/logging_service.dart';`

```dart
// Replace retry warning (line ~50):
debugPrint('httpGetWithRetry: ${response.statusCode} for $url ...');
// With:
globalTalker.warning('[HTTP] ${response.statusCode} for $url (attempt ${attempt + 1}/$maxAttempts, retrying)');

// Replace catch block (line ~65):
debugPrint('httpGetWithRetry: $e for $url ...');
// With (change catch (e) to catch (e, st)):
globalTalker.warning('[HTTP] $e for $url (attempt ${attempt + 1}/$maxAttempts, retrying)');
```

- [ ] **Step 5: Migrate core/sync/ files**

**settings_sync.dart** — Add import: `import '../logging/logging_service.dart';`
```dart
// Replace (line ~45):
debugPrint('Push setting "$key" failed, marking dirty: $e');
// With (change catch (e) to catch (e, st)):
globalTalker.error('[SYNC] push setting "$key" failed, marking dirty', e, st);
```

**review_sync.dart** — Add import: `import '../logging/logging_service.dart';`
```dart
// Replace (line ~65):
debugPrint('Push review card failed (will retry): $e');
// With:
globalTalker.error('[SYNC] push review card failed (will retry)', e, st);

// Replace (line ~107):
debugPrint('Push review log failed (will retry): $e');
// With:
globalTalker.error('[SYNC] push review log failed (will retry)', e, st);
```
Change both `catch (e)` to `catch (e, st)`.

**vocabulary_list_sync.dart** — Add import: `import '../logging/logging_service.dart';`
```dart
// Replace (line ~55):
debugPrint('Push vocabulary list failed: $e');
// With:
globalTalker.error('[SYNC] push vocabulary list failed', e, st);

// Replace (line ~93):
debugPrint('Push vocabulary list entry failed: $e');
// With:
globalTalker.error('[SYNC] push vocabulary list entry failed', e, st);
```
Change both `catch (e)` to `catch (e, st)`.

- [ ] **Step 6: Migrate core/update/ files**

**update_service.dart** — Add import: `import '../logging/logging_service.dart';`
```dart
// Replace (line ~58):
debugPrint('Update check failed: $e');
// With (change catch (e) to catch (e, st)):
globalTalker.error('[UPDATE] check failed', e, st);
```

**play_store_update_service.dart** — Add import: `import '../logging/logging_service.dart';`
```dart
// Replace (line ~17):
debugPrint('Play Store update check failed: $e');
// With:
globalTalker.error('[UPDATE] Play Store check failed', e, st);

// Replace (line ~39, in onError callback):
debugPrint('Update listener error: $e');
// With:
globalTalker.error('[UPDATE] listener error: $e');

// Replace (line ~44):
debugPrint('Flexible update failed: $e');
// With:
globalTalker.error('[UPDATE] flexible update failed', e, st);
```
Change `catch (e)` to `catch (e, st)` where applicable.

- [ ] **Step 7: Migrate app.dart**

Add import: `import 'core/logging/logging_service.dart';`

```dart
// Replace (line ~246):
debugPrint('Failed to register hotkey: $e');
// With (change catch (e) to catch (e, st)):
globalTalker.error('[HOTKEY] failed to register', e, st);

// Replace (line ~264):
debugPrint('Failed to setup tray icon: $e');
// With:
globalTalker.error('[TRAY] failed to setup', e, st);

// Replace (line ~379):
debugPrint('Could not position window: $e');
// With:
globalTalker.error('[WINDOW] could not position', e, st);
```
Change all three `catch (e)` to `catch (e, st)`.

- [ ] **Step 8: Verify main.dart**

The `debugPrint` in `_initSyncServices` was already migrated in Task 8 when rewriting main.dart. It now uses `globalTalker.warning('[INIT] sync services not available: $e')`. Verify it's present and correct.

- [ ] **Step 9: Verify no remaining debugPrint usage**

```bash
cd app && grep -r 'debugPrint' lib/ --include='*.dart'
```

Expected: No results (all migrated).

- [ ] **Step 10: Run analysis and tests**

```bash
cd app && flutter analyze --fatal-warnings && flutter test
```

Expected: No warnings, all tests pass.

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "refactor: migrate all debugPrint calls to Talker logging"
```

---

### Task 11: Final Verification

- [ ] **Step 1: Run the full app**

```bash
cd app && flutter run
```

Verify:
1. App starts without errors
2. Console shows Talker-formatted log output (colored, timestamped)
3. Go to Settings → long-press version text → TalkerScreen opens with logs

- [ ] **Step 2: Verify Sentry (if DSN configured)**

```bash
cd app && flutter run --dart-define-from-file=env.json
```

Check Sentry dashboard for a test event. If no DSN yet, this step is deferred.

- [ ] **Step 3: Verify Supabase log flushing (if sync enabled)**

After running the app with sync enabled for a few minutes, check the Supabase dashboard:
```sql
SELECT * FROM app_logs ORDER BY created_at DESC LIMIT 10;
```

Expected: Log entries with device_id, level, message, platform, app_version populated.

- [ ] **Step 4: Run full test suite one more time**

```bash
cd app && flutter test
```

Expected: All tests pass.

- [ ] **Step 5: Final commit if any fixups needed**

```bash
cd app && flutter analyze --fatal-warnings
```
