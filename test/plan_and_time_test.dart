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

  test('달력 날짜: 일요일에 시작해 토요일에 끝나고 그달을 모두 담는다', () {
    for (final (y, m) in [(2026, 10), (2026, 2), (2027, 1), (2026, 8)]) {
      final d = calendarDays(y, m);
      expect(d.length % 7, 0);
      expect(d.first.weekday, DateTime.sunday);
      expect(d.last.weekday, DateTime.saturday);
      expect(d.where((x) => x.month == m).length, DateTime(y, m + 1, 0).day);
    }
  });

  testWidgets('설교 계획 달력: 이번 주 설교가 진행 상태와 함께 보이고, 누르면 그 설교가 열린다', (tester) async {
    final store = await _pumpHome(tester);
    final now = DateTime.now();
    final sunday = DateTime(now.year, now.month, now.day - now.weekday % 7);
    final item = await store.createItem('sermon', {'date': _ymd(sunday), 'title': '아브라함의 믿음', 'passage': '창 12:1-4'}, '');
    await store.saveStep(item, 0, '서사 연구');
    await tester.tap(find.text('설교 달력'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanView), findsOneWidget);
    expect(find.text('창 12:1-4'), findsOneWidget);
    expect(find.text('연구 1/10'), findsOneWidget);
    await tester.tap(find.text('창 12:1-4'));
    await tester.pumpAndSettle();
    expect(find.byType(PlanView), findsNothing);
    expect(find.textContaining('설교문'), findsWidgets); // 설교작성 화면(우측 초안창)
  });

  testWidgets('설교 계획 달력: 빈 주일 칸을 누르면 그 날짜로 주일설교가 만들어진다', (tester) async {
    final store = await _pumpHome(tester);
    await tester.tap(find.text('설교 달력'));
    await tester.pumpAndSettle();
    final first = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final sunday = DateTime(first.year, first.month, 1 + (7 - first.weekday % 7) % 7);
    await tester.tap(find.byKey(ValueKey('plan-${_ymd(sunday)}')));
    await tester.pumpAndSettle();
    final created = store.items['sermon']!.single;
    expect(created.date, _ymd(sunday));
    expect(store.items['dawn']!, isEmpty);
    expect(find.byType(PlanView), findsNothing);
  });

  testWidgets('설교 계획 달력: 평일 칸을 누르면 새벽설교, 이미 있으면 그 새벽설교가 열린다', (tester) async {
    final store = await _pumpHome(tester);
    final first = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final monday = DateTime(first.year, first.month, 1 + (8 - first.weekday) % 7);
    final cellDate = DateTime(monday.year, monday.month, monday.day - 1); // 그 앞 주일
    await store.createItem('worship', {'date': _ymd(cellDate)}, '');
    await store.createItem('cell', {'date': _ymd(cellDate)}, '');
    await tester.tap(find.text('설교 달력'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(PlanView), matching: find.text('예배인도')), findsOneWidget);
    expect(find.text('교재작성 O'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('plan-${_ymd(monday)}')));
    await tester.pumpAndSettle();
    final created = store.items['dawn']!.single;
    expect(created.date, _ymd(monday));
    expect(store.items['sermon']!, isEmpty);
    await tester.tap(find.text('설교 달력'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('plan-${_ymd(monday)}')));
    await tester.pumpAndSettle();
    expect(store.items['dawn']!.length, 1); // 새로 만들지 않고 연다
  });

  testWidgets('설교 계획 달력: 창이 900px 아래여도 달력 폭이 넉넉하면 칸 안에 글자로 보인다', (tester) async {
    final store = await _pumpHome(tester);
    tester.view.physicalSize = const Size(880, 900);
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final sunday = DateTime(now.year, now.month, now.day - now.weekday % 7);
    await store.createItem('sermon', {'date': _ymd(sunday), 'passage': '창 12:1-4'}, '');
    await tester.tap(find.text('설교 달력'));
    await tester.pumpAndSettle();
    expect(find.text('창 12:1-4'), findsOneWidget);
    expect(find.text('눌러서 주일설교로'), findsNothing); // 휴대폰 펼침 없음
  });

  testWidgets('목록 정렬: 고른 정렬이 탭마다 따로 저장된다', (tester) async {
    await _pumpHome(tester);
    await tester.tap(find.text('설교작성'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('날짜↓'));
    await tester.pumpAndSettle();
    expect(find.text('날짜↑'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bibleblok-sort-sermon'), 'date-asc');
    await tester.tap(find.text('예배인도'));
    await tester.pumpAndSettle();
    expect(find.text('날짜↓'), findsOneWidget); // 다른 탭은 기본값
    await tester.tap(find.text('설교작성'));
    await tester.pumpAndSettle();
    expect(find.text('날짜↑'), findsOneWidget); // 돌아오면 기억한 정렬
  });

  testWidgets('설교 시간 버튼: 초안이 있으면 "약 N분", 누르면 꺼진다', (tester) async {
    final store = await _pumpHome(tester);
    final item = await store.createItem('sermon', {'date': '2026-10-18', 'title': '시험 설교'}, '');
    item.draft = '<p>${'가' * 600}</p>';
    await store.saveItem(item);
    await tester.tap(find.text('설교 달력'));
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
