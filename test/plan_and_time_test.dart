// 설교 계획 탭과 예상 설교 시간
import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/home_screen.dart';
import 'package:bibleblok_app/screens/plan_view.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_fs.dart';

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<Store> _pumpHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
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
  return store;
}

void main() {
  test('예상 설교 시간: 글자 수 ÷ 설교 속도', () {
    expect(sermonMinutes(7500, 300), 25);
    expect(sermonMinutes(100, 300), 1);
    expect(sermonMinutes(0, 300), 0);
    expect(sermonMinutes(7000, 350), 20);
  });

  test('그해 주일은 52~53개이고 모두 일요일', () {
    final s = sundaysOf(2026);
    expect(s.length, inInclusiveRange(52, 53));
    expect(s.every((d) => d.weekday == DateTime.sunday && d.year == 2026), isTrue);
  });

  testWidgets('설교 계획: 이번 주 설교가 진행 상태와 함께 보이고, 누르면 그 설교가 열린다', (tester) async {
    final store = await _pumpHome(tester);
    final now = DateTime.now();
    final sunday = DateTime(now.year, now.month, now.day - now.weekday % 7);
    final item = await store.createItem('sermon', {'date': _ymd(sunday), 'title': '아브라함의 믿음', 'passage': '창 12:1-4'}, '');
    await store.saveStep(item, 0, '서사 연구');
    await tester.tap(find.text('설교 계획'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanView), findsOneWidget);
    expect(find.text('아브라함의 믿음'), findsOneWidget);
    expect(find.text('연구 1/10'), findsOneWidget);
    await tester.tap(find.text('아브라함의 믿음'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanView), findsNothing);
    expect(find.textContaining('설교문'), findsWidgets); // 설교작성 화면(우측 초안창)
  });

  testWidgets('설교 계획: 빈 주일의 "+ 새 설교"를 누르면 그 날짜로 설교가 만들어진다', (tester) async {
    final store = await _pumpHome(tester);
    await tester.tap(find.text('설교 계획'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('+ 새 설교').first); // 이번 주로 스크롤돼 있어 1월 칸을 화면 안으로
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ 새 설교').first);
    await tester.pumpAndSettle();
    final created = store.items['sermon']!.single;
    expect(DateTime.parse(created.date!).weekday, DateTime.sunday);
    expect(find.byType(PlanView), findsNothing);
  });

  testWidgets('설교 시간 버튼: 초안이 있으면 "약 N분", 누르면 꺼진다', (tester) async {
    final store = await _pumpHome(tester);
    final item = await store.createItem('sermon', {'date': '2026-10-18', 'title': '시험 설교'}, '');
    item.draft = '<p>${'가' * 600}</p>';
    await store.saveItem(item);
    await tester.tap(find.text('설교 계획'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설교작성'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('시험 설교').first);
    await tester.pumpAndSettle();
    expect(find.text('약 2분'), findsOneWidget);
    await tester.tap(find.text('약 2분'));
    await tester.pumpAndSettle();
    expect(find.text('설교 시간'), findsOneWidget);
  });
}
