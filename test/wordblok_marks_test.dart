// 11-22 성경나침반이 꾸밈을 살려 넣은 .scb 설교 — 열 때 편집기 서식으로, 저장할 때 다시 표시로
import 'package:bibleblok_app/services/wordblok_sermons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('꾸밈 표시 → 초안 HTML → 다시 표시', () {
    const text = '# 신을 신으라\n베드로가 **급히 일어나라** 하는 *말씀*을 <u>들었다</u> & 2 < 3\n\n그냥 줄';
    final html = textToDraftHtml(text);
    expect(html,
        '<h1>신을 신으라</h1><p>베드로가 <strong>급히 일어나라</strong> 하는 <em>말씀</em>을 <u>들었다</u> &amp; 2 &lt; 3</p><p>그냥 줄</p>');
    expect(draftHtmlToText(html), '# 신을 신으라\n베드로가 **급히 일어나라** 하는 *말씀*을 <u>들었다</u> & 2 < 3\n그냥 줄');
    // 꾸밈 없는 옛 글은 지금과 같음
    expect(textToDraftHtml('가\n나'), '<p>가</p><p>나</p>');
    expect(draftHtmlToText('<p style="color:red"><span style="font-size:2em">가</span></p><p>나</p>'), '가\n나');
  });
}
