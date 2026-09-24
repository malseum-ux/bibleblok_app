// 저장소(폴더 저장) 시험 — 메모리 속 가짜 폴더로 실제 파일을 건드리지 않고 검사한다
import 'dart:convert';

import 'package:bibleblok_app/services/fs/data_fs.dart';
import 'package:bibleblok_app/services/store.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryFs implements DataFs {
  final files = <String, String>{};
  final dirs = <String>{};

  void _addDirs(String path) {
    final parts = path.split('/');
    for (var i = 1; i <= parts.length; i++) {
      dirs.add(parts.sublist(0, i).join('/'));
    }
  }

  @override
  String get displayName => 'Memory';

  @override
  Future<FsTree> listTree() async => FsTree(dirs.toList(), files.keys.toList());

  @override
  Future<String?> readText(String path) async => files[path];

  @override
  Future<bool> writeText(String path, String text) async {
    files[path] = text;
    if (path.contains('/')) _addDirs(path.substring(0, path.lastIndexOf('/')));
    return true;
  }

  @override
  Future<bool> mkdir(String path) async {
    _addDirs(path);
    return true;
  }

  @override
  Future<bool> delete(String path) async {
    files.remove(path);
    files.removeWhere((k, _) => k.startsWith('$path/'));
    dirs.removeWhere((d) => d == path || d.startsWith('$path/'));
    return true;
  }
}

void main() {
  late MemoryFs fs;
  late Store store;

  setUp(() async {
    fs = MemoryFs();
    store = Store(fs);
    await store.loadAll();
  });

  test('설교를 만들면 "날짜 제목.json" 파일이 생기고, 제목을 바꾸면 파일 이름도 바뀐다', () async {
    final item = await store.createItem('sermon', {'date': '2026-09-21', 'title': '아브라함의 부르심', 'passage': '창 12:1-9'}, '');
    expect(fs.files.keys, ['설교작성/2026-09-21 아브라함의 부르심.json']);
    item.title = '믿음의 조상';
    await store.saveItem(item);
    expect(fs.files.keys, ['설교작성/2026-09-21 믿음의 조상.json']);
  });

  test('같은 이름이면 (2) 를 붙인다', () async {
    await store.createItem('sermon', {'date': '2026-09-21', 'title': '같은 제목'}, '');
    await store.createItem('sermon', {'date': '2026-09-21', 'title': '같은 제목'}, '');
    expect(fs.files.keys.toSet(), {'설교작성/2026-09-21 같은 제목.json', '설교작성/2026-09-21 같은 제목 (2).json'});
  });

  test('다시 불러와도 내용·폴더가 그대로다', () async {
    await store.createFolder('sermon', '', '창세기 강해');
    final item = await store.createItem('sermon', {'date': '2026-09-21', 'title': 'A'}, '창세기 강해');
    await store.saveStep(item, 4, '본문 메시지 내용');
    final again = Store(fs);
    await again.loadAll();
    expect(again.folders['sermon'], ['창세기 강해']);
    final loaded = again.items['sermon']!.single;
    expect(loaded.folder, '창세기 강해');
    expect(loaded.steps[4], '본문 메시지 내용');
  });

  test('파일을 폴더로 옮기면 실제 파일도 옮겨진다', () async {
    await store.createFolder('sermon', '', '강해');
    final item = await store.createItem('sermon', {'date': '2026-09-21', 'title': 'A'}, '');
    await store.moveItem(item, '강해');
    expect(fs.files.keys, ['설교작성/강해/2026-09-21 A.json']);
    expect(item.folder, '강해');
  });

  test('폴더 이름을 바꾸면 하위 폴더와 파일이 함께 옮겨진다', () async {
    await store.createFolder('sermon', '', '창세기');
    await store.createFolder('sermon', '창세기', '1부');
    await store.createItem('sermon', {'date': '2026-09-21', 'title': 'A'}, '창세기/1부');
    await store.renameFolder('sermon', '창세기', '창세기 강해');
    expect(store.folders['sermon'], ['창세기 강해', '창세기 강해/1부']);
    expect(fs.files.keys, ['설교작성/창세기 강해/1부/2026-09-21 A.json']);
    expect(fs.dirs.any((d) => d == '설교작성/창세기'), isFalse);
  });

  test('폴더를 다른 폴더 안으로 옮긴다 (자기 안으로는 못 옮긴다)', () async {
    await store.createFolder('sermon', '', 'A');
    await store.createFolder('sermon', '', 'B');
    await store.createItem('sermon', {'date': '2026-09-21', 'title': 'x'}, 'A');
    await store.moveFolder('sermon', 'A', 'B');
    expect(store.folders['sermon'], ['B', 'B/A']);
    expect(fs.files.keys, ['설교작성/B/A/2026-09-21 x.json']);
    await store.moveFolder('sermon', 'B', 'B/A');
    expect(store.folders['sermon'], ['B', 'B/A']);
  });

  test('폴더를 지우면 바로 아래 하위 폴더와 파일은 루트로 옮겨진다 (웹과 같은 동작)', () async {
    await store.createFolder('sermon', '', 'A');
    await store.createFolder('sermon', 'A', 'B');
    await store.createFolder('sermon', 'A/B', 'C');
    await store.createItem('sermon', {'date': '2026-09-21', 'title': 'in A'}, 'A');
    await store.createItem('sermon', {'date': '2026-09-22', 'title': 'in C'}, 'A/B/C');
    await store.deleteFolder('sermon', 'A');
    expect(store.folders['sermon'], ['B', 'B/C']);
    expect(fs.files.keys.toSet(), {'설교작성/2026-09-21 in A.json', '설교작성/B/C/2026-09-22 in C.json'});
  });

  test('웹 백업 파일을 불러오면 폴더 구조·단계 내용·지시어가 옮겨진다', () async {
    final backup = {
      'version': 2,
      'data': {
        'folders': [
          {'id': 'f1', 'tab': 'sermon', 'name': '창세기 강해', 'parentId': null},
          {'id': 'f2', 'tab': 'sermon', 'name': '1부', 'parentId': 'f1'},
        ],
        'sermons': [
          {'id': 's1', 'date': '2026-09-01', 'title': '태초에', 'passage': '창 1:1', 'folderId': 'f2', 'draft': '<p>초안</p>', 'createdAt': 1},
        ],
        'sermonSteps': [
          {'sermonId': 's1', 'stepIndex': 4, 'content': '메시지'},
        ],
        'cells': [
          {'id': 'c1', 'passage': '요 8:1-11', 'title': null, 'date': null, 'folderId': null, 'createdAt': 2},
        ],
        'cellSteps': [
          {'cellId': 'c1', 'stepIndex': 0, 'content': '나눔', 'finalContent': ''},
        ],
        'customStepItems': [
          {'id': 'x1', 'tab': 'sermon', 'stepKey': 'message', 'label': '청년', 'text': '- 청년', 'order': 0},
        ],
        'keywords': {'defaultKeyword_sermon_message': '청년 대상'},
      },
    };
    final added = await store.importBackup(backup);
    expect(added, 2);
    expect(store.folders['sermon'], ['창세기 강해', '창세기 강해/1부']);
    expect(fs.files.containsKey('설교작성/창세기 강해/1부/2026-09-01 태초에.json'), isTrue);
    expect(fs.files.containsKey('교재작성/요 8 1-11.json'), isTrue);
    final s = store.items['sermon']!.single;
    expect(s.steps[4], '메시지');
    expect(s.draft, '<p>초안</p>');
    expect(store.keywordFor('sermon', 'message'), '청년 대상');
    expect(store.customItemsFor('sermon', 'message').single.label, '청년');

    // 같은 백업을 다시 불러와도 겹쳐 생기지 않는다
    expect(await store.importBackup(backup), 0);

    // 내보내기 → 새 폴더에 불러오기 하면 같은 내용
    final exported = jsonDecode(jsonEncode(store.exportBackup())) as Map<String, dynamic>;
    final other = Store(MemoryFs());
    await other.loadAll();
    expect(await other.importBackup(exported), 2);
    expect(other.folders['sermon'], ['창세기 강해', '창세기 강해/1부']);
    expect(other.items['sermon']!.single.steps[4], '메시지');
  });

  test('학습 메모리와 기억된 지시어는 settings.json 에 저장된다', () async {
    await store.addMemory('sermon', 'message', '짧게 써 줘');
    await store.setKeyword('sermon', 'message', '청년');
    final again = Store(fs);
    await again.loadAll();
    expect(again.buildMemoryPrompt('sermon', 'message'), contains('- 짧게 써 줘'));
    expect(again.keywordFor('sermon', 'message'), '청년');
  });
}
