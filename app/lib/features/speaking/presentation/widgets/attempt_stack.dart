import 'package:flutter/material.dart';

import '../../domain/speaking_attempt.dart';
import 'attempt_card.dart';

/// Renders a list of attempts with the newest expanded on top and older ones
/// collapsed. Tapping a collapsed card expands it (and collapses the other
/// expanded one — single-expansion model keeps the screen from growing huge).
class AttemptStack extends StatefulWidget {
  final List<SpeakingAttempt> attempts; // index 0 = oldest
  final bool readOnly;

  const AttemptStack({
    super.key,
    required this.attempts,
    this.readOnly = false,
  });

  @override
  State<AttemptStack> createState() => _AttemptStackState();
}

class _AttemptStackState extends State<AttemptStack> {
  String? _expandedId;

  @override
  void didUpdateWidget(covariant AttemptStack old) {
    super.didUpdateWidget(old);
    if (widget.attempts.isNotEmpty &&
        widget.attempts.length > old.attempts.length) {
      _expandedId = widget.attempts.last.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordered = [...widget.attempts].reversed.toList(); // newest first
    final expandedId =
        _expandedId ?? (ordered.isNotEmpty ? ordered.first.id : null);
    final total = widget.attempts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attempt in ordered)
          AttemptCard(
            key: ValueKey(attempt.id),
            attempt: attempt,
            totalAttempts: total,
            expanded: attempt.id == expandedId,
            readOnly: widget.readOnly,
            onToggle: () {
              setState(() {
                _expandedId = attempt.id == expandedId ? null : attempt.id;
              });
            },
          ),
      ],
    );
  }
}
