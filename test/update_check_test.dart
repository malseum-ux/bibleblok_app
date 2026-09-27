// 업데이트 확인 — 버전 비교, 켤 때 설정 버튼 점, 설정 화면 "앱 정보"
import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/home_screen.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/services/update_check.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:bibleblok_app/widgets/settings_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_fs.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  final store = Store(MemoryFs());
  await store.loadAll();
  final folder = FolderState()
    ..store = store
    ..status = FolderStatus.ready;
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [folderProvider.overrideWith((ref) => folder)],
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      home: const HomeScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 설정 화면을 맨 아래 "앱 정보"까지 내린다
Future<void> _scrollToAbout(WidgetTester tester) => tester.scrollUntilVisible(
      find.text('업데이트 확인'),
      300,
      scrollable: find.descendant(of: find.byType(SettingsPanel), matching: find.byType(Scrollable)).first,
    );

void main() {
  tearDown(() => debugCheckForUpdate = null);

  test('버전 비교: 숫자 단위로, 빌드 번호는 무시', () {
    expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.10.0', '1.9.9'), isTrue);
    expect(isNewerVersion('2.0', '1.9.9'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('1.0.0+5', '1.0.0+1'), isFalse);
    expect(isNewerVersion('0.9.0', '1.0.0'), isFalse);
  });

  for (final (platform, button) in [(TargetPlatform.macOS, '새 버전 받기'), (TargetPlatform.android, '스토어에서 업데이트')]) {
    testWidgets('새 버전이 있으면 설정 버튼에 점, 설정 화면에 안내와 "$button" (${platform.name})', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      debugCheckForUpdate = () async => const UpdateInfo(current: '1.0.0', latest: '1.1.0', url: 'https://example.com/app');
      await _pumpHome(tester);
      expect(find.byTooltip('설정 — 새 버전이 있습니다'), findsOneWidget);
      await tester.tap(find.byTooltip('설정 — 새 버전이 있습니다'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(button),
        300,
        scrollable: find.descendant(of: find.byType(SettingsPanel), matching: find.byType(Scrollable)).first,
      );
      expect(find.text('새 버전(1.1.0)이 있습니다.'), findsOneWidget);
      expect(find.text(button), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('최신이면 점이 없고, 확인 버튼을 누르면 "최신 버전입니다"', (tester) async {
    debugCheckForUpdate = () async => const UpdateInfo(current: '1.0.0', latest: '1.0.0');
    await _pumpHome(tester);
    expect(find.byTooltip('설정'), findsOneWidget);
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await _scrollToAbout(tester);
    await tester.tap(find.text('업데이트 확인'));
    await tester.pumpAndSettle();
    expect(find.text('최신 버전입니다.'), findsOneWidget);
  });
}
