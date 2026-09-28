// 성경나침반 내설교 — 네이티브 (Mac·Windows·iPhone·iPad·Android)
// 폴더 경로는 SharedPreferences 에 보관한다. Mac 앱은 저장 폴더처럼 보안 범위 북마크로 허락을 보관한다 (fs/mac_bookmark.dart).
// .scb 는 읽기 전용으로 연다 — iPhone·iPad·Android 는 sqflite, Mac·Windows·Linux 는 sqflite_common_ffi
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fs/mac_bookmark.dart';

const _rootKey = 'bibleblok-wordblok-sermon-root';
const _bookmarkKey = 'bibleblok-wordblok-sermon-bookmark'; // Mac 앱: 내설교 폴더 허락

String? _root; // 연결된 내설교 폴더 (절대 경로)
bool _stored = false; // 기록은 있는데 폴더에 들어갈 수 없어 다시 허용을 기다리는 중
final Map<String, Database> _dbs = {}; // 파일 경로 → 열린 DB
bool _ffiReady = false;

String folderName() => _root == null ? '' : p.basename(_root!);

bool permissionNeeded() => _root == null && _stored;

Future<bool> _canRead(String path) async {
  try {
    final dir = Directory(path);
    if (!await dir.exists()) return false;
    await dir.list().isEmpty; // 들어갈 수 없으면 예외
    return true;
  } catch (_) {
    return false;
  }
}

Future<String?> pick() async {
  final path = await FilePicker.getDirectoryPath();
  if (path == null) return null;
  final prefs = await SharedPreferences.getInstance();
  // Mac 앱: 다음에 켤 때도 이 폴더에 들어갈 수 있도록 허락을 북마크로 보관
  if (needsFolderBookmark) {
    final bookmark = await createFolderBookmark(path);
    if (bookmark == null) throw Exception('폴더 허락을 보관하지 못했습니다');
    await prefs.setString(_bookmarkKey, bookmark);
  }
  await prefs.setString(_rootKey, path);
  clearCache();
  _root = path;
  _stored = false;
  return folderName();
}

Future<String?> restore() async {
  if (_root != null) return folderName();
  final prefs = await SharedPreferences.getInstance();
  var path = prefs.getString(_rootKey);
  if (path == null || path.isEmpty) return null;
  _stored = true;
  // Mac 앱: 북마크로 폴더를 다시 열어야 들어갈 수 있다
  if (needsFolderBookmark) {
    final bookmark = prefs.getString(_bookmarkKey);
    if (bookmark == null) return null;
    final resolved = await resolveFolderBookmark(bookmark);
    if (resolved == null) return null;
    if (resolved.renewed != null) await prefs.setString(_bookmarkKey, resolved.renewed!);
    path = resolved.path;
  }
  if (!await _canRead(path)) return null;
  _root = path;
  _stored = false;
  return folderName();
}

/// 네이티브는 권한을 다시 물을 방법이 없어 폴더를 다시 고른다
Future<String?> requestPermission() => pick();

void clearCache() {
  for (final db in _dbs.values) {
    db.close().catchError((_) {});
  }
  _dbs.clear();
}

Future<List<String>> listScb() async {
  final root = _root;
  if (root == null) return [];
  final out = <String>[];
  try {
    await for (final e in Directory(root).list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: root).replaceAll('\\', '/');
      if (rel.split('/').any((s) => s.startsWith('.'))) continue; // 숨김 파일·폴더 제외
      if (rel.toLowerCase().endsWith('.scb')) out.add(rel);
    }
  } catch (_) {
    // 읽을 수 없는 폴더는 건너뛴다
  }
  return out..sort();
}

DatabaseFactory get _factory {
  if (Platform.isIOS || Platform.isAndroid) return sqflite.databaseFactorySqflitePlugin;
  if (!_ffiReady) {
    sqfliteFfiInit();
    _ffiReady = true;
  }
  return databaseFactoryFfi;
}

Future<Database> _open(String path) async {
  final cached = _dbs[path];
  if (cached != null) return cached;
  final abs = p.joinAll([_root!, ...path.split('/')]);
  final db = await _factory.openDatabase(abs, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  return _dbs[path] = db;
}

Future<List<List<Object?>>> query(String path, String sql, [List<Object?> args = const []]) async {
  if (_root == null) return [];
  final db = await _open(path);
  final rows = await db.rawQuery(sql, args);
  return [for (final r in rows) r.values.toList()];
}

Future<void> beginWrite(String path) async {
  if (_root == null) throw Exception('설교 파일이 열려 있지 않습니다');
}

/// 저장할 때만 쓰기로 다시 열어 UPDATE 하고 닫는다 (읽기용으로 열어 둔 것은 닫아 다음에 새로 읽게 한다)
Future<void> update(String path, String sql, List<Object?> args) async {
  final root = _root;
  if (root == null) throw Exception('설교 파일이 열려 있지 않습니다');
  final cached = _dbs.remove(path);
  await cached?.close();
  final abs = p.joinAll([root, ...path.split('/')]);
  final db = await _factory.openDatabase(abs, options: OpenDatabaseOptions(readOnly: false, singleInstance: false));
  try {
    await db.rawUpdate(sql, args);
  } finally {
    await db.close();
  }
}

/// 네이티브는 따로 물을 권한이 없다
Future<bool> requestWrite() async => _root != null;
