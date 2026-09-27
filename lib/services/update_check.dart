// 업데이트 확인 — 설정 화면 "앱 정보"와 켤 때의 조용한 확인이 쓴다 (웹 src/updateCheck.js 와 같은 역할)
// - Mac·Windows·iPhone·Android: Supabase 의 app_releases 표(기기별 최신 버전·받는 곳)와 비교
// - 플러터 웹: 배포된 version.json 과 비교 (pubspec 의 version 을 올려서 배포해야 알아챈다)
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'page_reload_stub.dart' if (dart.library.js_interop) 'page_reload_web.dart';

class UpdateInfo {
  final String current; // 지금 버전
  final String? latest; // 최신 버전 (모르면 null)
  final String? url; // 새 버전을 받는 곳 (없으면 안내만)
  const UpdateInfo({required this.current, this.latest, this.url});

  bool get hasUpdate => latest != null && isNewerVersion(latest!, current);
}

/// 시험용 — 실제 서버 대신 결과를 넣는다
@visibleForTesting
Future<UpdateInfo> Function()? debugCheckForUpdate;

/// '1.2.0' 이 '1.1.9' 보다 새 버전인지 (숫자 단위로 비교, '+빌드번호'는 무시)
bool isNewerVersion(String latest, String current) {
  List<int> parts(String v) => v.split('+').first.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// app_releases 표의 기기 이름 (웹이면 null)
String? get releasePlatform {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => null,
  };
}

/// iPhone·Android 는 스토어에서, Mac·Windows 는 다운로드로 받는다
bool get updatesFromStore => releasePlatform == 'ios' || releasePlatform == 'android';

Future<String> appVersion() async => (await PackageInfo.fromPlatform()).version;

Future<UpdateInfo> checkForUpdate() async {
  if (debugCheckForUpdate != null) return debugCheckForUpdate!();
  final info = await PackageInfo.fromPlatform();
  final current = info.version;
  if (kIsWeb) {
    final res = await http.get(Uri.base.resolve('version.json?_=${DateTime.now().millisecondsSinceEpoch}'));
    final latest = RegExp(r'"version"\s*:\s*"([^"]+)"').firstMatch(res.body)?.group(1);
    return UpdateInfo(current: current, latest: latest);
  }
  final platform = releasePlatform;
  if (platform == null) return UpdateInfo(current: current);
  final row = await Supabase.instance.client
      .from('app_releases')
      .select('version, url')
      .eq('app', 'bibleblok')
      .eq('platform', platform)
      .maybeSingle();
  return UpdateInfo(current: current, latest: row?['version'] as String?, url: row?['url'] as String?);
}

/// 새 버전 받기 — 웹은 새로고침, 앱은 다운로드 주소·스토어 열기
Future<void> applyUpdate(UpdateInfo info) async {
  if (kIsWeb) return reloadPage();
  final url = info.url;
  if (url != null && url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
