// dart:io 가 없는 플랫폼(웹)용 빈 구현
import 'data_fs.dart';

DataFs? createNativeFs(String root) => null;
Future<String?> pickNativeRoot() async => null;
