// Android 저장 폴더 — 폴더를 고르지 않고 앱 전용 폴더에 바로 저장
import 'dart:io';

import 'package:bibleblok_app/providers/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String base;
  _FakePaths(this.base);
  @override
  Future<String?> getExternalStoragePath() async => base;
  @override
  Future<String?> getApplicationDocumentsPath() async => '$base/docs';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    dir = Directory.systemTemp.createTempSync('bb_android');
    PathProviderPlatform.instance = _FakePaths(dir.path);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    dir.deleteSync(recursive: true);
  });

  test('켜면 폴더 선택 없이 앱 전용 폴더(성경과설교)를 만들어 바로 연다', () async {
    SharedPreferences.setMockInitialValues({});
    final folder = FolderState();
    await folder.init();
    expect(folder.status, FolderStatus.ready);
    expect(Directory('${dir.path}/성경과설교').existsSync(), isTrue);
    await folder.store!.createItem('sermon', {'title': '아브라함'}, '');
    expect(File('${dir.path}/성경과설교/설교작성/아브라함.json').existsSync(), isTrue);
  });
}
