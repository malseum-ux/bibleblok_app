// 웹 전용 — File System Access API (핸들은 JS 에서 관리, web/index.html 의 bb* 함수)
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'data_fs.dart';

const isWeb = true;

/// 이 브라우저가 폴더 읽기·쓰기를 지원하는지 (Chrome·Edge 만 지원)
bool get webFolderSupported => globalContext.has('showDirectoryPicker');

Future<JSAny?> _call(String fn, [List<JSAny?> args = const []]) async {
  try {
    final promise = globalContext.callMethodVarArgs<JSPromise<JSAny?>?>(fn.toJS, args);
    if (promise == null) return null;
    return await promise.toDart;
  } catch (_) {
    return null;
  }
}

Future<String?> _callString(String fn, [List<JSAny?> args = const []]) async {
  final r = await _call(fn, args);
  return r.isA<JSString>() ? (r as JSString).toDart : null;
}

Future<bool> _callBool(String fn, [List<JSAny?> args = const []]) async {
  final r = await _call(fn, args);
  return r.isA<JSBoolean>() && (r as JSBoolean).toDart;
}

Future<String?> pickWebRoot() => _callString('bbPickFolder');
Future<String?> restoreWebRoot() => _callString('bbRestoreFolder');
Future<String?> requestWebPermission() => _callString('bbRequestPermission');
Future<bool> hasStoredWebRoot() => _callBool('bbHasStored');

DataFs? createWebFs(String name) => _WebFs(name);

class _WebFs implements DataFs {
  final String name;
  _WebFs(this.name);

  @override
  String get displayName => name;

  @override
  Future<FsTree> listTree() async {
    final raw = await _call('bbListTree');
    final map = raw?.dartify();
    if (map is! Map) return const FsTree([], []);
    final dirs = [for (final d in (map['dirs'] as List? ?? [])) '$d'];
    final files = [for (final f in (map['files'] as List? ?? [])) '$f'];
    return FsTree(dirs, files);
  }

  @override
  Future<String?> readText(String path) => _callString('bbReadText', [path.toJS]);

  @override
  Future<bool> writeText(String path, String text) => _callBool('bbWriteText', [path.toJS, text.toJS]);

  @override
  Future<bool> mkdir(String path) => _callBool('bbMkdir', [path.toJS]);

  @override
  Future<bool> delete(String path) => _callBool('bbDelete', [path.toJS]);
}
