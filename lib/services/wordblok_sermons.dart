// 성경나침반(wordblok) 내설교 읽기·수정 — 설교작성 사이드 목록에 보여 주고, 고치면 원래 .scb 에 저장한다
// 웹 앱(bibleblok/src/wordblokSermons.js)과 같은 규칙.
//
// 내설교 폴더: .scb 파일(SQLite)들. 표 Bible(id, book, chapter, verse, btext, date)
//   btext = '[제목]\n\n본문' (앞 [제목] 이 제목)
// 폴더 연결은 기기마다 다르다.
//   웹       브라우저 File System Access API — 저장 폴더와 같은 IndexedDB(bb-folders)에 다른 키로 보관 (web/index.html 의 bbWb* 함수)
//            목록은 읽기 권한으로 읽고, 저장할 때 쓰기 권한을 묻는다 (저장 버튼 클릭 안에서)
//   네이티브  폴더 경로를 SharedPreferences 에 보관 (Mac 앱은 보안 범위 북마크도 함께)
import 'package:flutter/foundation.dart';

import 'wordblok/wb_native_stub.dart' if (dart.library.io) 'wordblok/wb_native.dart' as native;
import 'wordblok/wb_web_stub.dart' if (dart.library.js_interop) 'wordblok/wb_web.dart' as web;

/// 설교 한 편 (본문은 빼고 제목·날짜·구절만)
class WordblokItem {
  final String key; // '파일경로#id'
  final String path; // 내설교 폴더 기준 .scb 파일 경로
  final int id;
  final String title;
  final String date;
  final int? book;
  final int? chapter;
  final int? verse;
  const WordblokItem({
    required this.key,
    required this.path,
    required this.id,
    required this.title,
    required this.date,
    this.book,
    this.chapter,
    this.verse,
  });

  /// 구절을 바꾼 새 항목 (저장 뒤 목록·보기 화면에 반영)
  WordblokItem withRef(int? book, int? chapter, int? verse) =>
      WordblokItem(key: key, path: path, id: id, title: title, date: date, book: book, chapter: chapter, verse: verse);
}

/// .scb 파일 하나 — file: 파일 이름('2000 양성득설교'), items: 설교 목록
class WordblokGroup {
  final String file;
  final String path;
  final List<WordblokItem> items;
  const WordblokGroup({required this.file, required this.path, required this.items});
}

// 책 번호 → 약칭 (본문 표시용)
const _bookAbbr = [
  '', '창', '출', '레', '민', '신', '수', '삿', '룻', '삼상', '삼하', '왕상', '왕하', '대상', '대하', '스', '느', '에', '욥', '시', '잠',
  '전', '아', '사', '렘', '애', '겔', '단', '호', '욜', '암', '옵', '욘', '미', '나', '합', '습', '학', '슥', '말',
  '마', '막', '눅', '요', '행', '롬', '고전', '고후', '갈', '엡', '빌', '골', '살전', '살후', '딤전', '딤후', '딛', '몬', '히', '약',
  '벧전', '벧후', '요일', '요이', '요삼', '유', '계',
];

/// '요 3:16' — 책 번호가 없으면 ''
String passageLabel(int? book, int? chapter, int? verse) {
  if (book == null || book <= 0 || book >= _bookAbbr.length) return '';
  return '${_bookAbbr[book]} $chapter:$verse';
}

String wordblokFolderName() => web.isWeb ? web.folderName() : native.folderName();

/// 권한이 풀려 다시 허용을 기다리는 중인지
bool wordblokPermissionNeeded() => web.isWeb ? web.permissionNeeded() : native.permissionNeeded();

/// 폴더 선택 — 폴더 이름 반환 (취소하면 null, 실패하면 예외)
Future<String?> pickWordblokFolder() => web.isWeb ? web.pick() : native.pick();

/// 앱을 다시 켠 뒤 복원 — 폴더에 들어갈 수 있으면 폴더 이름, 아니면 null
Future<String?> restoreWordblokFolder() => web.isWeb ? web.restore() : native.restore();

/// 권한 다시 요청 — 사용자 클릭 안에서 호출해야 한다
Future<String?> requestWordblokPermission() => web.isWeb ? web.requestPermission() : native.requestPermission();

/// 새로고침: 열어 둔 파일을 닫아 다시 읽게 한다
void clearWordblokCache() {
  if (web.isWeb) {
    web.clearCache();
  } else {
    native.clearCache();
  }
}

Future<List<String>> _listScb() => web.isWeb ? web.listScb() : native.listScb();

/// 한 파일에 SQL 실행 — 행마다 값 목록 (파일을 열지 못하면 예외)
Future<List<List<Object?>>> _query(String path, String sql, [List<Object?> args = const []]) =>
    web.isWeb ? web.query(path, sql, args) : native.query(path, sql, args);

final _titleRe = RegExp(r'^\s*\[([^\]]+)\]');
final _headerRe = RegExp(r'^\s*\[[^\]]*\]\s*(\[[^\]]*\]\s*)?\n*');

int? _int(Object? v) => v is num ? v.toInt() : (v == null ? null : int.tryParse('$v'));

/// 파일별 설교 목록 (본문은 빼고 제목·날짜·구절만). 설교가 없는 파일은 뺀다.
Future<List<WordblokGroup>> loadWordblokSermons() async {
  if (wordblokFolderName().isEmpty) return [];
  final groups = <WordblokGroup>[];
  for (final path in await _listScb()) {
    final file = path.split('/').last.replaceFirst(RegExp(r'\.scb$', caseSensitive: false), '');
    final items = <WordblokItem>[];
    try {
      final rows = await _query(path, 'SELECT id, book, chapter, verse, substr(btext, 1, 200), date FROM Bible ORDER BY date, id');
      for (final r in rows) {
        final id = _int(r[0]) ?? 0;
        final m = _titleRe.firstMatch('${r[4] ?? ''}');
        items.add(WordblokItem(
          key: '$path#$id',
          path: path,
          id: id,
          title: m != null ? m.group(1)!.trim() : file,
          date: '${r[5] ?? ''}',
          book: _int(r[1]),
          chapter: _int(r[2]),
          verse: _int(r[3]),
        ));
      }
    } catch (e) {
      debugPrint('[bb] scb read failed $path $e');
    }
    if (items.isNotEmpty) groups.add(WordblokGroup(file: file, path: path, items: items));
  }
  return groups;
}

/// 설교 한 편의 본문 (앞 [제목] 줄은 뺀다)
Future<String> readWordblokSermon(String path, int id) async {
  final rows = await _query(path, 'SELECT btext FROM Bible WHERE id = ?', [id]);
  final btext = rows.isEmpty ? '' : '${rows.first.first ?? ''}';
  return btext.replaceFirst(_headerRe, '').trim();
}

// ── 수정 저장 ────────────────────────────────────────────────────

// 구절 글자 → 책·장·절 ('요 3:16', '요한복음 3장 16절')
final Map<String, int> _bookNames = {
  '창세기': 1, '출애굽기': 2, '레위기': 3, '민수기': 4, '신명기': 5, '여호수아': 6, '사사기': 7, '룻기': 8, '사무엘상': 9, '사무엘하': 10,
  '열왕기상': 11, '열왕기하': 12, '역대상': 13, '역대하': 14, '에스라': 15, '느헤미야': 16, '에스더': 17, '욥기': 18, '시편': 19, '잠언': 20,
  '전도서': 21, '아가': 22, '이사야': 23, '예레미야': 24, '예레미야애가': 25, '에스겔': 26, '다니엘': 27, '호세아': 28, '요엘': 29, '아모스': 30,
  '오바댜': 31, '요나': 32, '미가': 33, '나훔': 34, '하박국': 35, '스바냐': 36, '학개': 37, '스가랴': 38, '말라기': 39,
  '마태복음': 40, '마가복음': 41, '누가복음': 42, '요한복음': 43, '사도행전': 44, '로마서': 45, '고린도전서': 46, '고린도후서': 47,
  '갈라디아서': 48, '에베소서': 49, '빌립보서': 50, '골로새서': 51, '데살로니가전서': 52, '데살로니가후서': 53, '디모데전서': 54, '디모데후서': 55,
  '디도서': 56, '빌레몬서': 57, '히브리서': 58, '야고보서': 59, '베드로전서': 60, '베드로후서': 61, '요한일서': 62, '요한이서': 63, '요한삼서': 64,
  '유다서': 65, '요한계시록': 66, '계시록': 66, '마태': 40, '마가': 41, '누가': 42, '요한': 43,
  for (var i = 1; i < _bookAbbr.length; i++) _bookAbbr[i]: i,
};
final _nameRe = RegExp(
  '^\\s*(${(_bookNames.keys.toList()..sort((a, b) => b.length - a.length)).join('|')})\\s*(\\d{1,3})(?:\\s*[장:]\\s*(\\d{1,3}))?',
);

/// 구절 글자를 책·장·절로 — 못 알아보면 null (절이 없으면 1절)
({int book, int chapter, int verse})? parsePassage(String? text) {
  final m = _nameRe.firstMatch(text ?? '');
  if (m == null) return null;
  return (book: _bookNames[m.group(1)]!, chapter: int.parse(m.group(2)!), verse: m.group(3) != null ? int.parse(m.group(3)!) : 1);
}

/// 설교 한 편을 고쳐 원래 .scb 에 저장한다 (앞 [제목] 줄은 그대로 두고 본문만 바꾼다).
/// refText 를 못 알아보면 구절은 그대로. 웹은 저장 버튼 클릭 안에서 불러야 쓰기 권한 창이 뜬다.
/// 반환: 바뀐 책·장·절
Future<({int? book, int? chapter, int? verse})> saveWordblokSermon(String path, int id, String refText, String text) async {
  if (web.isWeb) {
    await web.beginWrite(path);
  } else {
    await native.beginWrite(path);
  }
  final rows = await _query(path, 'SELECT book, chapter, verse, btext FROM Bible WHERE id = ?', [id]);
  final row = rows.isEmpty ? const <Object?>[null, null, null, null] : rows.first;
  final header = _headerRe.firstMatch('${row[3] ?? ''}')?.group(0) ?? '';
  final parsed = parsePassage(refText);
  final ref = parsed != null
      ? (book: parsed.book, chapter: parsed.chapter, verse: parsed.verse)
      : (book: _int(row[0]), chapter: _int(row[1]), verse: _int(row[2]));
  const sql = 'UPDATE Bible SET book = ?, chapter = ?, verse = ?, btext = ? WHERE id = ?';
  final args = [ref.book, ref.chapter, ref.verse, header + text, id];
  if (web.isWeb) {
    await web.update(path, sql, args);
  } else {
    await native.update(path, sql, args);
  }
  return ref;
}
