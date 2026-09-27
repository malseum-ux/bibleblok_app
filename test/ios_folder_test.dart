// iPhone·iPad 저장 폴더 — iCloud Drive 의 성경과설교 폴더, iCloud 를 못 쓰면 기기 안 폴더
import 'dart:io';

import 'package:bibleblok_app/providers/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final String docs;
  _FakePaths(this.docs);
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bibleblok/icloud');
  late Directory dir;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    dir = Directory.systemTemp.createTempSync('bb_ios');
    PathProviderPlatform.instance = _FakePaths('${dir.path}/local');
    Directory('${dir.path}/local').createSync();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  test('iCloud 를 쓸 수 있으면 iCloud Drive 폴더를 바로 연다', () async {
    final icloud = Directory('${dir.path}/Mobile Documents/iCloud~com~blokzip~bibleblok/Documents')..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => call.method == 'documentsPath' ? icloud.path : null);
    final folder = FolderState();
    await folder.init();
    expect(folder.status, FolderStatus.ready);
    expect(folder.store!.fs.displayName, 'iCloud Drive › 성경과설교');
    await folder.store!.createItem('sermon', {'title': '아브라함'}, '');
    expect(File('${icloud.path}/설교작성/아브라함.json').existsSync(), isTrue);
  });

  test('iCloud 에 로그인하지 않았으면 기기 안 폴더', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => null);
    final folder = FolderState();
    await folder.init();
    expect(folder.status, FolderStatus.ready);
    expect(folder.store!.fs.displayName, '이 기기 › 성경과설교');
    await folder.store!.createItem('sermon', {'title': '모세'}, '');
    expect(File('${dir.path}/local/설교작성/모세.json').existsSync(), isTrue);
  });
}
