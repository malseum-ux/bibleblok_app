import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fs/data_fs.dart';
import '../services/store.dart';

// ── 앱 설정 (기기별) — 웹 settings.js 와 같은 키·기본값 ─────────────────────────

class AppSettings {
  final String theme; // system | light | dark
  final String lang; // ko | en
  final String bible;
  const AppSettings({this.theme = 'system', this.lang = 'ko', this.bible = '개역개정성경'});

  AppSettings copyWith({String? theme, String? lang, String? bible}) =>
      AppSettings(theme: theme ?? this.theme, lang: lang ?? this.lang, bible: bible ?? this.bible);

  Map<String, String> toJson() => {'theme': theme, 'lang': lang, 'bible': bible};
}

const _settingsKey = 'bibleblok-settings';
const _rootKey = 'bibleblok-data-root';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(prefs.getString(_settingsKey) ?? '{}') as Map;
      state = AppSettings(
        theme: (j['theme'] ?? 'system') as String,
        lang: (j['lang'] ?? 'ko') as String,
        bible: (j['bible'] ?? '개역개정성경') as String,
      );
    } catch (_) {}
  }

  Future<void> update(AppSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(next.toJson()));
  }

  /// 언어를 바꾸면 성경 번역본도 그 언어 기본값으로 (웹 SettingsPanel 과 같은 동작)
  Future<void> setLang(String lang) =>
      update(state.copyWith(lang: lang, bible: lang == 'en' ? 'ESV' : '개역개정성경'));
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) => SettingsNotifier());

// ── 저장 폴더 연결 상태 ─────────────────────────────────────────────────────

enum FolderStatus { checking, needFolder, needPermission, ready, unsupported }

class FolderState extends ChangeNotifier {
  FolderStatus status = FolderStatus.checking;
  Store? store;
  String? error;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final root = prefs.getString(_rootKey);
    if (isWebPlatform) {
      if (!webFolderSupported) {
        status = FolderStatus.unsupported;
        notifyListeners();
        return;
      }
      final name = await restoreWebRoot();
      if (name != null) return _open('$webRootPrefix$name');
      status = await hasStoredWebRoot() ? FolderStatus.needPermission : FolderStatus.needFolder;
      notifyListeners();
      return;
    }
    if (root != null && root.isNotEmpty && !isWebRoot(root)) return _open(root);
    status = FolderStatus.needFolder;
    notifyListeners();
  }

  Future<void> _open(String root) async {
    final fs = dataFsFromRoot(root);
    if (fs == null) {
      status = FolderStatus.needFolder;
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_rootKey, root);
    store?.removeListener(notifyListeners);
    store = Store(fs)..addListener(notifyListeners); // 저장소가 바뀌면 화면도 다시 그린다
    await store!.loadAll();
    status = FolderStatus.ready;
    notifyListeners();
  }

  /// 폴더 선택 창 (사용자 클릭 안에서 호출)
  Future<void> pickFolder() async {
    error = null;
    try {
      final root = await pickDataRoot();
      if (root != null) await _open(root);
    } catch (e) {
      error = '$e';
      if (isWebPlatform && '$e'.contains('unsupported')) status = FolderStatus.unsupported;
      notifyListeners();
    }
  }

  /// 웹: 새로고침 뒤 풀린 권한 다시 받기 (사용자 클릭 안에서 호출)
  Future<void> requestPermission() async {
    final name = await requestWebPermission();
    if (name != null) {
      await _open('$webRootPrefix$name');
    } else {
      error = '권한이 허용되지 않았습니다.';
      notifyListeners();
    }
  }
}

final folderProvider = ChangeNotifierProvider<FolderState>((ref) => FolderState());

/// 연결된 저장소 — 폴더가 준비된 화면(status == ready)에서만 쓴다
extension StoreRef on WidgetRef {
  Store get store => watch(folderProvider).store!;
  Store get storeRead => read(folderProvider).store!;
}
