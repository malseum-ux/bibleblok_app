// 성경나침반 내설교 — 웹 (폴더 핸들은 JS 에서 관리, web/index.html 의 bbWb* 함수)
// .scb 는 sql.js(web/sql-wasm.js)로 메모리에 열어 읽기만 한다.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

const isWeb = true;

JSObject? _sql; // sql.js 모듈
final Map<String, JSObject> _dbs = {}; // 파일 경로 → 열린 DB

Future<JSAny?> _call(String fn, [List<JSAny?> args = const []]) async {
  final promise = globalContext.callMethodVarArgs<JSPromise<JSAny?>?>(fn.toJS, args);
  if (promise == null) return null;
  return await promise.toDart;
}

String? _str(JSAny? r) => r.isA<JSString>() ? (r as JSString).toDart : null;

String folderName() {
  try {
    return _str(globalContext.callMethod<JSAny?>('bbWbName'.toJS)) ?? '';
  } catch (_) {
    return '';
  }
}

bool permissionNeeded() {
  try {
    final r = globalContext.callMethod<JSAny?>('bbWbPending'.toJS);
    return r.isA<JSBoolean>() && (r as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

/// 폴더 선택 — 취소하면 null, 지원하지 않는 브라우저 등은 예외
Future<String?> pick() async {
  final name = _str(await _call('bbWbPick'));
  if (name != null) clearCache();
  return name;
}

Future<String?> restore() async {
  try {
    return _str(await _call('bbWbRestore'));
  } catch (_) {
    return null;
  }
}

Future<String?> requestPermission() async {
  try {
    final name = _str(await _call('bbWbRequestPermission'));
    if (name != null) clearCache();
    return name;
  } catch (_) {
    return null;
  }
}

void clearCache() {
  for (final db in _dbs.values) {
    try {
      db.callMethod<JSAny?>('close'.toJS);
    } catch (_) {}
  }
  _dbs.clear();
}

Future<List<String>> listScb() async {
  try {
    final r = (await _call('bbWbListScb')).dartify();
    return r is List ? [for (final f in r) '$f'] : [];
  } catch (_) {
    return [];
  }
}

Future<JSObject> _initSql() async {
  if (_sql != null) return _sql!;
  // wasm 파일은 web/sql-wasm.wasm (index.html 기준 상대 경로)
  final config = JSObject()..['locateFile'] = ((JSString f) => f).toJS;
  _sql = await globalContext.callMethod<JSPromise<JSObject>>('initSqlJs'.toJS, config).toDart;
  return _sql!;
}

Future<JSObject> _open(String path) async {
  final cached = _dbs[path];
  if (cached != null) return cached;
  final bytes = await _call('bbWbReadBytes', [path.toJS]);
  if (bytes == null || !bytes.isA<JSUint8Array>()) throw Exception('파일을 읽지 못했습니다: $path');
  final sql = await _initSql();
  final db = (sql['Database'] as JSFunction).callAsConstructorVarArgs<JSObject>([bytes]);
  return _dbs[path] = db;
}

Object? _cell(Object? v) {
  if (v is num && v == v.truncate()) return v.toInt();
  if (v is ByteBuffer || v is Uint8List) return null; // BLOB 은 쓰지 않는다
  return v;
}

Future<List<List<Object?>>> query(String path, String sql, [List<Object?> args = const []]) async {
  final db = await _open(path);
  final result = db.callMethodVarArgs<JSAny?>('exec'.toJS, [sql.toJS, if (args.isNotEmpty) args.jsify()]).dartify();
  if (result is! List || result.isEmpty) return [];
  final values = (result[0] as Map)['values'] as List? ?? [];
  return [
    for (final row in values) [for (final v in row as List) _cell(v)],
  ];
}
