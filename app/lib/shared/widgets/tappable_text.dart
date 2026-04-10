import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Text where words are tappable (tap to look up) and selectable.
/// Words show a subtle dotted underline to hint they're tappable.
class TappableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final void Function(String word) onWordTap;

  const TappableText({
    super.key,
    required this.text,
    this.style,
    required this.onWordTap,
  });

  @override
  State<TappableText> createState() => _TappableTextState();
}

class _TappableTextState extends State<TappableText> {
  static final _wordRegex = RegExp(r"([a-zA-Z'-]+)|([^a-zA-Z'-]+)");
  static final _cleanRegex = RegExp(r'^[^a-z]+|[^a-z]+$');

  List<TapGestureRecognizer> _recognizers = [];
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _buildSpans();
  }

  @override
  void didUpdateWidget(TappableText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _disposeRecognizers();
      _buildSpans();
    }
  }

  void _buildSpans() {
    final matches = _wordRegex.allMatches(widget.text);
    final spans = <InlineSpan>[];

    for (final m in matches) {
      final word = m.group(1);
      final other = m.group(2);

      if (word != null && word.length > 1) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onWordTap(_cleanWord(word));
        _recognizers.add(recognizer);
        spans.add(TextSpan(text: word, recognizer: recognizer));
      } else {
        spans.add(TextSpan(text: word ?? other ?? ''));
      }
    }
    _spans = spans;
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [];
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  String _cleanWord(String word) {
    var w = word.toLowerCase().trim();
    if (w.endsWith("'s")) w = w.substring(0, w.length - 2);
    w = w.replaceAll(_cleanRegex, '');
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = widget.style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        style: defaultStyle,
        children: _spans,
      ),
    );
  }
}
