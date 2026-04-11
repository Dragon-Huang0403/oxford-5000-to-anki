import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../providers/review_providers.dart';
import 'word_detail_screen.dart';

typedef _PageLoader = Future<List<Map<String, dynamic>>> Function(int limit, int offset);

class _TabInfo {
  final String label;
  final Color? color;
  final _PageLoader loader;

  const _TabInfo({required this.label, this.color, required this.loader});
}

class StudyWordsScreen extends ConsumerStatefulWidget {
  const StudyWordsScreen({super.key});

  @override
  ConsumerState<StudyWordsScreen> createState() => _StudyWordsScreenState();
}

class _StudyWordsScreenState extends ConsumerState<StudyWordsScreen> {
  List<_TabInfo>? _tabs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTabs();
  }

  Future<void> _loadTabs() async {
    final filter = await ref.read(reviewFilterProvider.future);
    final db = ref.read(dictionaryDbProvider);

    final cefrLevels = await db.getDistinctCefrLevelsForFilter(
      cefrLevels: filter.cefrLevels.toList(),
      ox3000: filter.ox3000,
      ox5000: filter.ox5000,
    );

    final tabs = <_TabInfo>[];

    // "All" tab — always first
    tabs.add(_TabInfo(
      label: 'All',
      loader: (limit, offset) => db.getFilteredEntries(
        cefrLevels: filter.cefrLevels.toList(),
        ox3000: filter.ox3000,
        ox5000: filter.ox5000,
        limit: limit,
        offset: offset,
      ),
    ));

    // CEFR level tabs
    for (final level in cefrLevels) {
      tabs.add(_TabInfo(
        label: level.toUpperCase(),
        color: _cefrColor(level),
        loader: (limit, offset) => db.getFilteredEntriesByCefr(
          level,
          cefrLevels: filter.cefrLevels.toList(),
          ox3000: filter.ox3000,
          ox5000: filter.ox5000,
          limit: limit,
          offset: offset,
        ),
      ));
    }

    // Oxford tabs
    if (filter.ox3000) {
      tabs.add(_TabInfo(
        label: 'Oxford 3000',
        loader: (limit, offset) => db.getEntriesByOxfordList(
          ox3000: true,
          limit: limit,
          offset: offset,
        ),
      ));
    }
    if (filter.ox5000) {
      tabs.add(_TabInfo(
        label: 'Oxford 5000',
        loader: (limit, offset) => db.getEntriesByOxfordList(
          ox3000: false,
          limit: limit,
          offset: offset,
        ),
      ));
    }

    if (mounted) {
      setState(() {
        _tabs = tabs;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _tabs == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Study Words')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_tabs!.length <= 1 && _tabs!.first.label == 'All') {
      // Only "All" tab with potentially no results — still show it
    }

    return DefaultTabController(
      length: _tabs!.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Study Words'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: _tabs!.map((tab) => Tab(
              child: Text(
                tab.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: tab.color,
                ),
              ),
            )).toList(),
          ),
        ),
        body: TabBarView(
          children: _tabs!.map((tab) => _WordListTab(
            loader: tab.loader,
          )).toList(),
        ),
      ),
    );
  }

  static Color _cefrColor(String level) {
    return switch (level) {
      'a1' => const Color(0xFF4CAF50),
      'a2' => const Color(0xFF8BC34A),
      'b1' => const Color(0xFFFFC107),
      'b2' => const Color(0xFFFF9800),
      'c1' => const Color(0xFF9C27B0),
      _ => const Color(0xFF607D8B),
    };
  }
}

class _WordListTab extends StatefulWidget {
  final _PageLoader loader;

  const _WordListTab({required this.loader});

  @override
  State<_WordListTab> createState() => _WordListTabState();
}

class _WordListTabState extends State<_WordListTab>
    with AutomaticKeepAliveClientMixin {
  final _entries = <Map<String, dynamic>>[];
  final _scrollController = ScrollController();
  bool _loading = true;
  bool _hasMore = true;
  static const _pageSize = 50;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || (_loading && _entries.isNotEmpty)) return;
    setState(() => _loading = true);

    final rows = await widget.loader(_pageSize, _entries.length);

    if (mounted) {
      setState(() {
        _entries.addAll(rows);
        _hasMore = rows.length == _pageSize;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return const Center(child: Text('No words'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _entries.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _entries.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final entry = _entries[index];
        final headword = entry['headword'] as String? ?? '';
        final pos = entry['pos'] as String? ?? '';

        return ListTile(
          title: Text(headword, style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(pos, style: TextStyle(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.primary,
          )),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WordDetailScreen(entryRow: entry),
            ),
          ),
        );
      },
    );
  }
}
