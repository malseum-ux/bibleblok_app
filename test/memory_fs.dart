// 시험용 메모리 속 가짜 폴더
import 'package:bibleblok_app/services/fs/data_fs.dart';

class MemoryFs implements DataFs {
  final files = <String, String>{};
  final dirs = <String>{};

  void _addDirs(String path) {
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      dirs.add(parts.sublist(0, i).join('/'));
    }
  }

  @override
  String get displayName => 'Memory';

  @override
  Future<FsTree> listTree() async => FsTree(dirs.toList(), files.keys.toList());

  @override
  Future<String?> readText(String path) async => files[path];

  @override
  Future<bool> writeText(String path, String text) async {
    files[path] = text;
    if (path.contains('/')) _addDirs(path.substring(0, path.lastIndexOf('/')));
    return true;
  }

  @override
  Future<bool> mkdir(String path) async {
    _addDirs(path);
    return true;
  }

  @override
  Future<bool> delete(String path) async {
    files.remove(path);
    files.removeWhere((k, _) => k.startsWith('$path/'));
    dirs.removeWhere((d) => d == path || d.startsWith('$path/'));
    return true;
  }
}
