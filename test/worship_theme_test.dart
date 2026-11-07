// 예배인도 정보: 예배 주제 칸이 성서정과 옆에 있고, 저장하면 함께 넘어간다
import 'package:bibleblok_app/theme/app_colors.dart';
import 'package:bibleblok_app/widgets/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('예배 주제를 넣고 저장하면 emphasis 로 넘어간다', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, String?>? saved;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: WorshipForm(lang: 'ko', bible: '개역개정', onSave: (d) async { saved = d; }))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('예배 주제'), findsOneWidget);
    // 넓은 화면: 성서정과와 예배 주제가 같은 줄
    final lectY = tester.getTopLeft(find.text('성서정과 본문')).dy;
    final themeY = tester.getTopLeft(find.text('예배 주제')).dy;
    expect(themeY, lectY);
    await tester.enterText(find.descendant(of: find.byKey(const ValueKey('worship-theme')), matching: find.byType(TextField)), ' 추수감사주일 ');
    await tester.tap(find.text('저장'));
    await tester.pump();
    expect(saved?['emphasis'], '추수감사주일');
  });
}
