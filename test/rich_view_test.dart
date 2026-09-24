// 편집기 시험 — // 명령, 도구 막대
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:bibleblok_app/widgets/rich_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(GlobalKey<RichViewState>, List<SlashCommand>, List<String>)> _pump(WidgetTester tester, String source) async {
  final key = GlobalKey<RichViewState>();
  final cmds = <SlashCommand>[];
  final changes = <String>[];
  tester.view.physicalSize = const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
    home: Scaffold(
      body: RichView(
        key: key,
        source: source,
        fontSize: 14,
        editable: true,
        autoFocus: true,
        showToolbar: true,
        onChanged: changes.add,
        onEnterCommand: (cmd) async => cmds.add(cmd),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (key, cmds, changes);
}

Future<void> _typeAtEndAndEnter(WidgetTester tester, GlobalKey<RichViewState> key, String text) async {
  final ctrl = key.currentState!.controller;
  final end = ctrl.document.length - 1;
  ctrl.replaceText(end, 0, text, TextSelection.collapsed(offset: end + text.length));
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  for (final (typed, mode, instruction) in [
    ('//-결론 한 문단', 'research', '결론 한 문단'),
    ('//+결론 한 문단', 'theological', '결론 한 문단'),
    ('//결론 한 문단', 'fresh', '결론 한 문단'),
  ]) {
    testWidgets('$typed → $mode', (tester) async {
      final (key, cmds, _) = await _pump(tester, '<p>첫 문단 <strong>굵게</strong></p><p></p>');
      await _typeAtEndAndEnter(tester, key, typed);
      expect(cmds.single.mode, mode);
      expect(cmds.single.instruction, instruction);
      expect(cmds.single.contextBefore, '첫 문단 굵게\n');
      // 명령 글자는 지워진다
      expect(key.currentState!.controller.document.toPlainText(), '첫 문단 굵게\n\n');
    });
  }

  testWidgets('AI 글이 명령 자리에 들어가고, 앞 문단의 굵게는 그대로다', (tester) async {
    final (key, cmds, changes) = await _pump(tester, '<p>첫 문단 <strong>굵게</strong></p><p></p>');
    await _typeAtEndAndEnter(tester, key, '//-결론');
    cmds.single.write('생성 중');
    cmds.single.write('생성 완료된 결론입니다.');
    await tester.pumpAndSettle();
    expect(key.currentState!.controller.document.toPlainText(), '첫 문단 굵게\n생성 완료된 결론입니다.\n');
    expect(changes.last, '<p>첫 문단 <strong>굵게</strong></p><p>생성 완료된 결론입니다.</p>');
  });

  testWidgets('// 가 없는 줄의 Enter 는 그냥 줄바꿈', (tester) async {
    final (key, cmds, _) = await _pump(tester, '<p>문단</p>');
    await _typeAtEndAndEnter(tester, key, ' 이어서');
    expect(cmds, isEmpty);
  });

  testWidgets('도구 막대 B 를 누르면 선택한 글이 굵게', (tester) async {
    final (key, _, changes) = await _pump(tester, '<p>가나다라</p>');
    final ctrl = key.currentState!.controller;
    ctrl.updateSelection(const TextSelection(baseOffset: 0, extentOffset: 2), ChangeSource.local);
    await tester.pump();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(changes.last, '<p><strong>가나</strong>다라</p>');
    await tester.tap(find.text('A+'));
    await tester.pumpAndSettle();
    expect(changes.last, '<p><span style="font-size: 1.2em"><strong>가나</strong></span>다라</p>');
  });
}
