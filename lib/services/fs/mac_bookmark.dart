// Mac 앱 저장 폴더 허락 보관 — 보안 범위 북마크 (macos/Runner/MainFlutterWindow.swift 와 짝)
//
// Mac 앱은 사용자가 고른 폴더에 그 실행 동안만 들어갈 수 있다.
// 폴더를 고를 때 북마크를 만들어 두고, 다음에 켤 때 북마크로 다시 열어야 같은 폴더를 계속 쓸 수 있다.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('bibleblok/bookmarks');

/// 북마크가 필요한 기기인지 (Mac 앱만)
bool get needsFolderBookmark => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// 폴더 경로 → 북마크 글자 (실패하면 null)
Future<String?> createFolderBookmark(String path) async {
  try {
    return await _channel.invokeMethod<String>('create', {'path': path});
  } catch (_) {
    return null;
  }
}

/// 북마크로 폴더를 다시 연다 — 경로와, 북마크가 오래됐으면 새 북마크(renewed). 실패하면 null
Future<({String path, String? renewed})?> resolveFolderBookmark(String bookmark) async {
  try {
    final r = await _channel.invokeMapMethod<String, dynamic>('resolve', {'bookmark': bookmark});
    if (r == null || r['path'] is! String) return null;
    return (path: r['path'] as String, renewed: r['renewed'] as String?);
  } catch (_) {
    return null;
  }
}
