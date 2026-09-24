// 프롬프트 만들기 검사 — 네트워크 없이 buildXxxPrompt 만 확인한다
import 'package:bibleblok_app/services/hymns.dart';
import 'package:bibleblok_app/services/prompts.dart';
import 'package:bibleblok_app/services/worship_verses.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildSermonStepPrompt', () {
    test('message 단계에 본문과 항목이 들어간다', () {
      final b = buildSermonStepPrompt('message', '요 3:16', '', 'ko', '', '');
      expect(b.prompt, startsWith('\n앞서 분석한 내용을 바탕으로'));
      expect(b.prompt, contains('본문: 요 3:16'));
      expect(b.prompt, contains('응답 언어: 한국어'));
      expect(b.prompt, contains('기본 번역본: 개역개정성경'));
      for (final i in sermonStepItems['message']!) {
        expect(b.prompt, contains(i.text));
      }
      expect(b.prompt, contains('[문체 지침]'));
      expect(b.systemExtra, '');
    });

    test('인용 정책은 영어일 때만 붙는다', () {
      final ko = buildSermonStepPrompt('message', '요 3:16', '', 'ko', '', '');
      final en = buildSermonStepPrompt('message', 'John 3:16', '', 'en', 'ESV', '');
      expect(ko.prompt, isNot(contains('[Scripture Citation Policy]')));
      expect(en.prompt, contains('[Scripture Citation Policy]'));
      expect(withCitationPolicy('x', 'ko'), 'x');
    });

    test('선택 항목·강조·시리즈·키워드가 반영된다', () {
      final b = buildSermonStepPrompt('narrative', '창 1:1', '창조', 'ko', null, '[이전 설교]', ['context'], '키워드', '- 커스텀', '메모');
      expect(b.prompt, contains('- 본문의 전후 문맥'));
      expect(b.prompt, isNot(contains('- 해당 성경책에서의 위치와 역할')));
      expect(b.prompt, contains('설교자가 강조하고 싶은 주제: 창조'));
      expect(b.prompt, contains('[이전 설교]\n\n[강해설교 연속성 지침]'));
      expect(b.prompt, endsWith('\n- 커스텀\n\n메모\n\n[필수 반영 — 아래 키워드/지시를 결과에 반드시 명확하게 담으세요]: 키워드'));
    });

    test('모르는 단계는 예외', () {
      expect(() => buildSermonStepPrompt('nope', 'x', '', 'ko', '', ''), throwsException);
    });
  });

  test('예배 통합 프롬프트에 찬송가 목록과 구절 DB가 들어간다', () {
    final b = buildWorshipCombinedPrompt('2026-09-27', '', '', 'ko', '', null);
    expect(b.prompt, contains(getHymnListText()));
    expect(b.prompt, contains('날짜: 2026-09-27 | 절기: 일반 주일 | 성서정과: 미지정'));
    expect(b.prompt, contains('[12. 축도]'));
    expect(b.prompt, isNot(contains('[Scripture Citation Policy]')));
  });

  test('새벽 통합과 해설 단계는 문어체 시스템 지시를 쓴다', () {
    expect(buildDawnCombinedPrompt('시 1편', '', 'ko', '', '', null).systemExtra, dawnStyleSystem);
    expect(buildDawnStepPrompt('exposition', '시 1편', '', 'ko', '', '').systemExtra, dawnStyleSystem);
    expect(buildDawnStepPrompt('hymn', '시 1편', '', 'ko', '', '').systemExtra, '');
  });

  test('executeSelectionEdit 프롬프트에 선택한 글과 지시가 들어간다', () {
    final b = buildSelectionEditPrompt('선택한 문장입니다.', '더 짧게', '앞', '뒤', 'ko', '', '요 3:16', '사랑');
    expect(b.prompt, contains('[선택한 글]\n선택한 문장입니다.'));
    expect(b.prompt, contains('[지시사항]: 더 짧게'));
    expect(b.prompt, contains('본문: 요 3:16\n제목: 사랑\n[사용 성경]: 개역개정'));
    expect(b.systemExtra, contains('번호 붙이기 규칙은 적용하지 말고'));
  });

  test('인라인 명령은 앞 문맥 뒤 600자, 뒤 문맥 앞 600자만 쓴다', () {
    final before = '${'a' * 100}${'b' * 600}';
    final after = '${'c' * 600}${'d' * 100}';
    final b = buildInlineCommandPrompt('예화 추가', before, after, 'en', '', '', '');
    expect(b.prompt, contains('[앞 문맥]\n${'b' * 600}\n\n[뒤 문맥]\n${'c' * 600}\n'));
    expect(b.prompt, isNot(contains('a')));
    expect(b.prompt, endsWith('[사용 성경]: ESV'));
  });

  test('구절 DB와 찬송가 도우미', () {
    expect(forgivenessVerses.length, 185);
    expect(callToWorshipVerses.length, 142);
    expect(getRandomVerseText(callToWorshipVerses).split('\n').length, 18);
    expect(getHymnListText().split('\n').length, 645);
    expect(findHymn('1')?.title, '만복의 근원 하나님');
    expect(findHymn('기쁘다')?.number, isNotNull);
    expect(findHymn('없는제목xyz'), isNull);
  });
}
