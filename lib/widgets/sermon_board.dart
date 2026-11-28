// 설교 메모판 — 설교작성 오른쪽 창의 [메모판] 탭 (Scapple 처럼 빈 종이에 메모를 흩어 놓고 잇기)
// 빈 곳 두 번 누르기 = 새 메모, 끌어 옮기기, 둘 고르고 잇기·끊기·화살표, 여럿 고르고 상자로 묶기, 색
// 왼쪽 단계 글을 끌어 놓거나 붙여 넣기, 고른 메모를 설계도 가지로 보내기, AI로 설계도 정리·초안 풀어 쓰기
// 저장: 설교 파일(JSON)의 "board" 칸
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import 'sermon_map.dart' show MapTextDrag;

int _seq = 0;
String _newId() => 'n${DateTime.now().microsecondsSinceEpoch}${_seq++}';

// 메모 색 (0 = 기본)
const boardColors = [Color(0xFFFFFFFF), Color(0xFFFFF4C2), Color(0xFFDDF4E4), Color(0xFFDCEBFF), Color(0xFFF7DDEB), Color(0xFFEDE7FF)];
const _darkBoardColors = [Color(0xFF252538), Color(0xFF3A3420), Color(0xFF1F3A2A), Color(0xFF1F2E45), Color(0xFF3A2230), Color(0xFF2E2848)];
const _groupColors = [Color(0xFF534AB7), Color(0xFFD99A1E), Color(0xFF16A34A), Color(0xFF2563EB), Color(0xFFDB2777), Color(0xFF0891B2)];

// ── 자료 ───────────────────────────────────────────────────────────────────

class BoardNote {
  final String id;
  String text;
  double x, y;
  int color;
  String source;

  BoardNote({String? id, required this.text, required this.x, required this.y, this.color = 0, this.source = ''}) : id = id ?? _newId();

  factory BoardNote.fromJson(Map<String, dynamic> j) => BoardNote(
    id: j['id'] as String?,
    text: (j['text'] ?? '') as String,
    x: (j['x'] as num?)?.toDouble() ?? 0,
    y: (j['y'] as num?)?.toDouble() ?? 0,
    color: (j['color'] as num?)?.toInt() ?? 0,
    source: (j['source'] ?? '') as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'x': x.roundToDouble(),
    'y': y.roundToDouble(),
    if (color != 0) 'color': color,
    if (source.isNotEmpty) 'source': source,
  };
}

class BoardLink {
  final String from, to;
  bool arrow;
  BoardLink(this.from, this.to, {this.arrow = false});

  factory BoardLink.fromJson(Map<String, dynamic> j) => BoardLink((j['from'] ?? '') as String, (j['to'] ?? '') as String, arrow: j['arrow'] == true);
  Map<String, dynamic> toJson() => {'from': from, 'to': to, if (arrow) 'arrow': true};
  bool joins(String a, String b) => (from == a && to == b) || (from == b && to == a);
}

class BoardGroup {
  final String id;
  String title;
  int color;
  List<String> noteIds;
  BoardGroup({String? id, this.title = '', this.color = 0, required this.noteIds}) : id = id ?? _newId();

  factory BoardGroup.fromJson(Map<String, dynamic> j) => BoardGroup(
    id: j['id'] as String?,
    title: (j['title'] ?? '') as String,
    color: (j['color'] as num?)?.toInt() ?? 0,
    noteIds: [for (final n in (j['notes'] as List? ?? const [])) '$n'],
  );
  Map<String, dynamic> toJson() => {'id': id, 'title': title, if (color != 0) 'color': color, 'notes': noteIds};
}

class SermonBoard {
  List<BoardNote> notes;
  List<BoardLink> links;
  List<BoardGroup> groups;
  SermonBoard({List<BoardNote>? notes, List<BoardLink>? links, List<BoardGroup>? groups}) : notes = notes ?? [], links = links ?? [], groups = groups ?? [];

  factory SermonBoard.fromJson(Object? raw) {
    if (raw is! Map) return SermonBoard();
    List<Map<String, dynamic>> list(String k) => [
      for (final e in (raw[k] as List? ?? const []))
        if (e is Map) e.cast<String, dynamic>(),
    ];
    final b = SermonBoard(
      notes: [for (final j in list('notes')) BoardNote.fromJson(j)],
      links: [for (final j in list('links')) BoardLink.fromJson(j)],
      groups: [for (final j in list('groups')) BoardGroup.fromJson(j)],
    );
    b.cleanup();
    return b;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'notes': [for (final n in notes) n.toJson()],
    if (links.isNotEmpty) 'links': [for (final l in links) l.toJson()],
    if (groups.isNotEmpty) 'groups': [for (final g in groups) g.toJson()],
  };

  bool get isEmpty => notes.every((n) => n.text.trim().isEmpty);

  BoardNote? note(String id) => notes.where((n) => n.id == id).firstOrNull;

  /// 없는 메모를 가리키는 선·묶음 정리
  void cleanup() {
    final ids = {for (final n in notes) n.id};
    links.removeWhere((l) => !ids.contains(l.from) || !ids.contains(l.to) || l.from == l.to);
    for (final g in groups) {
      g.noteIds.removeWhere((id) => !ids.contains(id));
    }
    groups.removeWhere((g) => g.noteIds.isEmpty);
  }

  void removeNotes(Iterable<String> ids) {
    final s = ids.toSet();
    notes.removeWhere((n) => s.contains(n.id));
    cleanup();
  }

  /// 빈 자리 (오른쪽 아래로 차례차례)
  Offset freeSpot() {
    if (notes.isEmpty) return const Offset(60, 60);
    final maxY = notes.map((n) => n.y).reduce(math.max);
    final lastRow = notes.where((n) => (n.y - maxY).abs() < 1).toList();
    final maxX = lastRow.map((n) => n.x).reduce(math.max);
    return maxX + 230 < 1100 ? Offset(maxX + 220, maxY) : Offset(60, maxY + 150);
  }

  /// AI 에게 줄 메모판 글 — 메모는 m1, m2… 짧은 번호로. (글, 번호→메모 id)
  (String, Map<String, String>) describe({Set<String>? only}) {
    final picked = [
      for (final n in _readingOrder())
        if (n.text.trim().isNotEmpty && (only == null || only.contains(n.id))) n,
    ];
    final code = <String, String>{}; // id → m1
    final back = <String, String>{}; // m1 → id
    for (var i = 0; i < picked.length; i++) {
      code[picked[i].id] = 'm${i + 1}';
      back['m${i + 1}'] = picked[i].id;
    }
    final sb = StringBuffer('[메모]\n');
    for (final n in picked) {
      sb.writeln('${code[n.id]}: ${n.text.trim().replaceAll(RegExp(r'\n+'), ' / ')}${n.source.isNotEmpty ? ' [${n.source}]' : ''}');
    }
    final gs = groups.where((g) => g.noteIds.any(code.containsKey)).toList();
    if (gs.isNotEmpty) {
      sb.writeln('\n[묶음]');
      for (final g in gs) {
        sb.writeln(
          '${g.title.trim().isEmpty ? '(이름 없는 묶음)' : g.title.trim()}: ${(g.noteIds.where(code.containsKey).map((id) => code[id]!).toList()..sort((x, y) => int.parse(x.substring(1)) - int.parse(y.substring(1)))).join(', ')}',
        );
      }
    }
    final ls = links.where((l) => code.containsKey(l.from) && code.containsKey(l.to)).toList();
    if (ls.isNotEmpty) {
      sb.writeln('\n[이은 선] (→ 는 흐름 방향, — 는 서로 관련)');
      for (final l in ls) {
        sb.writeln('${code[l.from]} ${l.arrow ? '→' : '—'} ${code[l.to]}');
      }
    }
    return (sb.toString().trim(), back);
  }

  /// 읽는 순서: 위에서 아래로, 같은 줄이면 왼쪽부터
  List<BoardNote> _readingOrder() {
    final out = [...notes];
    out.sort((a, b) => (a.y - b.y).abs() > 60 ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    return out;
  }
}

// ── 화면 ───────────────────────────────────────────────────────────────────

class SermonBoardView extends StatefulWidget {
  final SermonBoard board;
  final String lang;
  final int speechRate;
  final bool aiBusy;
  final ValueChanged<SermonBoard> onChanged;

  /// 설계도 가지 목록 (id, 이름) — 고른 메모 보내기
  final List<(String, String)> mapTargets;
  final void Function(String branchId, List<BoardNote> notes) onSendToMap;

  /// AI 로 설계도 정리
  final VoidCallback onAiArrange;

  /// AI 로 초안 풀어 쓰기 — only 가 있으면 고른 메모만, chars 는 목표 글자 수
  final void Function(Set<String>? only, int chars) onAiWrite;

  const SermonBoardView({
    super.key,
    required this.board,
    required this.lang,
    required this.onChanged,
    required this.mapTargets,
    required this.onSendToMap,
    required this.onAiArrange,
    required this.onAiWrite,
    this.speechRate = 300,
    this.aiBusy = false,
  });

  @override
  State<SermonBoardView> createState() => _SermonBoardViewState();
}

class _SermonBoardViewState extends State<SermonBoardView> {
  static const double noteWidth = 190;
  final _tc = TransformationController();
  final _canvasKey = GlobalKey();
  final Map<String, GlobalKey> _noteKeys = {};
  Map<String, Size> _sizes = {};
  final Set<String> selected = {};
  Size _viewport = Size.zero;
  bool _needFit = true;
  bool _holding = false; // 메모·묶음을 누르고 있는 동안은 그림 옮기기를 멈춘다
  bool _moved = false;

  bool get ko => widget.lang != 'en';
  SermonBoard get board => widget.board;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void changed() {
    widget.onChanged(board);
    setState(() {});
  }

  double get _scale => _tc.value.getMaxScaleOnAxis();

  GlobalKey _noteKey(String id) => _noteKeys.putIfAbsent(id, () => GlobalKey());

  Rect _rectOf(BoardNote n) => Rect.fromLTWH(n.x, n.y, noteWidth, _sizes[n.id]?.height ?? 60);

  /// 메모 크기를 잰다 (선·묶음 상자를 그리려고)
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final next = <String, Size>{};
      for (final n in board.notes) {
        final box = _noteKeys[n.id]?.currentContext?.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) next[n.id] = box.size;
      }
      var same = next.length == _sizes.length;
      if (same) {
        for (final e in next.entries) {
          if ((_sizes[e.key]?.height ?? -1) != e.value.height) {
            same = false;
            break;
          }
        }
      }
      if (!same) setState(() => _sizes = next);
      if (_needFit && _viewport != Size.zero) {
        _needFit = false;
        _fit();
      }
    });
  }

  Size get _canvasSize {
    var w = 2400.0, h = 1600.0;
    for (final n in board.notes) {
      w = math.max(w, n.x + noteWidth + 600);
      h = math.max(h, n.y + 600);
    }
    return Size(w, h);
  }

  /// 메모 전체가 창에 들어오게
  void _fit() {
    if (_viewport.isEmpty) return;
    if (board.notes.isEmpty) {
      _tc.value = Matrix4.identity();
      return;
    }
    var r = _rectOf(board.notes.first);
    for (final n in board.notes) {
      r = r.expandToInclude(_rectOf(n));
    }
    r = r.inflate(40);
    final s = math.min(1.0, math.min(_viewport.width / r.width, _viewport.height / r.height)).clamp(0.25, 1.0);
    _tc.value = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(-r.left * s + math.max(0, (_viewport.width - r.width * s) / 2), -r.top * s, 0);
  }

  void _zoom(double f) {
    final cur = _scale;
    final next = (cur * f).clamp(0.25, 2.0);
    final focal = Offset(_viewport.width / 2, _viewport.height / 2);
    final scene = _tc.toScene(focal);
    _tc.value = Matrix4.diagonal3Values(next, next, 1)..setTranslationRaw(focal.dx - scene.dx * next, focal.dy - scene.dy * next, 0);
  }

  /// 창 가운데의 그림 위치 (새 메모를 보이는 곳에)
  Offset _visibleSpot() {
    if (_viewport.isEmpty) return board.freeSpot();
    final p = _tc.toScene(Offset(_viewport.width / 2 - noteWidth / 2, _viewport.height / 3));
    // 다른 메모와 겹치지 않게 조금씩 아래로
    var spot = Offset(math.max(10, p.dx), math.max(10, p.dy));
    for (var i = 0; i < 20 && board.notes.any((n) => (n.x - spot.dx).abs() < 30 && (n.y - spot.dy).abs() < 30); i++) {
      spot += const Offset(24, 24);
    }
    return spot;
  }

  // ── 고치기 ──

  Future<String?> _askText({required String title, String initial = '', String hint = '', bool multiline = true}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('board-edit-text'),
            controller: ctrl,
            autofocus: true,
            maxLines: multiline ? 8 : 1,
            minLines: multiline ? 3 : 1,
            decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
            onSubmitted: multiline ? null : (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ko ? '취소' : 'Cancel')),
          FilledButton(key: const ValueKey('board-edit-ok'), onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ko ? '확인' : 'OK')),
        ],
      ),
    );
  }

  Future<void> _newNote(Offset at) async {
    final v = await _askText(title: ko ? '새 메모' : 'New note', hint: ko ? '생각을 쓰거나 붙여 넣으세요' : 'Type or paste');
    if (v == null || v.trim().isEmpty) return;
    final n = BoardNote(text: v.trim(), x: math.max(0, at.dx), y: math.max(0, at.dy), source: ko ? '직접' : 'Typed');
    board.notes.add(n);
    selected
      ..clear()
      ..add(n.id);
    changed();
  }

  Future<void> _editNote(BoardNote n) async {
    final v = await _askText(title: ko ? '메모 고치기' : 'Edit note', initial: n.text);
    if (v == null) return;
    if (v.trim().isEmpty) {
      board.removeNotes([n.id]);
      selected.remove(n.id);
    } else {
      n.text = v.trim();
    }
    changed();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      // 웹에서 브라우저가 클립보드 읽기를 막으면 — 새 메모 창에 Cmd+V 로 붙이도록
      await _newNote(_visibleSpot());
      return;
    }
    final at = _visibleSpot();
    final n = BoardNote(text: text, x: at.dx, y: at.dy, source: ko ? '붙여넣기' : 'Pasted');
    board.notes.add(n);
    selected
      ..clear()
      ..add(n.id);
    changed();
  }

  void _tapNote(BoardNote n) {
    final kb = HardwareKeyboard.instance;
    setState(() {
      if (kb.isShiftPressed || kb.isMetaPressed || kb.isControlPressed) {
        selected.contains(n.id) ? selected.remove(n.id) : selected.add(n.id);
      } else if (selected.length > 1 && selected.contains(n.id)) {
        selected.remove(n.id);
      } else if (selected.length == 1 && !selected.contains(n.id)) {
        // 하나 고른 뒤 다른 메모를 누르면 둘 다 고름 (잇기 편하게)
        selected.add(n.id);
      } else if (selected.contains(n.id)) {
        selected.remove(n.id);
      } else {
        selected.add(n.id);
      }
    });
  }

  List<BoardNote> get _selectedNotes => [
    for (final n in board.notes)
      if (selected.contains(n.id)) n,
  ];

  BoardLink? get _selectedLink {
    if (selected.length != 2) return null;
    final [a, b] = selected.toList();
    return board.links.where((l) => l.joins(a, b)).firstOrNull;
  }

  void _link() {
    if (selected.length != 2) return;
    final [a, b] = selected.toList();
    if (board.links.any((l) => l.joins(a, b))) return;
    board.links.add(BoardLink(a, b));
    changed();
  }

  void _unlink() {
    final l = _selectedLink;
    if (l == null) return;
    board.links.remove(l);
    changed();
  }

  /// 화살표: 없음 → 먼저 고른 쪽에서 나중 쪽으로 → 반대로 → 없음
  void _toggleArrow() {
    final l = _selectedLink;
    if (l == null) return;
    final i = board.links.indexOf(l);
    if (!l.arrow) {
      l.arrow = true;
    } else {
      final flipped = BoardLink(l.to, l.from, arrow: true);
      // 이미 한 번 뒤집은 것이면 화살표 없앰
      final firstPicked = selected.first;
      if (l.from == firstPicked) {
        board.links[i] = flipped;
      } else {
        l.arrow = false;
      }
    }
    changed();
  }

  void _group() {
    if (selected.length < 2) return;
    for (final g in board.groups) {
      g.noteIds.removeWhere(selected.contains);
    }
    board.groups.add(BoardGroup(noteIds: selected.toList(), color: board.groups.length % _groupColors.length));
    board.cleanup();
    changed();
  }

  void _setColor(int ci) {
    for (final n in _selectedNotes) {
      n.color = ci;
    }
    changed();
  }

  void _deleteSelected() {
    board.removeNotes(selected);
    selected.clear();
    changed();
  }

  void _sendToMap(String branchId) {
    final notes = _selectedNotes.where((n) => n.text.trim().isNotEmpty).toList();
    if (notes.isEmpty) return;
    widget.onSendToMap(branchId, notes);
    final name = widget.mapTargets.where((t) => t.$1 == branchId).firstOrNull?.$2 ?? '';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(duration: const Duration(seconds: 2), content: Text(ko ? '메모 ${notes.length}개를 설계도 $name에 넣었습니다.' : 'Sent ${notes.length} note(s) to $name.')),
    );
  }

  Future<void> _editGroup(BoardGroup g) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: g.title);
        return AlertDialog(
          title: Text(ko ? '묶음' : 'Group', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('board-group-title'),
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(labelText: ko ? '묶음 이름' : 'Name', border: const OutlineInputBorder()),
                  onSubmitted: (_) {
                    g.title = ctrl.text.trim();
                    Navigator.pop(ctx, 'save');
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < _groupColors.length; i++)
                      InkWell(
                        onTap: () {
                          g.color = i;
                          g.title = ctrl.text.trim();
                          Navigator.pop(ctx, 'save');
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _groupColors[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: g.color == i ? Colors.black54 : Colors.transparent, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'ungroup'),
              child: Text(ko ? '묶음 풀기' : 'Ungroup', style: const TextStyle(color: AppColors.danger)),
            ),
            FilledButton(
              onPressed: () {
                g.title = ctrl.text.trim();
                Navigator.pop(ctx, 'save');
              },
              child: Text(ko ? '확인' : 'OK'),
            ),
          ],
        );
      },
    );
    if (action == 'ungroup') board.groups.remove(g);
    if (action != null) changed();
  }

  Future<void> _askAiWrite() async {
    final hasSel = selected.isNotEmpty;
    var onlySel = hasSel;
    final minutesCtrl = TextEditingController(text: hasSel ? '5' : '25');
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final mins = int.tryParse(minutesCtrl.text.trim()) ?? 0;
          return AlertDialog(
            title: Text(ko ? '메모판으로 설교문 풀어 쓰기' : 'Write sermon from board', style: const TextStyle(fontSize: 15)),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    ko ? '메모와 묶음, 이은 선의 흐름을 따라 설교문을 씁니다. 쓴 글은 초안 끝에 붙습니다.' : 'Writes from notes, groups and links; appended to the draft.',
                    style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  if (hasSel)
                    DropdownButtonFormField<bool>(
                      initialValue: onlySel,
                      decoration: InputDecoration(labelText: ko ? '쓸 범위' : 'Scope', border: const OutlineInputBorder()),
                      items: [
                        DropdownMenuItem(value: true, child: Text(ko ? '고른 메모 ${selected.length}개만' : 'Selected ${selected.length} notes')),
                        DropdownMenuItem(value: false, child: Text(ko ? '메모판 전체' : 'Whole board')),
                      ],
                      onChanged: (v) => setD(() {
                        onlySel = v ?? false;
                        minutesCtrl.text = onlySel ? '5' : '25';
                      }),
                    ),
                  if (hasSel) const SizedBox(height: 12),
                  TextField(
                    controller: minutesCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setD(() {}),
                    decoration: InputDecoration(
                      labelText: ko ? '설교 시간(분)' : 'Minutes',
                      helperText: ko ? '약 ${mins * widget.speechRate}자 (1분에 ${widget.speechRate}자, 설정의 설교 속도)' : '~${mins * widget.speechRate} chars',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ko ? '취소' : 'Cancel')),
              FilledButton(onPressed: mins > 0 ? () => Navigator.pop(ctx, true) : null, child: Text(ko ? '쓰기' : 'Write')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final mins = int.tryParse(minutesCtrl.text.trim()) ?? 25;
    widget.onAiWrite(onlySel ? {...selected} : null, math.max(300, mins * widget.speechRate));
  }

  // ── 그리기 ──

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget tool(String label, VoidCallback? onTap, {bool accent = false, Key? key, Color? color}) => Padding(
      padding: const EdgeInsets.only(left: 6),
      child: TextButton(
        key: key,
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: accent ? c.accentLight : null,
          foregroundColor: color ?? c.accent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
            side: BorderSide(color: accent ? c.accent : c.border),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
    final n = selected.length;
    final link = _selectedLink;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final topBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            tool(ko ? '+ 메모' : '+ Note', () => _newNote(_visibleSpot()), key: const ValueKey('board-add')),
            tool(ko ? '붙여넣기' : 'Paste', _paste, key: const ValueKey('board-paste')),
            tool(ko ? 'AI로 설계도 정리' : 'Arrange into map', board.isEmpty || widget.aiBusy ? null : widget.onAiArrange, key: const ValueKey('board-ai-arrange')),
            tool(
              widget.aiBusy ? (ko ? '쓰는 중...' : 'Writing...') : (ko ? 'AI로 풀어 쓰기' : 'Write with AI'),
              board.isEmpty || widget.aiBusy ? null : _askAiWrite,
              accent: true,
              key: const ValueKey('board-ai-write'),
            ),
          ],
        ),
      ),
    );

    // 고른 메모가 있으면 나오는 줄
    final selBar = n == 0
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.bgSidebar,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(ko ? '메모 $n개' : '$n selected', style: TextStyle(fontSize: 12, color: c.textMuted)),
                  if (n == 2 && link == null) tool(ko ? '잇기' : 'Link', _link, key: const ValueKey('board-link')),
                  if (link != null) ...[
                    tool(ko ? '화살표' : 'Arrow', _toggleArrow, key: const ValueKey('board-arrow')),
                    tool(ko ? '끊기' : 'Unlink', _unlink, key: const ValueKey('board-unlink')),
                  ],
                  if (n >= 2) tool(ko ? '상자로 묶기' : 'Group', _group, key: const ValueKey('board-group')),
                  const SizedBox(width: 8),
                  for (var i = 0; i < boardColors.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        key: ValueKey('board-color-$i'),
                        onTap: () => _setColor(i),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: (dark ? _darkBoardColors : boardColors)[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: c.border),
                          ),
                        ),
                      ),
                    ),
                  if (widget.mapTargets.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: PopupMenuButton<String>(
                        key: const ValueKey('board-send-map'),
                        tooltip: '',
                        onSelected: _sendToMap,
                        itemBuilder: (_) => [for (final t in widget.mapTargets) PopupMenuItem(value: t.$1, child: Text(t.$2))],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: c.border),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            ko ? '설계도로 보내기 ▾' : 'Send to map ▾',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.accent),
                          ),
                        ),
                      ),
                    ),
                  tool(ko ? '지우기' : 'Delete', _deleteSelected, color: AppColors.danger, key: const ValueKey('board-delete')),
                  tool(ko ? '고르기 풀기' : 'Deselect', () => setState(selected.clear)),
                ],
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topBar,
        ?selBar,
        Expanded(child: _canvas(c, dark)),
      ],
    );
  }

  Widget _canvas(AppColors c, bool dark) {
    _measure();
    final size = _canvasSize;
    final rects = {for (final n in board.notes) n.id: _rectOf(n)};

    final stack = SizedBox(
      key: _canvasKey,
      width: size.width,
      height: size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 빈 곳: 누르면 고르기 풀기, 두 번 누르면 새 메모
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('board-canvas'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (selected.isNotEmpty) setState(selected.clear);
              },
              onDoubleTapDown: (d) => _pendingDouble = d.localPosition,
              onDoubleTap: () {
                final p = _pendingDouble;
                if (p != null) _newNote(p - const Offset(noteWidth / 2, 20));
              },
            ),
          ),
          // 묶음 상자
          for (final g in board.groups) ..._groupBox(c, g, rects),
          // 이은 선
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _LinkPainter(board.links, rects, c.textMuted, selected))),
          ),
          for (final note in board.notes) _noteWidget(c, note, dark),
          if (board.notes.isEmpty)
            Positioned(
              left: 60,
              top: 60,
              child: IgnorePointer(
                child: Text(
                  ko
                      ? '빈 곳을 두 번 누르거나 [+ 메모]로 생각을 적어 보세요.\n왼쪽 단계 글을 골라 끌어 놓거나 [붙여넣기]로도 넣을 수 있습니다.\n메모를 하나 누르고 다른 메모를 누르면 둘이 골라져 잇거나 묶을 수 있습니다.'
                      : 'Double-click empty space or use [+ Note].\nDrag text from the left, or paste.\nTap two notes to link or group them.',
                  style: TextStyle(fontSize: 13, height: 1.8, color: c.textMuted),
                ),
              ),
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        _viewport = Size(box.maxWidth, box.maxHeight);
        return Stack(
          children: [
            Positioned.fill(
              child: DragTarget<Object>(
                onWillAcceptWithDetails: (d) => d.data is MapTextDrag,
                onAcceptWithDetails: (d) {
                  final data = d.data as MapTextDrag;
                  final canvas = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
                  final at = canvas == null ? _visibleSpot() : canvas.globalToLocal(d.offset);
                  final note = BoardNote(text: data.text.trim(), x: math.max(0, at.dx), y: math.max(0, at.dy), source: data.source);
                  board.notes.add(note);
                  changed();
                },
                builder: (context, cand, _) => Container(
                  color: cand.isNotEmpty ? c.accentLight.withValues(alpha: 0.35) : c.bg,
                  child: InteractiveViewer(
                    transformationController: _tc,
                    constrained: false,
                    panEnabled: !_holding,
                    minScale: 0.25,
                    maxScale: 2,
                    boundaryMargin: const EdgeInsets.all(400),
                    child: stack,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(
                children: [
                  _zoomBtn(c, Icons.remove, () => _zoom(1 / 1.2), 'board-zoom-out'),
                  _zoomBtn(c, Icons.center_focus_strong_outlined, _fit, 'board-fit'),
                  _zoomBtn(c, Icons.add, () => _zoom(1.2), 'board-zoom-in'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Offset? _pendingDouble;

  Widget _zoomBtn(AppColors c, IconData icon, VoidCallback onTap, String key) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Material(
      color: c.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        key: ValueKey(key),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: c.textMuted),
        ),
      ),
    ),
  );

  /// 끌어 옮기기 — 누르는 순간 그림 옮기기를 멈추고, 움직인 만큼(화면 → 그림 비율로) 메모를 옮긴다
  Widget _dragWrap({required List<BoardNote> Function() moving, required Widget child}) => Listener(
    onPointerDown: (_) => setState(() {
      _holding = true;
      _moved = false;
    }),
    onPointerMove: (e) {
      if (!_holding) return;
      final delta = e.delta / _scale;
      if (!_moved && e.delta.distance < 0.5) return;
      _moved = true;
      for (final m in moving()) {
        m.x = math.max(0, m.x + delta.dx);
        m.y = math.max(0, m.y + delta.dy);
      }
      setState(() {});
    },
    onPointerUp: (_) => _endHold(),
    onPointerCancel: (_) => _endHold(),
    child: child,
  );

  void _endHold() {
    _holding = false;
    if (_moved) {
      _moved = false;
      changed();
    } else {
      setState(() {});
    }
  }

  List<Widget> _groupBox(AppColors c, BoardGroup g, Map<String, Rect> rects) {
    final rs = [for (final id in g.noteIds) ?rects[id]];
    if (rs.isEmpty) return const [];
    var r = rs.first;
    for (final x in rs) {
      r = r.expandToInclude(x);
    }
    r = Rect.fromLTRB(r.left - 14, r.top - 34, r.right + 14, r.bottom + 14);
    final color = _groupColors[g.color % _groupColors.length];
    return [
      Positioned.fromRect(
        rect: r,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              border: Border.all(color: color.withValues(alpha: 0.7), width: 1.4),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      // 이름 줄: 누르면 고치기, 끌면 묶음째 옮기기
      Positioned(
        left: r.left,
        top: r.top,
        width: r.width,
        height: 28,
        child: GestureDetector(
          key: ValueKey('board-group-${g.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _editGroup(g),
          child: _dragWrap(
            moving: () => [for (final id in g.noteIds) ?board.note(id)],
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
                child: Text(
                  g.title.trim().isEmpty ? (ko ? '묶음 (눌러 이름 짓기)' : 'Group (tap to name)') : g.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _noteWidget(AppColors c, BoardNote n, bool dark) {
    final on = selected.contains(n.id);
    final bg = (dark ? _darkBoardColors : boardColors)[n.color.clamp(0, boardColors.length - 1)];
    return Positioned(
      left: n.x,
      top: n.y,
      child: GestureDetector(
        key: ValueKey('board-note-${n.id}'),
        onTap: () => _tapNote(n),
        onDoubleTap: () => _editNote(n),
        // 고른 메모들 가운데 하나를 끌면 함께 옮긴다
        child: _dragWrap(
          moving: () => selected.contains(n.id) && selected.length > 1 ? _selectedNotes : [n],
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: Container(
              key: _noteKey(n.id),
              width: noteWidth,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: bg,
                border: Border.all(color: on ? c.accent : c.border, width: on ? 2 : 1),
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    n.text,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.45, color: c.text),
                  ),
                  if (n.source.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      n.source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: c.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkPainter extends CustomPainter {
  final List<BoardLink> links;
  final Map<String, Rect> rects;
  final Color color;
  final Set<String> selected;
  _LinkPainter(this.links, this.rects, this.color, this.selected);

  /// 상자 가운데에서 p 쪽으로 나가는 테두리 위 점
  Offset _edge(Rect r, Offset toward) {
    final c = r.center;
    final d = toward - c;
    if (d.distance < 1) return c;
    final sx = d.dx.abs() < 1e-6 ? double.infinity : (r.width / 2) / d.dx.abs();
    final sy = d.dy.abs() < 1e-6 ? double.infinity : (r.height / 2) / d.dy.abs();
    return c + d * math.min(sx, sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final l in links) {
      final a = rects[l.from], b = rects[l.to];
      if (a == null || b == null) continue;
      final on = selected.contains(l.from) && selected.contains(l.to);
      final paint = Paint()
        ..color = on ? const Color(0xFF534AB7) : color.withValues(alpha: 0.8)
        ..strokeWidth = on ? 2.2 : 1.4
        ..style = PaintingStyle.stroke;
      final p1 = _edge(a.inflate(3), b.center), p2 = _edge(b.inflate(3), a.center);
      canvas.drawLine(p1, p2, paint);
      if (l.arrow) {
        final dir = (p2 - p1);
        if (dir.distance < 1) continue;
        final u = dir / dir.distance;
        final n = Offset(-u.dy, u.dx);
        final path = Path()
          ..moveTo(p2.dx, p2.dy)
          ..lineTo((p2 - u * 10 + n * 5).dx, (p2 - u * 10 + n * 5).dy)
          ..lineTo((p2 - u * 10 - n * 5).dx, (p2 - u * 10 - n * 5).dy)
          ..close();
        canvas.drawPath(path, Paint()..color = paint.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinkPainter old) => true;
}
