// 설교 메모판 — 자료 모양, AI 에게 줄 글, 오른쪽 창 [메모판] 탭 (새 메모·잇기·묶기·설계도로 보내기·AI 정리 넣기)
import 'package:bibleblok_app/models/item.dart';
import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/step_view.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:bibleblok_app/widgets/sermon_board.dart';
import 'package:bibleblok_app/widgets/sermon_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_fs.dart';

Future<(Store, Item)> _setup(WidgetTester tester, {Map<String, dynamic>? board}) async {
  final store = Store(MemoryFs());
  await store.loadAll();
  final item = await store.createItem('sermon', {'date': '2026-11-29', 'title': '깨어 있으라', 'passage': '막 13:24-37'}, '');
  if (board != null) {
    item.board = board;
    await store.saveItem(item);
  }
  final folder = FolderState()
    ..store = store
    ..status = FolderStatus.ready;
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
  await tester.tap(find.byKey(const ValueKey('right-tab-board')));
  await tester.pumpAndSettle();
  return (store, item);
}

Map<String, dynamic> _twoNotes() => {
      'notes': [
        {'id': 'a', 'text': '무화과나무의 비유', 'x': 40, 'y': 40},
        {'id': 'b', 'text': '그날과 그때는 아무도 모른다', 'x': 320, 'y': 40},
      ],
    };

/// 메모 한 번 누르기 (두 번 누르기를 기다리는 시간까지)
Future<void> _tapNote(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('board-note-$id')));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('저장 되읽기·정리·AI 에게 줄 글', () {
    final b = SermonBoard(notes: [
      BoardNote(id: 'a', text: '깨어 있으라', x: 300, y: 40),
      BoardNote(id: 'b', text: '주인이 언제 올지 모른다', x: 40, y: 40, source: '1단계'),
      BoardNote(id: 'c', text: '문지기의 사명', x: 40, y: 300),
    ]);
    b.links.add(BoardLink('b', 'a', arrow: true));
    b.links.add(BoardLink('a', 'zz')); // 없는 메모 — 정리 때 빠진다
    b.groups.add(BoardGroup(title: '종말 의식', noteIds: ['a', 'b']));
    final again = SermonBoard.fromJson(b.toJson());
    expect(again.notes.length, 3);
    expect(again.links.length, 1);
    expect(again.groups.single.title, '종말 의식');
    final (text, back) = again.describe();
    // 위→아래, 왼쪽→오른쪽 순서로 m1, m2…
    expect(text, contains('m1: 주인이 언제 올지 모른다 [1단계]'));
    expect(text, contains('m2: 깨어 있으라'));
    expect(text, contains('m3: 문지기의 사명'));
    expect(text, contains('종말 의식: m1, m2'));
    expect(text, contains('m1 → m2'));
    expect(back['m3'], 'c');
    // 고른 메모만
    final (part, back2) = again.describe(only: {'c'});
    expect(back2.length, 1);
    expect(part, isNot(contains('주인이')));
    // 지우면 선·묶음도 정리
    again.removeNotes(['a']);
    expect(again.links, isEmpty);
    expect(again.groups.single.noteIds, ['b']);
  });

  testWidgets('[메모판] 탭 — 새 메모 쓰기가 파일에 저장된다', (tester) async {
    final (store, item) = await _setup(tester);
    expect(find.textContaining('빈 곳을 두 번 누르거나'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('board-edit-text')), '깨어 있는 삶이란 무엇인가');
    await tester.tap(find.byKey(const ValueKey('board-edit-ok')));
    await tester.pumpAndSettle();
    expect(find.text('깨어 있는 삶이란 무엇인가'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    final saved = SermonBoard.fromJson(item.board);
    expect(saved.notes.single.text, '깨어 있는 삶이란 무엇인가');
    expect(store.items['sermon']!.first.board, isNotNull);
  });

  testWidgets('둘 고르고 잇기·화살표·묶기·지우기', (tester) async {
    final (_, item) = await _setup(tester, board: _twoNotes());
    await _tapNote(tester, 'a');
    await _tapNote(tester, 'b');
    expect(find.text('메모 2개'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('board-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-arrow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('board-group')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    var saved = SermonBoard.fromJson(item.board);
    expect(saved.links.single.arrow, isTrue);
    expect(saved.groups.single.noteIds.toSet(), {'a', 'b'});
    expect(find.text('묶음 (눌러 이름 짓기)'), findsOneWidget);
    // 끌어 옮기기 — 두 메모를 함께
    await tester.drag(find.byKey(const ValueKey('board-note-a')), const Offset(0, 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    saved = SermonBoard.fromJson(item.board);
    expect(saved.note('a')!.y, greaterThan(100));
    expect(saved.note('b')!.y, greaterThan(100));
    await tester.tap(find.byKey(const ValueKey('board-delete')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    saved = SermonBoard.fromJson(item.board);
    expect(saved.notes, isEmpty);
  });

  testWidgets('고른 메모를 설계도 가지로 보내기', (tester) async {
    final (_, item) = await _setup(tester, board: _twoNotes());
    await _tapNote(tester, 'a');
    await tester.tap(find.byKey(const ValueKey('board-send-map')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('서론').last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final map = SermonMap.fromJson(item.map);
    final intro = map.branches.firstWhere((b) => b.kind == 'intro');
    expect(intro.cards.single.text, '무화과나무의 비유');
    expect(intro.cards.single.source, '메모판');
    // 메모판에는 그대로 남는다
    expect(SermonBoard.fromJson(item.board).notes.length, 2);
  });

  testWidgets('AI 정리 결과 넣기 — 대지는 빈 가지에만, 본론이 모자라면 더한다', (tester) async {
    final (_, item) = await _setup(tester, board: _twoNotes());
    final state = tester.state(find.byType(StepView)) as dynamic;
    state.applyBoardPlan({
      'bigidea': '깨어 있는 사람이 주님을 맞는다',
      'parts': [
        {'kind': 'intro', 'thesis': '무화과나무를 보라', 'notes': ['m1']},
        {'kind': 'body', 'thesis': '1', 'notes': []},
        {'kind': 'body', 'thesis': '2', 'notes': []},
        {'kind': 'body', 'thesis': '3', 'notes': []},
        {'kind': 'body', 'thesis': '넷째', 'notes': ['m2']},
      ],
      'study': [],
    }, {'m1': 'a', 'm2': 'b'});
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    final map = SermonMap.fromJson(item.map);
    expect(map.branches.firstWhere((b) => b.kind == 'bigidea').thesis, '깨어 있는 사람이 주님을 맞는다');
    final bodies = map.ordered.where((b) => b.kind == 'body').toList();
    expect(bodies.length, 4);
    expect(bodies[3].thesis, '넷째');
    expect(bodies[3].cards.single.text, '그날과 그때는 아무도 모른다');
    expect(map.branches.firstWhere((b) => b.kind == 'intro').cards.single.text, '무화과나무의 비유');
    // 설계도 탭으로 넘어간다
    expect(find.byKey(const ValueKey('sermon-map')), findsOneWidget);
  });
}
