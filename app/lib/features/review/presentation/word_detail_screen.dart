import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../dictionary/providers/search_provider.dart';
import '../../dictionary/presentation/widgets/entry_card.dart';

class WordDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> entryRow;

  const WordDetailScreen({super.key, required this.entryRow});

  @override
  ConsumerState<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends ConsumerState<WordDetailScreen> {
  DictEntry? _entry;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dictionaryDbProvider);
    final entry = await loadFullEntry(db, widget.entryRow);
    if (mounted) {
      setState(() {
        _entry = entry;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final headword = widget.entryRow['headword'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(headword)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entry == null
          ? const Center(child: Text('Entry not found'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: EntryCard(entry: _entry!, onWordTap: (_) {}),
            ),
    );
  }
}
