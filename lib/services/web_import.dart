// 웹 바이블블록 데이터 가져오기 — 같은 계정으로 로그인했으면 Supabase 에 있는 내 설교·교재를 읽어 폴더로 옮긴다
// 웹 db.js exportAllData 와 같은 형식(version 2)으로 바꾼 뒤, 백업 불러오기(Store.importBackup)에 그대로 넘긴다.
// Supabase 의 원본은 지우지 않는다. (웹 브라우저에만 있던 기억된 지시어·학습 메모리는 읽을 수 없다)
import 'package:supabase_flutter/supabase_flutter.dart';

typedef RowsFetcher = Future<List<Map<String, dynamic>>> Function(String table);

/// Supabase 에서 한 표 전체를 읽는다 — 한 번에 1000줄까지라 나눠서 읽는다
Future<List<Map<String, dynamic>>> fetchAllRows(String table) async {
  final sb = Supabase.instance.client;
  const page = 1000;
  final out = <Map<String, dynamic>>[];
  for (var from = 0;; from += page) {
    final rows = await sb.from(table).select().range(from, from + page - 1);
    out.addAll(rows.map((r) => Map<String, dynamic>.from(r)));
    if (rows.length < page) break;
  }
  return out;
}

/// 표 이름 → 웹 백업 항목 (db.js 의 mapSermon 등과 같은 이름 바꾸기)
Future<Map<String, dynamic>> buildWebBackup([RowsFetcher fetch = fetchAllRows]) async {
  List<Map<String, dynamic>> map(List<Map<String, dynamic>> rows, Map<String, String> fields) => [
        for (final r in rows) {for (final e in fields.entries) e.value: r[e.key]},
      ];
  const item = {'id': 'id', 'date': 'date', 'title': 'title', 'passage': 'passage', 'draft': 'draft', 'folder_id': 'folderId', 'created_at': 'createdAt'};

  final results = await Future.wait([
    for (final t in ['sermons', 'sermon_steps', 'worships', 'worship_steps', 'dawns', 'dawn_steps', 'folders', 'cells', 'cell_steps', 'custom_step_items']) fetch(t),
  ]);
  final [sermons, sermonSteps, worships, worshipSteps, dawns, dawnSteps, folders, cells, cellSteps, custom] = results;

  return {
    'version': 2,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'data': {
      'sermons': map(sermons, {...item, 'category': 'category', 'emphasis': 'emphasis'}),
      'sermonSteps': map(sermonSteps, {'sermon_id': 'sermonId', 'step_index': 'stepIndex', 'content': 'content'}),
      'worships': map(worships, {...item, 'season': 'season'}),
      'worshipSteps': map(worshipSteps, {'worship_id': 'worshipId', 'step_index': 'stepIndex', 'content': 'content'}),
      'dawns': map(dawns, {...item, 'category': 'category', 'season': 'season', 'emphasis': 'emphasis'}),
      'dawnSteps': map(dawnSteps, {'dawn_id': 'dawnId', 'step_index': 'stepIndex', 'content': 'content'}),
      'folders': map(folders, {'id': 'id', 'tab': 'tab', 'name': 'name', 'parent_id': 'parentId', 'created_at': 'createdAt'}),
      'cells': map(cells, {'id': 'id', 'passage': 'passage', 'title': 'title', 'date': 'date', 'folder_id': 'folderId', 'created_at': 'createdAt'}),
      'cellSteps': map(cellSteps, {'cell_id': 'cellId', 'step_index': 'stepIndex', 'content': 'content', 'final_content': 'finalContent'}),
      'customStepItems': map(custom, {'id': 'id', 'tab': 'tab', 'step_key': 'stepKey', 'label': 'label', 'text': 'text', 'order': 'order'}),
      'keywords': <String, String>{},
    },
  };
}
