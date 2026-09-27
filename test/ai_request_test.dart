// AI 요청 — 앱은 지시문 대신 { kind, params } 만 보내고, 서버의 스트리밍 응답을 이어 붙인다
import 'dart:convert';

import 'package:bibleblok_app/services/ai.dart';
import 'package:bibleblok_app/services/prompts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final bodies = <Map<String, dynamic>>[];
  final headers = <Map<String, String>>[];

  http.Client fakeServer() => MockClient.streaming((req, bodyStream) async {
        final body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
        bodies.add(body);
        headers.add(req.headers);
        if (body['kind'] == 'lectionary') {
          return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'choices': [{'message': {'content': ' 사 40:1 | 시 85 '}}]}))), 200);
        }
        final sse = 'data: {"choices":[{"delta":{"content":"하나"}}]}\n\ndata: {"choices":[{"delta":{"content":"님"}}]}\n\ndata: [DONE]\n';
        return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
      });

  setUp(() {
    bodies.clear();
    headers.clear();
    debugAccessToken = () => 'TEST-TOKEN';
  });
  tearDown(() => debugAccessToken = null);

  test('설교 단계 생성: kind·재료만 보내고, 흘러오는 글을 이어 붙인다', () async {
    final chunks = <String>[];
    final full = await http.runWithClient(
      () => generateSermonStep('narrative', '롬 1:1', '', 'ko', null, '', chunks.add, ['context'], '청년', '- 추가', '[메모리]'),
      fakeServer,
    );
    expect(full, '하나님');
    expect(chunks, ['하나', '하나님']);
    expect(bodies.single, {
      'kind': 'sermonStep',
      'params': {
        'stepKey': 'narrative', 'passage': '롬 1:1', 'emphasis': '', 'lang': 'ko', 'bible': null, 'seriesCtx': '',
        'selectedItems': ['context'], 'userKeyword': '청년', 'customText': '- 추가', 'memory': '[메모리]',
      },
    });
    expect(bodies.single.containsKey('messages'), isFalse); // 지시문은 보내지 않는다
    expect(headers.single['Authorization'], 'Bearer TEST-TOKEN');
  });

  test('// 지시문: 단계별 연구는 {label, content} 목록으로', () async {
    await http.runWithClient(
      () => executeInlineCommand('예화 추가', '앞', '뒤', 'ko', null, '요 1:1', '말씀', null, [(label: '원어', content: '로고스')], true),
      fakeServer,
    );
    expect(bodies.single['kind'], 'inlineCommand');
    expect(bodies.single['params']['stepsData'], [{'label': '원어', 'content': '로고스'}]);
    expect(bodies.single['params']['useTheological'], true);
  });

  test('성서정과 조회: 한 번에 받아 앞뒤 공백을 뗀다', () async {
    final r = await http.runWithClient(() => fetchLectionary('2026-09-27', '', 'ko', ''), fakeServer);
    expect(r, '사 40:1 | 시 85');
    expect(bodies.single, {'kind': 'lectionary', 'params': {'date': '2026-09-27', 'season': '', 'bible': ''}});
  });
}
