// 글 형식 변환 시험 — 웹 편집기(TipTap)가 저장한 HTML 을 그대로 읽고 되쓸 수 있는지
import 'package:bibleblok_app/services/rich_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('문단이 따로 유지된다', () {
    final d = docFromSource('<p>첫 문단입니다.</p><p>둘째 문단입니다.</p>');
    expect(d.toPlainText(), '첫 문단입니다.\n둘째 문단입니다.\n');
  });

  test('일반 글은 빈 줄을 빼고 줄마다 문단', () {
    final d = docFromSource('1. 전후 문맥\n\n바벨탑 사건 이후\n\n\n2. 위치');
    expect(d.toPlainText(), '1. 전후 문맥\n바벨탑 사건 이후\n2. 위치\n');
  });

  test('TipTap 서식이 그대로 되살아난다 (읽고 다시 쓰기)', () {
    const src = '<p>원어 해설 <strong>굵은 글</strong> 과 <span style="color: #dc2626">빨간 글</span></p>'
        '<p style="text-align: center">가운데 정렬 <em>기울임</em> <u>밑줄</u></p>'
        '<p><span style="font-size: 1.2em">큰 글</span> <span style="font-size: 0.85em">작은 글</span></p>'
        '<p></p>'
        '<ul><li><p>항목 하나</p></li><li><p>항목 둘</p></li></ul>'
        '<h2>소제목</h2>';
    final html = htmlFromDoc(docFromSource(src));
    expect(html, src);
  });

  test('br 은 줄을 나눈다', () {
    expect(docFromSource('<p>가<br>나</p>').toPlainText(), '가\n나\n');
  });

  test('글자만 뽑기', () {
    expect(stripHtml('<p>하나 <strong>둘</strong></p><p>셋</p>'), '하나 둘\n셋');
    expect(stripHtml('그냥 글'), '그냥 글');
  });

  test('특수 문자는 안전하게', () {
    final html = htmlFromDoc(docFromSource('<p>a &lt; b &amp; c</p>'));
    expect(html, '<p>a &lt; b &amp; c</p>');
  });
}
