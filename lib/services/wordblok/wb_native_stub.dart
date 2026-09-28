// dart:io 가 없는 플랫폼(웹)용 빈 구현
String folderName() => '';
bool permissionNeeded() => false;
Future<String?> pick() async => null;
Future<String?> restore() async => null;
Future<String?> requestPermission() async => null;
void clearCache() {}
Future<List<String>> listScb() async => [];
Future<List<List<Object?>>> query(String path, String sql, [List<Object?> args = const []]) async => [];
Future<void> beginWrite(String path) async {}
Future<void> update(String path, String sql, List<Object?> args) async {}
