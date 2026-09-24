// 설교·예배·새벽·교재 한 건 = 저장 폴더의 JSON 파일 하나
//
// 파일 형식 (version 1)
// {
//   "app": "bibleblok", "version": 1, "tab": "sermon",
//   "id": "...", "createdAt": 1727000000000,
//   "date": "2026-09-21", "category": "", "title": "", "passage": "",
//   "emphasis": "", "season": "", "lectionary": "", "draft": "<p>...</p>",
//   "steps": { "0": "...", "4": "..." },
//   "finalSteps": { }          ← 교재만 사용
// }

class Item {
  final String id;
  final String tab;
  final int createdAt;
  String? date;
  String? category;
  String? title;
  String? passage;
  String? emphasis;
  String? season;
  String? lectionary;
  String? draft;
  Map<int, String> steps;
  Map<int, String> finalSteps;

  /// 탭 폴더 안에서의 폴더 경로 ('' = 루트)
  String folder;

  /// 지금 저장되어 있는 파일 이름 (이름이 바뀌면 파일도 새 이름으로 옮긴다)
  String? fileName;

  Item({
    required this.id,
    required this.tab,
    required this.createdAt,
    this.date,
    this.category,
    this.title,
    this.passage,
    this.emphasis,
    this.season,
    this.lectionary,
    this.draft,
    Map<int, String>? steps,
    Map<int, String>? finalSteps,
    this.folder = '',
    this.fileName,
  })  : steps = steps ?? {},
        finalSteps = finalSteps ?? {};

  static Map<int, String> _intMap(Object? raw) {
    if (raw is! Map) return {};
    final out = <int, String>{};
    raw.forEach((k, v) {
      final i = int.tryParse(k.toString());
      if (i != null && v is String) out[i] = v;
    });
    return out;
  }

  factory Item.fromJson(Map<String, dynamic> j, {required String folder, required String fileName}) {
    String? s(String k) => j[k] is String ? j[k] as String : null;
    return Item(
      id: s('id') ?? fileName,
      tab: s('tab') ?? 'sermon',
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      date: s('date'),
      category: s('category'),
      title: s('title'),
      passage: s('passage'),
      emphasis: s('emphasis'),
      season: s('season'),
      lectionary: s('lectionary'),
      draft: s('draft'),
      steps: _intMap(j['steps']),
      finalSteps: _intMap(j['finalSteps']),
      folder: folder,
      fileName: fileName,
    );
  }

  Map<String, dynamic> toJson() => {
        'app': 'bibleblok',
        'version': 1,
        'tab': tab,
        'id': id,
        'createdAt': createdAt,
        'date': date,
        'category': category,
        'title': title,
        'passage': passage,
        'emphasis': emphasis,
        'season': season,
        'lectionary': lectionary,
        'draft': draft,
        'steps': steps.map((k, v) => MapEntry('$k', v)),
        if (finalSteps.isNotEmpty) 'finalSteps': finalSteps.map((k, v) => MapEntry('$k', v)),
      };

  /// 사이드바 표시 이름 — 웹 Sidebar.getLabel 과 같은 규칙
  String label(String lang) {
    final d = date == null ? '' : date!.replaceAll('-', '').padRight(2).substring(2);
    final name = tab == 'worship'
        ? (lang == 'en' ? 'Worship' : '예배인도')
        : (_nonEmpty(title) ?? _nonEmpty(passage) ?? (lang == 'en' ? 'Untitled' : '제목 없음'));
    return d.isNotEmpty ? '$d $name' : name;
  }

  static String? _nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v;

  /// 저장 파일 이름 (확장자 포함) — "날짜 제목.json"
  String preferredFileName() {
    final name = tab == 'worship'
        ? '예배인도'
        : (_nonEmpty(title) ?? _nonEmpty(passage) ?? '제목 없음');
    final base = [if (_nonEmpty(date) != null) date!, name].join(' ');
    var safe = base.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (safe.startsWith('.')) safe = safe.substring(1);
    if (safe.length > 80) safe = safe.substring(0, 80).trim();
    if (safe.isEmpty) safe = id;
    return '$safe.json';
  }
}
