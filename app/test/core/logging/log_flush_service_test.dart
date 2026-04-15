import 'package:flutter_test/flutter_test.dart';
import 'package:deckionary/core/logging/log_flush_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

      expect(service.bufferLength, 1);
      expect(insertedBatches, isEmpty);
    });
  });

  group('auto-flush on threshold', () {
    test('flushes when buffer reaches 50 entries', () async {
      for (int i = 0; i < 50; i++) {
        service.addLog(level: 'info', message: 'msg $i');
      }
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
      // Tag extraction strips the [SYNC] prefix from message
      expect(entry['tag'], 'SYNC');
      expect(entry['message'], 'push failed');
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
