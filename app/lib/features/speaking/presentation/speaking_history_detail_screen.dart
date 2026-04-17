import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/speaking_providers.dart';
import 'widgets/attempt_stack.dart';

class SpeakingHistoryDetailScreen extends ConsumerWidget {
  final String sessionId;
  final String topic;

  const SpeakingHistoryDetailScreen({
    super.key,
    required this.sessionId,
    required this.topic,
  });

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final service = ref.read(speakingServiceProvider);
    await service?.deleteSession(sessionId);
    ref.invalidate(speakingHistoryProvider);
    ref.invalidate(speakingSessionByIdProvider(sessionId));
    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(speakingSessionByIdProvider(sessionId));
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          TextButton(
            onPressed: () => _delete(context, ref),
            child: Text('Delete', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('Session not found'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    topic,
                    style: textTheme.titleSmall?.copyWith(color: cs.primary),
                  ),
                ),
                const SizedBox(height: 8),
                AttemptStack(attempts: session.attempts, readOnly: true),
              ],
            ),
          );
        },
      ),
    );
  }
}
