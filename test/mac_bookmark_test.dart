// Mac 앱 저장 폴더 — 켤 때 북마크로 폴더를 다시 여는 흐름
import 'dart:io';

import 'package:bibleblok_app/providers/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bibleblok/bookmarks');
  late Directory dir;
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    dir = Directory.systemTemp.createTempSync('bb_mac');
    calls.clear();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    dir.deleteSync(recursive: true);
  });

  void mockResolve(Map<String, String>? result) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return result;
    });
  }

  test('북마크가 있으면 그 폴더를 다시 열고, 오래된 북마크는 새것으로 바꾼다', () async {
    SharedPreferences.setMockInitialValues({'bibleblok-data-bookmark': 'OLD'});
    mockResolve({'path': dir.path, 'renewed': 'NEW'});
    final folder = FolderState();
    await folder.init();
    expect(calls.single.method, 'resolve');
    expect(calls.single.arguments, {'bookmark': 'OLD'});
    expect(folder.status, FolderStatus.ready);
    expect(folder.store!.fs.displayName, dir.uri.pathSegments.where((s) => s.isNotEmpty).last);
    expect((await SharedPreferences.getInstance()).getString('bibleblok-data-bookmark'), 'NEW');
  });

  test('북마크로 폴더를 못 열면 폴더 선택 화면과 안내 문구', () async {
    SharedPreferences.setMockInitialValues({'bibleblok-data-bookmark': 'BROKEN', 'bibleblok-data-root': '/old/path'});
    mockResolve(null);
    final folder = FolderState();
    await folder.init();
    expect(folder.status, FolderStatus.needFolder);
    expect(folder.error, contains('다시 선택'));
  });

  test('북마크가 없으면 옛 경로가 있어도 폴더 선택부터 (Mac 은 경로만으로 못 들어간다)', () async {
    SharedPreferences.setMockInitialValues({'bibleblok-data-root': dir.path});
    mockResolve(null);
    final folder = FolderState();
    await folder.init();
    expect(calls, isEmpty);
    expect(folder.status, FolderStatus.needFolder);
  });
}
