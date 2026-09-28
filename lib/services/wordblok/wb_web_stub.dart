// 웹이 아닌 플랫폼용 빈 구현
const isWeb = false;
String folderName() => '';
bool permissionNeeded() => false;
Future<String?> pick() async => null;
Future<String?> restore() async => null;
Future<String?> requestPermission() async => null;
void clearCache() {}
Future<List<String>> listScb() async => [];
Future<List<List<Object?>>> query(String path, String sql, [List<Object?> args = const []]) async => [];
