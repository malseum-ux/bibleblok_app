// 글꼴 크기(기본 15·설정에 저장·숫자 표시)와 // 지시문 안내
import 'dart:convert';

import 'package:bibleblok_app/providers/app_state.dart';
import 'package:bibleblok_app/screens/home_screen.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:bibleblok_app/widgets/step_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_fs.dart';

Future<Store> _pumpHome(WidgetTester tester) async {
  final store = Store(MemoryFs());
  await store.loadAll();
  await store.createItem('sermon', {'date': '2026-10-11', 'title': '아브라함', 'passage': '창 12:1-4'}, '');
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
  test('글꼴 크기: 기본 15, 바꾸면 저장되고 11~24 사이로 묶인다', () async {
    SharedPreferences.setMockInitialValues({});
    final n = SettingsNotifier();
    await n.init();
    expect(n.state.fontSize, 15);
    await n.setFontSize(18);
    expect(jsonDecode((await SharedPreferences.getInstance()).getString('bibleblok-settings')!)['fontSize'], 18);
    await n.setFontSize(40);
    expect(n.state.fontSize, 24);
    final again = SettingsNotifier();
    await again.init();
    expect(again.state.fontSize, 24);
  });

  testWidgets('A-·A+ 사이에 지금 크기가 보이고, 누르면 바뀐다', (tester) async {
    double size = 15;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) => FontSizeButtons(fontSize: size, onChange: (v) => setState(() => size = v)))),
    ));
    expect(find.text('15'), findsOneWidget);
    await tester.tap(find.text('A+'));
    await tester.pump();
    expect(find.text('16'), findsOneWidget);
  });

  testWidgets('설교작성: 우측 초안창의 "지시문 안내"를 누르면 안내가 펼쳐진다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pumpHome(tester);
    await tester.tap(find.textContaining('아브라함').first);
    await tester.pumpAndSettle();
    expect(find.byType(SlashHelpPanel), findsNothing);
    await tester.tap(find.text('지시문 안내'));
    await tester.pumpAndSettle();
    expect(find.byType(SlashHelpPanel), findsOneWidget);
    expect(find.text('//+ 지시'), findsOneWidget);
  });
}
