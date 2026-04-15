import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:uuid/uuid.dart';
import '../build_info.dart';
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
      scope.setTag('build_commit', buildCommit);
    });
  }

  // 4. Talker — replace the console-only default with fully configured instance
  globalTalker = Talker(
    observer: SentryTalkerObserver(flushService: globalLogFlushService),
  );
}
