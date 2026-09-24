// 네이티브 (Mac·Windows·Android) — dart:io 폴더
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'data_fs.dart';

DataFs? createNativeFs(String root) => _NativeFs(root);

Future<String?> pickNativeRoot() => FilePicker.getDirectoryPath();

class _NativeFs implements DataFs {
  final String root;
  _NativeFs(this.root);

  String _abs(String rel) => p.joinAll([root, ...rel.split('/').where((s) => s.isNotEmpty)]);
  String _rel(String abs) => p.relative(abs, from: root).replaceAll('\\', '/');

  @override
  String get displayName => p.basename(root);

  @override
  Future<FsTree> listTree() async {
    final dir = Directory(root);
    if (!await dir.exists()) return const FsTree([], []);
    final dirs = <String>[];
    final files = <String>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      final rel = _rel(e.path);
      if (rel.split('/').any((s) => s.startsWith('.'))) continue; // 숨김 파일·폴더 제외
      if (e is Directory) {
        dirs.add(rel);
      } else if (e is File) {
        files.add(rel);
      }
    }
    return FsTree(dirs, files);
  }

  @override
  Future<String?> readText(String path) async {
    try {
      return await File(_abs(path)).readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> writeText(String path, String text) async {
    try {
      final f = File(_abs(path));
      await f.parent.create(recursive: true);
      await f.writeAsString(text, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> mkdir(String path) async {
    try {
      await Directory(_abs(path)).create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String path) async {
    try {
      final abs = _abs(path);
      if (await FileSystemEntity.isDirectory(abs)) {
        await Directory(abs).delete(recursive: true);
      } else {
        await File(abs).delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
