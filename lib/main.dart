import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'constants.dart';
import 'providers/app_state.dart';
import 'providers/auth.dart';
import 'screens/auth_gate.dart';
import 'screens/folder_gate.dart';
import 'screens/home_screen.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);
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
    // 로그인 → 저장 폴더 → 메인 순서
    final user = ref.watch(authUserProvider);
    final Widget home = user.isLoading && !user.hasValue
        ? const SizedBox()
        : (user.valueOrNull == null ? const AuthGate() : (ready ? const HomeScreen() : const FolderGate()));
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
      // 편집기(flutter_quill)와 날짜 달력이 쓰는 언어 설정
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('ko'), Locale('en')],
      locale: Locale(settings.lang),
      home: home,
    );
  }
}
