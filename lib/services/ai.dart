// AI 요청 보내기 — 지시문은 서버(bibleblok-generate)가 조립하고, 여기서는 { kind, params } 를 보내 결과를 받는다
// (웹 src/claude.js 의 streamKind · fetchLectionary 와 같은 요청)
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'http_client_stub.dart' if (dart.library.js_interop) 'http_client_web.dart';

Uri _endpoint() {
  if (kAiEndpoint.isEmpty) throw Exception('AI 서버 주소가 설정되지 않았습니다');
  return Uri.parse(kAiEndpoint);
}

/// 시험용 — 로그인 없이 요청 모양을 확인할 때 로그인 증표를 대신 넣는다
@visibleForTesting
String? Function()? debugAccessToken;

/// 로그인 증표를 붙인 요청 머리말 — AI 서버는 로그인한 사용자만 받는다
Map<String, String> _headers() {
  final token = debugAccessToken?.call() ?? Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) throw Exception('로그인이 필요합니다.');
  return {'content-type': 'application/json', 'Authorization': 'Bearer $token', 'apikey': kSupabaseAnonKey};
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

/// 스트리밍 생성 — onChunk 에는 지금까지 받은 전체 글이 온다 (웹과 같음). 완성된 글 반환
Future<String> streamKind(String kind, Map<String, dynamic> params, void Function(String full)? onChunk) async {
  final client = createStreamingClient();
  final abort = Completer<void>();
  _activeClients.add(client);
  _activeAborts.add(abort);
  var fullText = '';
  try {
    final req = http.Request('POST', _endpoint())
      ..headers.addAll(_headers())
      ..body = jsonEncode({'kind': kind, 'params': params});
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
  final res = await http.post(
    _endpoint(),
    headers: _headers(),
    body: jsonEncode({
      'kind': 'lectionary',
      'params': {'date': date, 'season': season, 'bible': bible},
    }),
  );
  if (res.statusCode != 200) throw Exception('API error');
  final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
  return ((data['choices'] as List?)?.first?['message']?['content'] as String? ?? '').trim();
}
