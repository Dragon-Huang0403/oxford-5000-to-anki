import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database_provider.dart';
import 'core/sync/sync_provider.dart';
import 'features/dictionary/presentation/dictionary_screen.dart';

/// Reactive theme mode provider
final themeModeProvider = FutureProvider<ThemeMode>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final mode = await dao.getThemeMode();
  return switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
});

class OxfordDictionaryApp extends ConsumerStatefulWidget {
  const OxfordDictionaryApp({super.key});

  @override
  ConsumerState<OxfordDictionaryApp> createState() => _OxfordDictionaryAppState();
}

class _OxfordDictionaryAppState extends ConsumerState<OxfordDictionaryApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Pull remote changes when app comes to foreground
      ref.read(syncServiceProvider)?.pullSearchHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider).when(
      data: (mode) => mode,
      loading: () => ThemeMode.system,
      error: (_, _) => ThemeMode.system,
    );

    return MaterialApp(
      title: 'Deckionary',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0057A8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6AB0F5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const DictionaryScreen(),
    );
  }
}
