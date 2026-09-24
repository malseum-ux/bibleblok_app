// 웹 데이터 가져오기 — Supabase 표 → 웹 백업 형식 → 폴더
import 'package:bibleblok_app/services/store.dart';
import 'package:bibleblok_app/services/web_import.dart';
import 'package:flutter_test/flutter_test.dart';

import 'memory_fs.dart';

void main() {
  test('Supabase 표를 읽어 폴더로 옮긴다 (웹과 같은 필드 이름)', () async {
    final tables = <String, List<Map<String, dynamic>>>{
      'folders': [
        {'id': 'f1', 'user_id': 'u', 'tab': 'sermon', 'name': '로마서 강해', 'parent_id': null, 'created_at': 1},
      ],
      'sermons': [
        {'id': 's1', 'user_id': 'u', 'date': '2026-08-02', 'category': '로마서 강해', 'title': '복음의 능력', 'passage': '롬 1:16-17', 'emphasis': null, 'draft': '<p>초안</p>', 'folder_id': 'f1', 'created_at': 5},
      ],
      'sermon_steps': [
        {'id': 'x', 'user_id': 'u', 'sermon_id': 's1', 'step_index': 4, 'content': '본문 메시지'},
      ],
      'worships': [
        {'id': 'w1', 'user_id': 'u', 'date': '2026-08-02', 'season': '오순절 후 10번째 주일', 'title': null, 'passage': null, 'draft': null, 'folder_id': null, 'created_at': 6},
      ],
      'worship_steps': [
        {'id': 'y', 'user_id': 'u', 'worship_id': 'w1', 'step_index': 0, 'content': '예배 순서'},
      ],
      'dawns': [],
      'dawn_steps': [],
      'cells': [],
      'cell_steps': [],
      'custom_step_items': [
        {'id': 'c1', 'user_id': 'u', 'tab': 'sermon', 'step_key': 'message', 'label': '청년', 'text': '- 청년', 'order': 0},
      ],
    };
    final backup = await buildWebBackup((t) async => tables[t]!);
    final store = Store(MemoryFs());
    await store.loadAll();
    expect(await store.importBackup(backup), 2);
    final s = store.items['sermon']!.single;
    expect(s.folder, '로마서 강해');
    expect(s.steps[4], '본문 메시지');
    expect(s.draft, '<p>초안</p>');
    expect(store.items['worship']!.single.season, '오순절 후 10번째 주일');
    expect(store.customItemsFor('sermon', 'message').single.text, '- 청년');
    // 다시 가져와도 겹치지 않는다
    expect(await store.importBackup(await buildWebBackup((t) async => tables[t]!)), 0);
  });
}
