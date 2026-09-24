import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'constants.dart';
import 'providers/app_state.dart';
import 'screens/folder_gate.dart';
import 'screens/home_screen.dart';
import 'theme/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: BibleBlokApp()));
}

class BibleBlokApp extends ConsumerStatefulWidget {
  const BibleBlokApp({super.key});

  @override
  ConsumerState<BibleBlokApp> createState() => _BibleBlokAppState();
}

class _BibleBlokAppState extends ConsumerState<BibleBlokApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(settingsProvider.notifier).init();
      await ref.read(folderProvider).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final ready = ref.watch(folderProvider.select((f) => f.status == FolderStatus.ready));
    return MaterialApp(
      title: appName(settings.lang),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (settings.theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: ready ? const HomeScreen() : const FolderGate(),
    );
  }
}
