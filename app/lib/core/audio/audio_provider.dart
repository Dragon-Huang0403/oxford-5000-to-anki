import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_service.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(service.dispose);
  return service;
});

/// Single source of truth for offline audio state
class OfflineAudioState {
  final int cachedFiles;
  final int cachedBytes;
  final bool downloading;
  final int downloadedFiles;
  final int totalFiles;
  final int downloadedBytes;
  final String? error;

  const OfflineAudioState({
    this.cachedFiles = 0,
    this.cachedBytes = 0,
    this.downloading = false,
    this.downloadedFiles = 0,
    this.totalFiles = 0,
    this.downloadedBytes = 0,
    this.error,
  });

  static const totalAudioInDb = 217156;

  bool get isFullyDownloaded => cachedFiles >= totalAudioInDb;
  double get progress => totalFiles > 0 ? downloadedFiles / totalFiles : 0;

  String get cacheSizeFormatted {
    final bytes = cachedBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class OfflineAudioNotifier extends AsyncNotifier<OfflineAudioState> {
  @override
  Future<OfflineAudioState> build() async {
    final audio = ref.read(audioServiceProvider);
    final stats = await audio.getCacheStats();
    return OfflineAudioState(
      cachedFiles: stats.fileCount,
      cachedBytes: stats.sizeBytes,
    );
  }

  Future<void> downloadAll() async {
    final current = state.when(
      data: (s) => s,
      loading: () => const OfflineAudioState(),
      error: (_, _) => const OfflineAudioState(),
    );
    if (current.downloading) return;

    state = AsyncData(OfflineAudioState(
      cachedFiles: current.cachedFiles,
      cachedBytes: current.cachedBytes,
      downloading: true,
    ));

    final audio = ref.read(audioServiceProvider);
    try {
      await audio.downloadAll(
        onProgress: (downloaded, total, bytes) {
          state = AsyncData(OfflineAudioState(
            cachedFiles: current.cachedFiles + downloaded,
            cachedBytes: current.cachedBytes + bytes,
            downloading: true,
            downloadedFiles: downloaded,
            totalFiles: total,
            downloadedBytes: bytes,
          ));
        },
      );
      // Refresh real stats from disk
      final stats = await audio.getCacheStats();
      state = AsyncData(OfflineAudioState(
        cachedFiles: stats.fileCount,
        cachedBytes: stats.sizeBytes,
      ));
    } catch (e) {
      final stats = await audio.getCacheStats();
      state = AsyncData(OfflineAudioState(
        cachedFiles: stats.fileCount,
        cachedBytes: stats.sizeBytes,
        error: e.toString(),
      ));
    }
  }

  Future<void> clearCache() async {
    final audio = ref.read(audioServiceProvider);
    await audio.clearCache();
    state = const AsyncData(OfflineAudioState());
  }
}

final offlineAudioProvider =
    AsyncNotifierProvider<OfflineAudioNotifier, OfflineAudioState>(OfflineAudioNotifier.new);
