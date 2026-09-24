// 예배·새벽·교재 화면이 오류 없이 그려지는지
import 'package:bibleblok_app/models/item.dart';
import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/cell_view.dart';
import 'package:bibleblok_app/screens/step_view.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_fs.dart';

Future<void> _pump(WidgetTester tester, Store store, Widget Function(Item) build, Item item, {bool mobile = false}) async {
  final folder = FolderState()
    ..store = store
    ..status = FolderStatus.ready;
  tester.view.physicalSize = mobile ? const Size(390, 800) : const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ProviderScope(
    overrides: [folderProvider.overrideWith((ref) => folder)],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      home: Scaffold(body: build(item)),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final tab in ['worship', 'dawn']) {
    testWidgets('$tab 단계 화면', (tester) async {
      final store = Store(MemoryFs());
      await store.loadAll();
      final item = await store.createItem(tab, {'date': '2026-09-21', 'passage': '시 23', 'season': '일반 주일'}, '');
      await store.saveStep(item, 0, '<p>통합 결과</p>');
      await _pump(tester, store, (i) => StepView(item: i, lang: 'ko', bible: '개역개정성경', fontSize: 14, onFontSizeChange: (_) {}, isMobile: false, onGoToCell: (_) {}), item);
      expect(find.textContaining('통합 결과', findRichText: true), findsWidgets);
      expect(find.text('설교문 초안'.toUpperCase()), findsNothing); // 초안 창은 설교 탭만
      await tester.tap(find.textContaining('지시 항목'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('교재 화면 + 같은 본문 설교 뱃지', (tester) async {
    final store = Store(MemoryFs());
    await store.loadAll();
    await store.createItem('sermon', {'date': '2026-09-21', 'title': '아브라함', 'passage': '창세기 12:1-4'}, '');
    final cell = await store.createItem('cell', {'passage': '창세기 12:1-4'}, '');
    await _pump(tester, store, (i) => CellView(item: i, lang: 'ko', bible: '개역개정성경', fontSize: 14, onFontSizeChange: (_) {}, isMobile: false, onGoToSermon: (_) {}), cell);
    expect(find.text('설교'), findsOneWidget);
    expect(find.textContaining('AI 생성 버튼을 눌러 나눔 교재을 생성합니다'), findsOneWidget);
    await tester.tap(find.textContaining('지시 항목'));
    await tester.pumpAndSettle();
    expect(find.text('편집'), findsOneWidget);
  });

  testWidgets('설교 화면 — 휴대폰 폭 (AI 결과 / 설교 초안 전환)', (tester) async {
    final store = Store(MemoryFs());
    await store.loadAll();
    final item = await store.createItem('sermon', {'date': '2026-09-21', 'title': 'A', 'passage': '창 1:1'}, '');
    await _pump(tester, store, (i) => StepView(item: i, lang: 'ko', bible: '개역개정성경', fontSize: 14, onFontSizeChange: (_) {}, isMobile: true, onGoToCell: (_) {}), item, mobile: true);
    expect(find.text('AI 결과'), findsOneWidget);
    await tester.tap(find.text('설교 초안'));
    await tester.pumpAndSettle();
    expect(find.text('클릭하여 설교문 초안을 작성하세요'), findsOneWidget);
  });
}
