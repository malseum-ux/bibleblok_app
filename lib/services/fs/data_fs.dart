// 저장 폴더 공통 접근 계층
//
// 저장 폴더 문자열은 두 가지 형태다.
//   웹       'web:이름'     → 브라우저 File System Access API (JS 브리지, web/index.html)
//   네이티브  '/full/path'   → dart:io 폴더 (Mac·Windows·Android)
// 앱의 다른 코드는 DataFs 만 쓰면 플랫폼을 신경 쓰지 않아도 된다.
// 경로는 항상 저장 폴더 기준 상대 경로, 구분자는 '/'.
import 'fs_native_stub.dart' if (dart.library.io) 'fs_native.dart' as native;
import 'fs_web_stub.dart' if (dart.library.js_interop) 'fs_web.dart' as web;

class FsTree {
  final List<String> dirs;
  final List<String> files;
  const FsTree(this.dirs, this.files);
}

abstract class DataFs {
  /// 화면에 보여 줄 폴더 이름
  String get displayName;

  /// 하위 폴더까지 전부 — 폴더 목록과 파일 목록 (상대 경로)
  Future<FsTree> listTree();

  Future<String?> readText(String path);

  /// 파일 쓰기 (없으면 만들고, 중간 폴더도 만든다)
  Future<bool> writeText(String path, String text);

  /// 폴더 만들기 (중간 폴더 포함)
  Future<bool> mkdir(String path);

  /// 파일 또는 폴더 삭제 (폴더는 안의 내용까지)
  Future<bool> delete(String path);
}

const webRootPrefix = 'web:';

bool isWebRoot(String root) => root.startsWith(webRootPrefix);

/// 저장된 폴더 문자열로 DataFs 를 만든다. 쓸 수 없는 형태면 null
DataFs? dataFsFromRoot(String root) {
  if (isWebRoot(root)) return web.createWebFs(root.substring(webRootPrefix.length));
  return native.createNativeFs(root);
}

/// 폴더 선택 창 — 선택한 폴더 문자열 (취소하면 null)
Future<String?> pickDataRoot() async {
  final w = await web.pickWebRoot();
  if (w != null) return '$webRootPrefix$w';
  return native.pickNativeRoot();
}

/// 웹: 새로고침 뒤 이전에 고른 폴더를 다시 연결 (권한이 살아 있으면 폴더 이름)
Future<String?> restoreWebRoot() => web.restoreWebRoot();

/// 웹: 권한이 풀린 폴더에 권한 다시 요청 (사용자 클릭 안에서 호출)
Future<String?> requestWebPermission() => web.requestWebPermission();

/// 웹: 이전에 고른 폴더 기록이 있는지 (권한과 무관)
Future<bool> hasStoredWebRoot() => web.hasStoredWebRoot();

bool get isWebPlatform => web.isWeb;

/// 웹: 이 브라우저에서 폴더 저장을 쓸 수 있는지
bool get webFolderSupported => web.webFolderSupported;
