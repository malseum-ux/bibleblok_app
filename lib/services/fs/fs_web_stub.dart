// 웹이 아닌 플랫폼용 빈 구현
import 'data_fs.dart';

const isWeb = false;
bool get webFolderSupported => false;

DataFs? createWebFs(String name) => null;
Future<String?> pickWebRoot() async => null;
Future<String?> restoreWebRoot() async => null;
Future<String?> requestWebPermission() async => null;
Future<bool> hasStoredWebRoot() async => false;
