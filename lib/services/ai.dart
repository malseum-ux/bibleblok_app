// AI 요청 — 웹 claude.js 의 streamCompletion / WorshipForm.fetchLectionary 와 같은 요청 내용
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'http_client_stub.dart' if (dart.library.js_interop) 'http_client_web.dart';

Uri _endpoint() {
  if (kAiEndpoint.isEmpty) throw Exception('AI 서버 주소가 설정되지 않았습니다');
  return Uri.parse(kAiEndpoint);
}

/// 사용자가 중지를 눌렀을 때 던지는 예외 (웹의 AbortError)
class AbortedException implements Exception {
  @override
  String toString() => 'AbortError';
}

// 생성마다 자기 중단 장치를 갖는다 — 동시에 여러 생성이 돌아도 서로 덮어쓰지 않음
final Set<http.Client> _activeClients = {};
final Set<Completer<void>> _activeAborts = {};

void stopCurrentGeneration() {
  for (final c in _activeAborts) {
    if (!c.isCompleted) c.complete();
  }
  for (final c in _activeClients) {
    c.close();
  }
  _activeAborts.clear();
  _activeClients.clear();
}

const _baseSystem =
    '결과를 반드시 일반 텍스트로만 작성하세요. ##, **, ***, --, ---, > 같은 마크다운 기호를 절대 사용하지 마세요. 제목은 줄 바꿈으로, 강조는 일반 문장으로 표현하세요. 단락과 항목 사이에는 반드시 빈 줄 하나로 구분하세요. 빈 줄을 두 줄 이상 연속으로 넣지 마세요. 각 항목과 소제목에는 반드시 번호를 붙여(1. 2. 3. 형식) 내용이 한눈에 구조적으로 파악되도록 작성하세요. 찬송가를 추천할 때는 반드시 2006년 한국찬송가공회 발행 21세기찬송가(총 645장)를 기준으로 하세요. 번호와 제목을 스스로 교차 확인한 후 제시하되, 확신하지 못할 경우 번호 없이 제목만 제시하고 "번호는 직접 확인하세요"라고 안내하세요.';

/// 스트리밍 생성 — onChunk 에는 지금까지 받은 전체 글이 온다 (웹과 같음). 완성된 글 반환
Future<String> streamCompletion(String prompt, void Function(String full)? onChunk, {String systemExtra = ''}) async {
  final client = createStreamingClient();
  final abort = Completer<void>();
  _activeClients.add(client);
  _activeAborts.add(abort);
  final systemContent = systemExtra.isEmpty ? _baseSystem : '$_baseSystem\n\n$systemExtra';
  var fullText = '';
  try {
    final req = http.Request('POST', _endpoint())
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'model': 'deepseek-chat',
        'max_tokens': 8000,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': systemContent},
          {'role': 'user', 'content': prompt},
        ],
      });
    final http.StreamedResponse res;
    try {
      res = await client.send(req);
    } catch (e) {
      if (abort.isCompleted) throw AbortedException();
      rethrow;
    }
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      String message = 'API error';
      try {
        message = ((jsonDecode(body) as Map)['error'] as Map?)?['message'] as String? ?? message;
      } catch (_) {
        if (body.isNotEmpty) message = body;
      }
      throw Exception(message);
    }

    var buffer = '';
    void handleLine(String line) {
      if (!line.startsWith('data: ')) return;
      final data = line.substring(6).trim();
      if (data.isEmpty || data == '[DONE]') return;
      try {
        final j = jsonDecode(data) as Map;
        final text = ((j['choices'] as List?)?.first as Map?)?['delta']?['content'] as String? ?? '';
        if (text.isNotEmpty) {
          fullText += text;
          onChunk?.call(fullText);
        }
      } catch (_) {}
    }

    final lines = res.stream.transform(utf8.decoder);
    await for (final chunk in lines) {
      if (abort.isCompleted) throw AbortedException();
      buffer += chunk;
      final parts = buffer.split('\n');
      buffer = parts.removeLast();
      parts.forEach(handleLine);
    }
    if (abort.isCompleted) throw AbortedException();
    handleLine(buffer);
    return fullText;
  } catch (e) {
    if (abort.isCompleted && e is! AbortedException) throw AbortedException();
    rethrow;
  } finally {
    _activeClients.remove(client);
    _activeAborts.remove(abort);
    client.close();
  }
}

// 성서정과 AI 조회 (스트리밍 없이 한 번에)
Future<String> fetchLectionary(String date, String season, String lang, String bible) async {
  final year = DateTime.tryParse(date)?.year ?? DateTime.now().year;
  const cycles = ['A', 'B', 'C'];
  final idx = (year - 2022) % 3;
  final cycle = idx >= 0 ? cycles[idx] : 'A';

  final prompt = '''개정 공동 성구집(RCL) $cycle년 주기를 기준으로, $date (${season.isEmpty ? '일반 주일' : season})의 성서정과 본문을 알려주세요.
구약/시편/서신서/복음서 각 1개씩, 성경 장절 형식으로만 간결하게 답하세요. 설명 없이 본문 목록만 작성하세요.
예시 형식: 사 40:1-11 | 시 85:1-2, 8-13 | 막 1:1-8 | 빌 1:3-11
번역본: ${bible.isEmpty ? '개역개정성경' : bible}''';

  final res = await http.post(
    _endpoint(),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'model': 'deepseek-chat',
      'max_tokens': 200,
      'stream': false,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    }),
  );
  if (res.statusCode != 200) throw Exception('API error');
  final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
  return ((data['choices'] as List?)?.first?['message']?['content'] as String? ?? '').trim();
}
