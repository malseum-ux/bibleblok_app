// 네이티브 (Mac·Windows·Android) — dart:io 폴더
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data_fs.dart';

DataFs? createNativeFs(String root) => _NativeFs(root);

Future<String?> pickNativeRoot() => FilePicker.getDirectoryPath();

const _icloud = MethodChannel('bibleblok/icloud'); // ios/Runner/AppDelegate.swift 의 ICloudFolder

/// 폴더를 고르지 않고 정해진 폴더에 저장 (어느 기기에서 쓸지는 data_fs.dart 의 usesAutoFolder 한 곳에서 정한다)
/// - iPhone·iPad: iCloud Drive 의 "성경과설교" 폴더. iCloud 에 로그인하지 않았으면 기기 안 폴더(파일 앱 > 나의 iPhone·iPad > 성경과설교)
/// - Android: 앱 전용 폴더 Android/data/<앱>/files/성경과설교 (없으면 앱 내부 폴더)
///   최근 Android 는 앱이 아무 폴더에나 쓰지 못하게 막아서, 다른 기기로 옮길 때는 백업 내보내기·불러오기를 쓴다.
Future<String?> autoNativeRoot() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      final icloud = await _icloud.invokeMethod<String>('documentsPath');
      if (icloud != null) return icloud;
    } catch (_) {
      // iCloud 를 쓸 수 없으면 기기 안 폴더
    }
    return (await getApplicationDocumentsDirectory()).path;
  }
  final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, '성경과설교'));
  await dir.create(recursive: true);
  return dir.path;
}

class _NativeFs implements DataFs {
  final String root;
  _NativeFs(this.root);

  String _abs(String rel) => p.joinAll([root, ...rel.split('/').where((s) => s.isNotEmpty)]);
  String _rel(String abs) => p.relative(abs, from: root).replaceAll('\\', '/');

  @override
  String get displayName {
    // iPhone·iPad 는 폴더 이름이 Documents 라서 파일 앱에 보이는 이름으로
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return root.contains('Mobile Documents') ? 'iCloud Drive › 성경과설교' : '이 기기 › 성경과설교';
    }
    return p.basename(root);
  }

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
