// 설교 설계도 — 자료 모양, 개요, 오른쪽 창 [설계도] 탭
import 'package:bibleblok_app/models/item.dart';
import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/step_view.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:bibleblok_app/widgets/sermon_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_fs.dart';

Future<(Store, Item)> _setup(WidgetTester tester) async {
  final store = Store(MemoryFs());
  await store.loadAll();
  final item = await store.createItem('sermon', {'date': '2026-11-22', 'title': '인간 욕망의 잔인함', 'passage': '삼하 13:1-22'}, '');
  await store.saveStep(item, 0, '다윗 가정의 비극. 암논의 욕망이 시작이다.');
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
  return (store, item);
}

void main() {
  test('처음 모양·번호·개요·저장 되읽기', () {
    final m = SermonMap.initial();
    expect(m.branches.map((b) => b.kind).toList(), ['bigidea', 'intro', 'body', 'body', 'body', 'conclusion', 'study']);
    final intro = m.branches[1], body2 = m.branches[3], concl = m.branches[5];
    expect(m.numberOf(intro), 1);
    expect(m.nameOf(body2, true), '본론 2');
    expect(m.numberOf(concl), 5);
    m.branches[0].thesis = '욕망은 사람을 잔인하게 만든다';
    intro.thesis = '다윗 가정의 비극';
    intro.cards.add(MapCard.fromText('다윗 가정의 비극. 암논의 욕망이 시작이다.', '1단계 서사적 해설'));
    intro.cards.first.children.add(MapCard(title: '욕망의 정의', source: '직접'));
    final o = m.outline(true);
    expect(o, contains('Big Idea: 욕망은 사람을 잔인하게 만든다'));
    expect(o, contains('1. 서론 — 다윗 가정의 비극'));
    expect(o, contains('1.1 다윗 가정의 비극. [1단계 서사적 해설]'));
    expect(o, contains('1.1.1 욕망의 정의 [직접]'));
    // 카드 옮기기
    final card = m.removeCard(intro.cards.first.id)!;
    body2.cards.add(card);
    expect(m.outline(true), contains('3.1 다윗 가정의 비극.'));
    // 저장 → 되읽기
    final again = SermonMap.fromJson(m.toJson());
    expect(again.outline(true), m.outline(true));
  });

  test('카드 제목은 첫 문장 앞부분', () {
    expect(shortTitle('다윗 가정의 비극. 그다음 이야기'), '다윗 가정의 비극.');
    expect(shortTitle('아주 아주 긴 첫 문장이라서 스물네 글자를 훌쩍 넘어가는 문장입니다').endsWith('…'), isTrue);
  });

  testWidgets('오른쪽 창 [설계도] 탭: 단계 글을 넣으면 카드가 생기고 설교 파일에 저장된다', (tester) async {
    final (store, item) = await _setup(tester);
    await tester.tap(find.byKey(const ValueKey('right-tab-map')));
    await tester.pumpAndSettle();
    expect(find.byType(SermonMapView), findsOneWidget);
    expect(find.text('인간 욕망의 잔인함'), findsOneWidget); // 가운데
    expect(find.textContaining('서론'), findsWidgets);
    final state = tester.state(find.byType(StepView)) as dynamic;
    final introId = (state.sermonMap as SermonMap).branches.firstWhere((b) => b.kind == 'intro').id;
    state.addToMap(introId, '다윗 가정의 비극. 암논의 욕망이 시작이다.');
    await tester.pump(const Duration(milliseconds: 600)); // 저장 기다리기
    await tester.pumpAndSettle();
    expect(find.textContaining('다윗 가정의 비극.'), findsWidgets);
    expect(find.textContaining('1단계 서사적 해설'), findsWidgets);
    expect(item.map, isNotNull);
    final saved = SermonMap.fromJson(item.map);
    expect(saved.branches.firstWhere((b) => b.kind == 'intro').cards.single.source, '1단계 서사적 해설');
    // 순서 보기
    await tester.tap(find.text('순서 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.1 다윗 가정의 비극.'), findsOneWidget);
    // 개요로 붙이기 → 초안 탭으로 가서 초안 끝에 들어간다
    await tester.tap(find.text('개요로 붙이기'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(item.draft, contains('1. 서론'));
    expect(find.byType(SermonMapView), findsNothing);
    expect(store.items['sermon']!.single.map, isNotNull);
  });

  Future<SermonMap> pumpMap(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final m = SermonMap.initial();
    final intro = m.branches[1];
    intro.cards.addAll([MapCard(title: '첫째 카드', source: '직접'), MapCard(title: '둘째 카드', source: '직접')]);
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(
        body: SermonMapView(map: m, lang: 'ko', title: '제목', passage: '삼하 13:1-22', onChanged: (_) {}, onPasteOutline: () {}, onAiWrite: (_, _) {}),
      ),
    ));
    await tester.pumpAndSettle();
    return m;
  }

  Future<void> dragTo(WidgetTester tester, Finder from, Offset to) async {
    final g = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 50));
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveTo(to);
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('카드 위에 놓으면 하위 가지, 카드 사이에 놓으면 그 자리', (tester) async {
    final m = await pumpMap(tester);
    final intro = m.branches[1];
    final a = intro.cards[0], b = intro.cards[1];
    // 둘째 카드를 첫째 카드 위에 → 하위 가지
    await dragTo(tester, find.byKey(ValueKey('map-card-${b.id}')), tester.getCenter(find.byKey(ValueKey('map-card-${a.id}'))));
    expect(intro.cards.map((c) => c.title).toList(), ['첫째 카드']);
    expect(a.children.single.title, '둘째 카드');
    expect(find.textContaining('1.1.1 둘째 카드'), findsOneWidget);
    // 하위 가지를 다시 첫째 카드 앞 사이로 → 같은 줄 맨 앞
    await dragTo(tester, find.byKey(ValueKey('map-card-${b.id}')), tester.getCenter(find.byKey(ValueKey('map-gap-${identityHashCode(intro.cards)}-0'))));
    expect(intro.cards.map((c) => c.title).toList(), ['둘째 카드', '첫째 카드']);
    expect(a.children, isEmpty);
  });

  testWidgets('배치 고르기: 오른쪽으로 바꾸면 기억한다', (tester) async {
    await pumpMap(tester);
    final infoBefore = tester.getCenter(find.text('설교 정보')).dx;
    final kmBefore = tester.getCenter(find.textContaining('추가 공부 주제')).dx;
    expect(kmBefore < infoBefore, isTrue); // 양쪽: 추가 공부 주제는 왼쪽
    await tester.tap(find.byKey(const ValueKey('map-layout-right')));
    await tester.pumpAndSettle();
    final info = tester.getTopLeft(find.text('설교 정보')).dx;
    final km = tester.getTopLeft(find.textContaining('추가 공부 주제')).dx;
    expect((km - info).abs() < 2, isTrue); // 오른쪽: 이름표가 모두 같은 줄(왼쪽 끝)에 위→아래
    expect(tester.getTopLeft(find.textContaining('추가 공부 주제')).dy > tester.getTopLeft(find.text('설교 정보')).dy, isTrue);
    expect((await SharedPreferences.getInstance()).getString('bibleblok-map-layout'), 'right');
    await tester.tap(find.byKey(const ValueKey('map-fit')));
    await tester.pumpAndSettle();
  });

  testWidgets('가지 메뉴 붙여넣기: 복사한 글이 카드로 들어간다', (tester) async {
    final m = await pumpMap(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': '복사한 글입니다. 둘째 문장'};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final concl = m.branches.firstWhere((b) => b.kind == 'conclusion');
    await tester.tap(find.descendant(of: find.byKey(ValueKey('map-branch-menu-${concl.id}')), matching: find.byType(Icon)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('붙여넣기').last);
    await tester.pumpAndSettle();
    expect(concl.cards.single.title, '복사한 글입니다.');
    expect(concl.cards.single.source, '붙여넣기');
  });
}
