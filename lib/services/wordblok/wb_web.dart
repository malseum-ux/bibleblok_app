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

/// 저장 전 쓰기 권한 요청 — 저장 버튼 클릭 안에서 가장 먼저 불러야 권한 창이 뜬다
Future<void> beginWrite(String path) async {
  if (!_dbs.containsKey(path)) throw Exception('설교 파일이 열려 있지 않습니다');
  try {
    await _call('bbWbRequestWrite', [path.toJS]);
  } catch (e) {
    throw Exception(_jsMessage(e));
  }
}

/// UPDATE 를 메모리 DB 에 실행하고, 바뀐 DB 를 원래 .scb 파일에 다시 쓴다
Future<void> update(String path, String sql, List<Object?> args) async {
  final db = await _open(path);
  db.callMethodVarArgs<JSAny?>('run'.toJS, [sql.toJS, args.jsify()]);
  final bytes = db.callMethod<JSAny?>('export'.toJS);
  try {
    await _call('bbWbWriteBytes', [path.toJS, bytes]);
  } catch (e) {
    // 파일에 못 썼으면 메모리 DB 도 버려 다음에 파일에서 다시 읽게 한다
    _dbs.remove(path);
    throw Exception(_jsMessage(e));
  }
}

/// JS 오류 글자에서 앞의 'Error: ' 를 뗀다
String _jsMessage(Object e) => '$e'.replaceFirst(RegExp(r'^(Exception|Error): '), '');
