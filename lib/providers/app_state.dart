import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/fs/data_fs.dart';
import '../services/fs/mac_bookmark.dart';
import '../services/store.dart';

// ── 앱 설정 (기기별) — 웹 settings.js 와 같은 키·기본값 ─────────────────────────

/// 글꼴 크기 범위·기본값 — 설정 화면과 화면 위 A-·A+ 버튼이 같은 값을 바꾼다 (웹 settings.js 와 같다)
const kFontMin = 11.0;
const kFontMax = 24.0;
const kFontDefault = 15.0;

/// 설교 속도 — 1분에 읽는 글자 수 (느림·보통·빠름, 웹 settings.js 와 같다)
const kSpeechRates = [250, 300, 350];
const kSpeechDefault = 300;

/// 예상 설교 시간(분) — 공백을 뺀 글자 수 ÷ 설교 속도 (반올림, 글이 있으면 최소 1분)
int sermonMinutes(int chars, int rate) => chars > 0 ? (chars / rate).round().clamp(1, 1 << 30) : 0;

class AppSettings {
  final String theme; // system | light | dark
  final String lang; // ko | en
  final double fontSize; // 본문 글꼴 크기 — 모든 탭이 같이 쓴다
  final int speechRate; // 설교 속도 (1분에 읽는 글자 수)
  final bool showSermonTime; // 우측 초안창에 예상 설교 시간 보이기
  const AppSettings({
    this.theme = 'system',
    this.lang = 'ko',
    this.fontSize = kFontDefault,
    this.speechRate = kSpeechDefault,
    this.showSermonTime = true,
  });

  /// 성경 번역본 — 고르지 않고 언어에 따라 정해진다 (한국어 개역개정, 영어 ESV)
  String get bible => lang == 'en' ? 'ESV' : '개역개정성경';

  AppSettings copyWith({String? theme, String? lang, double? fontSize, int? speechRate, bool? showSermonTime}) => AppSettings(
        theme: theme ?? this.theme,
        lang: lang ?? this.lang,
        fontSize: fontSize ?? this.fontSize,
        speechRate: speechRate ?? this.speechRate,
        showSermonTime: showSermonTime ?? this.showSermonTime,
      );

  Map<String, Object> toJson() =>
      {'theme': theme, 'lang': lang, 'fontSize': fontSize, 'speechRate': speechRate, 'showSermonTime': showSermonTime};
}

const _settingsKey = 'bibleblok-settings';
const _rootKey = 'bibleblok-data-root';
const _bookmarkKey = 'bibleblok-data-bookmark'; // Mac 앱: 저장 폴더 허락 (fs/mac_bookmark.dart)

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final j = jsonDecode(prefs.getString(_settingsKey) ?? '{}') as Map;
      state = AppSettings(
        theme: (j['theme'] ?? 'system') as String,
        lang: (j['lang'] ?? 'ko') as String,
        fontSize: ((j['fontSize'] as num?)?.toDouble() ?? kFontDefault).clamp(kFontMin, kFontMax),
        speechRate: kSpeechRates.contains(j['speechRate']) ? j['speechRate'] as int : kSpeechDefault,
        showSermonTime: j['showSermonTime'] != false,
      );
    } catch (_) {}
  }

  Future<void> update(AppSettings next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(next.toJson()));
  }

  Future<void> setLang(String lang) => update(state.copyWith(lang: lang));

  Future<void> setFontSize(double size) => update(state.copyWith(fontSize: size.clamp(kFontMin, kFontMax)));

  Future<void> setSpeechRate(int rate) => update(state.copyWith(speechRate: kSpeechRates.contains(rate) ? rate : kSpeechDefault));

  Future<void> toggleSermonTime() => update(state.copyWith(showSermonTime: !state.showSermonTime));
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
    // Android: 폴더를 고르지 않고 앱 전용 폴더에 바로 저장
    if (usesAutoFolder) {
      final auto = await autoDataRoot();
      if (auto != null) return _open(auto);
      error = '저장 폴더를 만들지 못했습니다.';
      status = FolderStatus.needFolder;
      notifyListeners();
      return;
    }
    // Mac 앱: 북마크로 폴더를 다시 열어야 들어갈 수 있다
    if (needsFolderBookmark) {
      final bookmark = prefs.getString(_bookmarkKey);
      if (bookmark != null) {
        final resolved = await resolveFolderBookmark(bookmark);
        if (resolved != null) {
          if (resolved.renewed != null) await prefs.setString(_bookmarkKey, resolved.renewed!);
          return _open(resolved.path);
        }
        error = '저장 폴더에 다시 들어갈 수 없습니다. 폴더를 다시 선택해 주세요.';
      }
      status = FolderStatus.needFolder;
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
      if (root == null) return;
      // Mac 앱: 다음에 켤 때도 이 폴더에 들어갈 수 있도록 허락을 북마크로 보관
      if (needsFolderBookmark) {
        final bookmark = await createFolderBookmark(root);
        if (bookmark == null) throw Exception('폴더 허락을 보관하지 못했습니다');
        (await SharedPreferences.getInstance()).setString(_bookmarkKey, bookmark);
      }
      await _open(root);
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
