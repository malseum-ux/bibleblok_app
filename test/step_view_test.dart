// 단계 화면 시험 — 화면을 실제로 그려 보고 버튼을 눌러 본다
import 'package:bibleblok_app/models/item.dart';
import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/step_view.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_fs.dart';

Future<(Store, Item)> _setup(WidgetTester tester) async {
  final store = Store(MemoryFs());
  await store.loadAll();
  final item = await store.createItem('sermon', {'date': '2026-09-21', 'title': '아브라함', 'passage': '창 12:1-4'}, '');
  await store.saveStep(item, 0, '첫 문단\n\n둘째 문단');
  final folder = FolderState()
    ..store = store
    ..status = FolderStatus.ready;
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(ProviderScope(
    overrides: [folderProvider.overrideWith((ref) => folder)],
    child: MaterialApp(
      theme: buildTheme(Brightness.light),
      localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
      home: Scaffold(
        body: StepView(item: item, lang: 'ko', bible: '개역개정성경', fontSize: 14, onFontSizeChange: (_) {}, isMobile: false, onGoToCell: (_) {}),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (store, item);
}

void main() {
  testWidgets('지시 항목 버튼을 누르면 항목 패널이 열린다', (tester) async {
    await _setup(tester);
    await tester.tap(find.textContaining('지시 항목'));
    await tester.pumpAndSettle();
    expect(find.text('전후 문맥'), findsOneWidget);
    expect(find.textContaining('추가 키워드나 지시사항'), findsOneWidget);
  });

  testWidgets('사용자 항목을 추가하면 저장되고 선택된다', (tester) async {
    final (store, _) = await _setup(tester);
    await tester.tap(find.textContaining('지시 항목'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('편집'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '청년 대상');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.customItemsFor('sermon', 'narrative').single.label, '청년 대상');
    expect(find.textContaining('지시 항목 5/5'), findsOneWidget);
  });

  testWidgets('설교문에 반영을 누르면 초안 끝에 붙는다', (tester) async {
    final (store, item) = await _setup(tester);
    await tester.tap(find.text('설교문에 반영'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(item.draft, '<p>첫 문단</p><p>둘째 문단</p>');
  });
}
