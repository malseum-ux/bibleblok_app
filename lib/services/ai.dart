// AI 요청 — 웹 claude.js / WorshipForm.fetchLectionary 와 같은 요청 내용
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

Uri _endpoint() {
  if (kAiEndpoint.isEmpty) throw Exception('AI 서버 주소가 설정되지 않았습니다');
  return Uri.parse(kAiEndpoint);
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
