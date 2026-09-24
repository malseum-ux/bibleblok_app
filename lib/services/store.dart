// 저장소 — 웹의 db.js(Supabase) 역할을 사용자 저장 폴더로 대신한다
//
// 저장 폴더 구조
//   설교작성/ 예배인도/ 새벽설교/ 교재작성/   ← 탭별 폴더
//     <사이드바 폴더>/<하위 폴더>/날짜 제목.json   ← 사이드바 폴더 = 실제 폴더
//   settings.json                              ← 기억된 지시어·학습 메모리·사용자 지시항목
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../models/item.dart';
import 'fs/data_fs.dart';

const _settingsFile = 'settings.json';
const _uuid = Uuid();

String _join(String a, String b) => a.isEmpty ? b : (b.isEmpty ? a : '$a/$b');
String parentOf(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
String baseName(String path) => path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

class CustomStepItem {
  final String id;
  final String tab;
  final String stepKey;
  String label;
  String text;
  int order;
  CustomStepItem({required this.id, required this.tab, required this.stepKey, required this.label, required this.text, this.order = 0});

  factory CustomStepItem.fromJson(Map j) => CustomStepItem(
        id: j['id'] as String,
        tab: j['tab'] as String,
        stepKey: j['stepKey'] as String,
        label: (j['label'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        order: (j['order'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toJson() => {'id': id, 'tab': tab, 'stepKey': stepKey, 'label': label, 'text': text, 'order': order};
}

class MemoryEntry {
  final String text;
  final String date;
  const MemoryEntry(this.text, this.date);
}

class Store extends ChangeNotifier {
  final DataFs fs;
  Store(this.fs);

  bool loaded = false;
  String? loadError;

  final Map<String, List<Item>> items = {for (final t in tabs) t: []};

  /// 탭별 폴더 경로 목록 (탭 폴더 기준 상대 경로)
  final Map<String, List<String>> folders = {for (final t in tabs) t: []};

  // settings.json 내용
  final Map<String, String> defaultKeywords = {}; // 'tab_stepKey' → 지시어
  final Map<String, List<MemoryEntry>> memories = {}; // 'tab_stepKey' → 메모리
  final List<CustomStepItem> customStepItems = [];

  // ── 불러오기 ────────────────────────────────────────────────────────────

  Future<void> loadAll() async {
    try {
      final tree = await fs.listTree();
      for (final t in tabs) {
        final prefix = tabDirNames[t]!;
        folders[t] = tree.dirs
            .where((d) => d.startsWith('$prefix/'))
            .map((d) => d.substring(prefix.length + 1))
            .toList()
          ..sort();
        final list = <Item>[];
        for (final f in tree.files) {
          if (!f.startsWith('$prefix/') || !f.toLowerCase().endsWith('.json')) continue;
          final text = await fs.readText(f);
          if (text == null) continue;
          try {
            final j = jsonDecode(text);
            if (j is! Map<String, dynamic> || j['app'] != 'bibleblok') continue;
            final rel = f.substring(prefix.length + 1);
            list.add(Item.fromJson(j, folder: parentOf(rel), fileName: baseName(rel)));
          } catch (_) {
            // 형식이 맞지 않는 파일은 건너뛴다
          }
        }
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        items[t] = list;
      }
      await _loadSettings();
      loaded = true;
      loadError = null;
    } catch (e) {
      loadError = '$e';
    }
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    defaultKeywords.clear();
    memories.clear();
    customStepItems.clear();
    final text = await fs.readText(_settingsFile);
    if (text == null) return;
    try {
      final j = jsonDecode(text) as Map;
      (j['defaultKeywords'] as Map? ?? {}).forEach((k, v) => defaultKeywords['$k'] = '$v');
      (j['memories'] as Map? ?? {}).forEach((k, v) {
        memories['$k'] = [for (final m in (v as List)) MemoryEntry('${m['text']}', '${m['date']}')];
      });
      for (final c in (j['customStepItems'] as List? ?? [])) {
        customStepItems.add(CustomStepItem.fromJson(c as Map));
      }
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    final j = {
      'app': 'bibleblok',
      'version': 1,
      'defaultKeywords': defaultKeywords,
      'memories': memories.map((k, v) => MapEntry(k, [for (final m in v) {'text': m.text, 'date': m.date}])),
      'customStepItems': [for (final c in customStepItems) c.toJson()],
    };
    await fs.writeText(_settingsFile, const JsonEncoder.withIndent('  ').convert(j));
    notifyListeners();
  }

  // ── 항목 ────────────────────────────────────────────────────────────────

  Item? find(String tab, String id) {
    for (final i in items[tab]!) {
      if (i.id == id) return i;
    }
    return null;
  }

  String _dirOf(Item item) => _join(tabDirNames[item.tab]!, item.folder);

  /// 같은 폴더에 같은 이름이 있으면 " (2)" 를 붙인다
  String _uniqueName(Item item) {
    final want = item.preferredFileName();
    final taken = items[item.tab]!
        .where((o) => o.id != item.id && o.folder == item.folder)
        .map((o) => o.fileName)
        .toSet();
    if (!taken.contains(want)) return want;
    final base = want.substring(0, want.length - 5);
    for (var n = 2;; n++) {
      final candidate = '$base ($n).json';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  Future<void> _write(Item item) async {
    final name = _uniqueName(item);
    final path = _join(_dirOf(item), name);
    final ok = await fs.writeText(path, const JsonEncoder.withIndent('  ').convert(item.toJson()));
    if (!ok) throw Exception('파일을 저장하지 못했습니다: $path');
    final old = item.fileName;
    item.fileName = name;
    if (old != null && old != name) await fs.delete(_join(_dirOf(item), old));
  }

  Future<Item> createItem(String tab, Map<String, String?> data, String folder) async {
    final item = Item(
      id: _uuid.v4(),
      tab: tab,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      date: data['date'],
      category: data['category'],
      title: data['title'],
      passage: data['passage'],
      emphasis: data['emphasis'],
      season: data['season'],
      lectionary: data['lectionary'],
      folder: folder,
    );
    await _write(item);
    items[tab]!.insert(0, item);
    notifyListeners();
    return item;
  }

  /// 기본정보·초안 등 필드 변경 뒤 저장 (이름이 바뀌면 파일 이름도 바뀐다)
  Future<void> saveItem(Item item) async {
    await _write(item);
    notifyListeners();
  }

  Future<void> saveStep(Item item, int index, String content) async {
    item.steps[index] = content;
    await _write(item);
    notifyListeners();
  }

  Future<void> deleteItem(Item item) async {
    if (item.fileName != null) await fs.delete(_join(_dirOf(item), item.fileName!));
    items[item.tab]!.removeWhere((i) => i.id == item.id);
    notifyListeners();
  }

  Future<void> moveItem(Item item, String folder) async {
    if (item.folder == folder) return;
    final oldPath = item.fileName == null ? null : _join(_dirOf(item), item.fileName!);
    item.folder = folder;
    item.fileName = null;
    await _write(item);
    if (oldPath != null) await fs.delete(oldPath);
    notifyListeners();
  }

  // ── 폴더 ────────────────────────────────────────────────────────────────

  Future<void> createFolder(String tab, String parent, String name) async {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    if (clean.isEmpty) return;
    final path = _join(parent, clean);
    if (folders[tab]!.contains(path)) return;
    final ok = await fs.mkdir(_join(tabDirNames[tab]!, path));
    if (!ok) throw Exception('폴더를 만들지 못했습니다');
    folders[tab]!.add(path);
    folders[tab]!.sort();
    notifyListeners();
  }

  /// 폴더 삭제 — 바로 아래 하위 폴더와 파일은 루트로 옮긴 뒤 지운다 (웹과 같은 동작)
  Future<void> deleteFolder(String tab, String path) async {
    final childFolders = folders[tab]!.where((f) => parentOf(f) == path).toList();
    for (final child in childFolders) {
      await _relocateFolder(tab, child, baseName(child));
    }
    for (final item in items[tab]!.where((i) => i.folder == path).toList()) {
      await moveItem(item, '');
    }
    final ok = await fs.delete(_join(tabDirNames[tab]!, path));
    if (!ok) throw Exception('폴더를 지우지 못했습니다');
    folders[tab]!.removeWhere((f) => f == path || f.startsWith('$path/'));
    notifyListeners();
  }

  Future<void> renameFolder(String tab, String path, String name) async {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
    if (clean.isEmpty || clean == baseName(path)) return;
    await _relocateFolder(tab, path, _join(parentOf(path), clean));
  }

  Future<void> moveFolder(String tab, String path, String newParent) async {
    if (newParent == path || newParent.startsWith('$path/')) return;
    if (parentOf(path) == newParent) return;
    await _relocateFolder(tab, path, _join(newParent, baseName(path)));
  }

  /// 폴더를 통째로 옮긴다 — 새 위치에 폴더·파일을 다시 쓰고 옛 폴더를 지운다
  /// (브라우저 저장 방식에는 폴더 이동 기능이 없어서 모든 플랫폼에서 같은 방법을 쓴다)
  Future<void> _relocateFolder(String tab, String from, String to) async {
    if (from == to) return;
    if (folders[tab]!.contains(to)) throw Exception('같은 이름의 폴더가 이미 있습니다');
    final prefix = tabDirNames[tab]!;
    final affectedFolders = folders[tab]!.where((f) => f == from || f.startsWith('$from/')).toList();
    for (final f in affectedFolders) {
      await fs.mkdir(_join(prefix, to + f.substring(from.length)));
    }
    for (final item in items[tab]!.where((i) => i.folder == from || i.folder.startsWith('$from/')).toList()) {
      final newFolder = to + item.folder.substring(from.length);
      item.folder = newFolder;
      item.fileName = null;
      await _write(item);
    }
    await fs.delete(_join(prefix, from));
    folders[tab] = [
      ...folders[tab]!.where((f) => !affectedFolders.contains(f)),
      ...affectedFolders.map((f) => to + f.substring(from.length)),
    ]..sort();
    notifyListeners();
  }

  // ── 강해 시리즈 맥락 (웹 getSeriesContext 와 같은 문장) ─────────────────────────

  /// 같은 "구분"(시리즈명)의 다른 설교들을 만든 순서대로 요약 — 본문 메시지(새벽은 핵심 메시지) 앞 300자
  String getSeriesContext(String type, String? seriesName, String currentId) {
    if (seriesName == null || seriesName.trim().isEmpty) return '';
    final list = items[type]!.where((i) => i.category == seriesName && i.id != currentId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (list.isEmpty) return '';
    // 단계 순서가 바뀌어도 어긋나지 않도록 번호 대신 단계 이름으로 찾는다
    final coreKey = type == 'sermon' ? 'message' : 'core_message';
    final coreIndex = stepsForTab(type).firstWhere((s) => s.key == coreKey).index;
    final lines = ['[강해 시리즈: $seriesName] 이전에 다룬 본문들:'];
    for (final i in list) {
      final content = i.steps[coreIndex];
      final summary = (content == null || content.isEmpty)
          ? '(내용 미생성)'
          : (content.length > 300 ? content.substring(0, 300) : content).replaceAll('\n', ' ');
      lines.add('- ${i.date} | ${(i.passage == null || i.passage!.isEmpty) ? '본문 미지정' : i.passage} | $summary');
    }
    return lines.join('\n');
  }

  // ── 기억된 지시어 · 학습 메모리 · 사용자 지시항목 ───────────────────────────

  String keywordFor(String tab, String stepKey) => defaultKeywords['${tab}_$stepKey'] ?? '';

  Future<void> setKeyword(String tab, String stepKey, String value) async {
    if (value.trim().isEmpty) {
      defaultKeywords.remove('${tab}_$stepKey');
    } else {
      defaultKeywords['${tab}_$stepKey'] = value.trim();
    }
    await saveSettings();
  }

  Future<void> removeKeyword(String key) async {
    defaultKeywords.remove(key);
    await saveSettings();
  }

  Future<void> addMemory(String tab, String stepKey, String text) async {
    if (text.trim().isEmpty) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    (memories['${tab}_$stepKey'] ??= []).add(MemoryEntry(text.trim(), today));
    await saveSettings();
  }

  Future<void> deleteMemory(String key, int index) async {
    final list = memories[key];
    if (list == null || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) memories.remove(key);
    await saveSettings();
  }

  /// 웹 memory.js buildMemoryPrompt 와 같은 문장
  String buildMemoryPrompt(String tab, String stepKey) {
    final list = memories['${tab}_$stepKey'] ?? [];
    if (list.isEmpty) return '';
    return '[작성자 학습 메모리 — 아래 내용을 항상 반영하세요]\n${list.map((m) => '- ${m.text}').join('\n')}';
  }

  List<CustomStepItem> customItemsForTab(String tab) => customStepItems.where((c) => c.tab == tab).toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  List<CustomStepItem> customItemsFor(String tab, String stepKey) =>
      customStepItems.where((c) => c.tab == tab && c.stepKey == stepKey).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  Future<void> addCustomItem(String tab, String stepKey, String label) async {
    final existing = customItemsFor(tab, stepKey);
    customStepItems.add(CustomStepItem(
      id: _uuid.v4(),
      tab: tab,
      stepKey: stepKey,
      label: label,
      text: '- $label',
      order: existing.isEmpty ? 0 : existing.last.order + 1,
    ));
    await saveSettings();
  }

  Future<void> deleteCustomItem(String id) async {
    customStepItems.removeWhere((c) => c.id == id);
    await saveSettings();
  }

  Future<void> setCustomItemOrders(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      for (final c in customStepItems) {
        if (c.id == orderedIds[i]) c.order = i;
      }
    }
    await saveSettings();
  }

  // ── 백업 (웹 exportAllData 와 같은 형식, version 2) ─────────────────────────

  static const _tabKeys = {
    'sermon': ('sermons', 'sermonSteps', 'sermonId'),
    'worship': ('worships', 'worshipSteps', 'worshipId'),
    'dawn': ('dawns', 'dawnSteps', 'dawnId'),
    'cell': ('cells', 'cellSteps', 'cellId'),
  };

  /// 전체를 웹 백업과 같은 형식으로 — 폴더 id 는 폴더 경로를 쓴다
  Map<String, dynamic> exportBackup() {
    final data = <String, dynamic>{};
    final folderList = <Map<String, dynamic>>[];
    for (final t in tabs) {
      for (final f in folders[t]!) {
        folderList.add({'id': '$t:$f', 'tab': t, 'name': baseName(f), 'parentId': parentOf(f).isEmpty ? null : '$t:${parentOf(f)}', 'createdAt': 0});
      }
      final (listKey, stepsKey, idKey) = _tabKeys[t]!;
      data[listKey] = [
        for (final i in items[t]!)
          {
            'id': i.id, 'date': i.date, 'category': i.category, 'title': i.title, 'passage': i.passage,
            'emphasis': i.emphasis, 'season': i.season, 'lectionary': i.lectionary, 'draft': i.draft,
            'folderId': i.folder.isEmpty ? null : '$t:${i.folder}', 'createdAt': i.createdAt,
          }
      ];
      data[stepsKey] = [
        for (final i in items[t]!)
          for (final e in i.steps.entries)
            {idKey: i.id, 'stepIndex': e.key, 'content': e.value, if (t == 'cell') 'finalContent': i.finalSteps[e.key]}
      ];
    }
    data['folders'] = folderList;
    data['customStepItems'] = [for (final c in customStepItems) c.toJson()];
    data['keywords'] = defaultKeywords.map((k, v) => MapEntry('defaultKeyword_$k', v));
    return {'version': 2, 'exportedAt': DateTime.now().toUtc().toIso8601String(), 'data': data};
  }

  /// 웹 백업 파일 불러오기 — 기존 파일은 그대로 두고, 없는 것만 더한다. 더한 항목 수 반환
  Future<int> importBackup(Map<String, dynamic> json) async {
    final data = json['data'];
    if (json['version'] == null || data is! Map) throw Exception('잘못된 파일 형식입니다.');

    // 폴더 id → 경로
    final rawFolders = [for (final f in (data['folders'] as List? ?? [])) f as Map];
    final byId = {for (final f in rawFolders) '${f['id']}': f};
    String pathOf(String id, [int guard = 0]) {
      final f = byId[id];
      if (f == null || guard > 50) return '';
      final name = '${f['name']}'.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim();
      final parent = f['parentId'] == null ? '' : pathOf('${f['parentId']}', guard + 1);
      return _join(parent, name);
    }

    for (final f in rawFolders) {
      final tab = '${f['tab']}';
      if (!tabs.contains(tab)) continue;
      final path = pathOf('${f['id']}');
      if (path.isEmpty || folders[tab]!.contains(path)) continue;
      await fs.mkdir(_join(tabDirNames[tab]!, path));
      folders[tab]!.add(path);
    }

    var added = 0;
    for (final t in tabs) {
      final (listKey, stepsKey, idKey) = _tabKeys[t]!;
      final stepRows = [for (final s in (data[stepsKey] as List? ?? [])) s as Map];
      for (final raw in (data[listKey] as List? ?? [])) {
        final r = raw as Map;
        final id = '${r['id']}';
        if (find(t, id) != null) continue;
        String? s(String k) => r[k] is String ? r[k] as String : null;
        final item = Item(
          id: id,
          tab: t,
          createdAt: (r['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          date: s('date'), category: s('category'), title: s('title'), passage: s('passage'),
          emphasis: s('emphasis'), season: s('season'), lectionary: s('lectionary'), draft: s('draft'),
          folder: r['folderId'] == null ? '' : pathOf('${r['folderId']}'),
        );
        for (final st in stepRows.where((st) => '${st[idKey]}' == id)) {
          final idx = (st['stepIndex'] as num?)?.toInt();
          if (idx == null) continue;
          if (st['content'] is String) item.steps[idx] = st['content'] as String;
          if (st['finalContent'] is String && (st['finalContent'] as String).isNotEmpty) item.finalSteps[idx] = st['finalContent'] as String;
        }
        await _write(item);
        items[t]!.add(item);
        added++;
      }
      items[t]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      folders[t]!.sort();
    }

    final existingIds = customStepItems.map((c) => c.id).toSet();
    for (final c in (data['customStepItems'] as List? ?? [])) {
      final item = CustomStepItem.fromJson(c as Map);
      if (!existingIds.contains(item.id)) customStepItems.add(item);
    }
    (data['keywords'] as Map? ?? {}).forEach((k, v) {
      final key = '$k'.startsWith('defaultKeyword_') ? '$k'.substring('defaultKeyword_'.length) : '$k';
      defaultKeywords[key] = '$v';
    });
    await saveSettings();
    return added;
  }
}
