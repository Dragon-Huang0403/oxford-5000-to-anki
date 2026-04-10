import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_provider.dart';
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
  final int completedPacks;
  final int totalPacks;
  final int filesExtracted;
  final int downloadedBytes;
  final int totalAudioFiles;
  final String? error;

  const OfflineAudioState({
    this.cachedFiles = 0,
    this.cachedBytes = 0,
    this.downloading = false,
    this.completedPacks = 0,
    this.totalPacks = 0,
    this.filesExtracted = 0,
    this.downloadedBytes = 0,
    this.totalAudioFiles = 0,
    this.error,
  });

  bool get isFullyDownloaded =>
      totalAudioFiles > 0 && cachedFiles >= totalAudioFiles;
  double get progress => totalPacks > 0 ? completedPacks / totalPacks : 0;

  String get cacheSizeFormatted {
    final bytes = cachedBytes;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class OfflineAudioNotifier extends AsyncNotifier<OfflineAudioState> {
  @override
  Future<OfflineAudioState> build() async {
    final audio = ref.read(audioServiceProvider);
    final dictDb = ref.read(dictionaryDbProvider);
    final stats = await audio.getCacheStats();
    final allFilenames = await dictDb.getAllAudioFilenames();
    return OfflineAudioState(
      cachedFiles: stats.fileCount,
      cachedBytes: stats.sizeBytes,
      totalAudioFiles: allFilenames.length,
    );
  }

  Future<void> downloadAll() async {
    final current = state.when(
      data: (s) => s,
      loading: () => const OfflineAudioState(),
      error: (_, _) => const OfflineAudioState(),
    );
    if (current.downloading) return;

    state = AsyncData(
      OfflineAudioState(
        cachedFiles: current.cachedFiles,
        cachedBytes: current.cachedBytes,
        totalAudioFiles: current.totalAudioFiles,
        downloading: true,
      ),
    );

    final audio = ref.read(audioServiceProvider);
    try {
      await audio.downloadAll(
        onProgress: (completedPacks, totalPacks, filesExtracted, bytes) {
          state = AsyncData(
            OfflineAudioState(
              cachedFiles: current.cachedFiles + filesExtracted,
              cachedBytes: current.cachedBytes + bytes,
              totalAudioFiles: current.totalAudioFiles,
              downloading: true,
              completedPacks: completedPacks,
              totalPacks: totalPacks,
              filesExtracted: filesExtracted,
              downloadedBytes: bytes,
            ),
          );
        },
      );
      final stats = await audio.getCacheStats();
      state = AsyncData(
        OfflineAudioState(
          cachedFiles: stats.fileCount,
          cachedBytes: stats.sizeBytes,
          totalAudioFiles: current.totalAudioFiles,
        ),
      );
    } catch (e) {
      final stats = await audio.getCacheStats();
      state = AsyncData(
        OfflineAudioState(
          cachedFiles: stats.fileCount,
          cachedBytes: stats.sizeBytes,
          totalAudioFiles: current.totalAudioFiles,
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> clearCache() async {
    final audio = ref.read(audioServiceProvider);
    await audio.clearCache();
    state = const AsyncData(OfflineAudioState());
  }
}

final offlineAudioProvider =
    AsyncNotifierProvider<OfflineAudioNotifier, OfflineAudioState>(
      OfflineAudioNotifier.new,
    );
