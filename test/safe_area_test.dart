// 안전 영역 — iPhone 노치·홈 막대가 있는 화면에서 헤더와 내용이 가려지지 않는지
import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/home_screen.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_fs.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  final store = Store(MemoryFs());
  await store.loadAll();
  final folder = FolderState()
    ..store = store
    ..status = FolderStatus.ready;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  // iPhone 15 과 비슷한 여백: 위 59(다이내믹 아일랜드), 아래 34(홈 막대)
  tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
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

void main() {
  testWidgets('휴대폰: 헤더가 상태 표시줄 아래에서 시작한다', (tester) async {
    await _pump(tester, const Size(393, 852));
    final headerTab = find.text('설교작성').first;
    expect(tester.getTopLeft(headerTab).dy, greaterThanOrEqualTo(59));
  });

  testWidgets('패드: 헤더가 상태 표시줄 아래에서 시작한다', (tester) async {
    await _pump(tester, const Size(1024, 1366));
    final headerTab = find.text('설교작성').first;
    expect(tester.getTopLeft(headerTab).dy, greaterThanOrEqualTo(59));
  });
}
