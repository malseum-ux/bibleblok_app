// 설교 설계도 — 설교작성 오른쪽 창의 [설계도] 탭
// 가운데 제목·본문, 둘레 가지(설교 정보·Big Idea·서론·본론·결론·추가 공부 주제), 가지마다 대지 한 문장과 카드(하위 가지)
// 마인드맵 보기 / 순서 보기, 왼쪽 단계 글을 골라 넣거나 끌어 놓기, 개요로 붙이기 · AI로 풀어 쓰기
// 저장: 설교 파일(JSON)의 "map" 칸
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

int _seq = 0;
String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

// ── 자료 ───────────────────────────────────────────────────────────────────

class MapCard {
  final String id;
  String title;
  String text;
  String source; // 어디서 왔는지 (예: "6단계 교훈", "직접")
  List<MapCard> children;

  MapCard({String? id, required this.title, this.text = '', this.source = '', List<MapCard>? children})
      : id = id ?? _newId(),
        children = children ?? [];

  /// 고른 글로 카드 만들기 — 제목은 첫 문장 앞부분
  factory MapCard.fromText(String text, String source) => MapCard(title: shortTitle(text), text: text.trim(), source: source);

  factory MapCard.fromJson(Map<String, dynamic> j) => MapCard(
        id: j['id'] as String?,
        title: (j['title'] ?? '') as String,
        text: (j['text'] ?? '') as String,
        source: (j['source'] ?? '') as String,
        children: [for (final c in (j['children'] as List? ?? const [])) if (c is Map) MapCard.fromJson(c.cast<String, dynamic>())],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'source': source,
        if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
      };
}

/// 첫 문장 앞부분 20자 안팎
String shortTitle(String text) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return '';
  final first = t.split(RegExp(r'(?<=[.!?。])\s')).first;
  return first.length <= 24 ? first : '${first.substring(0, 22)}…';
}

/// 가지 종류: bigidea · intro(서론) · body(본론) · conclusion(결론) · study(추가 공부 주제)
class MapBranch {
  final String id;
  final String kind;
  String thesis; // 대지 — 이 가지에서 말할 한 문장
  List<MapCard> cards;

  MapBranch({String? id, required this.kind, this.thesis = '', List<MapCard>? cards})
      : id = id ?? _newId(),
        cards = cards ?? [];

  factory MapBranch.fromJson(Map<String, dynamic> j) => MapBranch(
        id: j['id'] as String?,
        kind: (j['kind'] ?? 'body') as String,
        thesis: (j['thesis'] ?? '') as String,
        cards: [for (final c in (j['cards'] as List? ?? const [])) if (c is Map) MapCard.fromJson(c.cast<String, dynamic>())],
      );

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind, 'thesis': thesis, 'cards': [for (final c in cards) c.toJson()]};
}

class SermonMap {
  List<MapBranch> branches;
  SermonMap(this.branches);

  /// 처음 모양: Big Idea · 서론 · 본론 1·2·3 · 결론 · 추가 공부 주제
  factory SermonMap.initial() => SermonMap([
        MapBranch(kind: 'bigidea'),
        MapBranch(kind: 'intro'),
        MapBranch(kind: 'body'),
        MapBranch(kind: 'body'),
        MapBranch(kind: 'body'),
        MapBranch(kind: 'conclusion'),
        MapBranch(kind: 'study'),
      ]);

  factory SermonMap.fromJson(Object? raw) {
    if (raw is! Map || raw['branches'] is! List) return SermonMap.initial();
    final list = [for (final b in raw['branches'] as List) if (b is Map) MapBranch.fromJson(b.cast<String, dynamic>())];
    return list.isEmpty ? SermonMap.initial() : SermonMap(list);
  }

  Map<String, dynamic> toJson() => {'version': 1, 'branches': [for (final b in branches) b.toJson()]};

  bool get isEmpty => branches.every((b) => b.thesis.trim().isEmpty && b.cards.isEmpty);

  /// 설교 순서 (Big Idea → 서론 → 본론 → 결론 → 추가 공부)
  List<MapBranch> get ordered {
    int rank(String k) => const {'bigidea': 0, 'intro': 1, 'body': 2, 'conclusion': 3, 'study': 4}[k] ?? 2;
    final out = [...branches];
    // 같은 종류(본론)끼리는 원래 순서 그대로
    final idx = {for (var i = 0; i < branches.length; i++) branches[i].id: i};
    out.sort((a, b) => rank(a.kind) != rank(b.kind) ? rank(a.kind) - rank(b.kind) : idx[a.id]! - idx[b.id]!);
    return out;
  }

  /// 번호 (서론 1, 본론 2…, 결론 n) — Big Idea·추가 공부는 번호 없음
  int? numberOf(MapBranch b) {
    var n = 0;
    for (final x in ordered) {
      if (x.kind == 'bigidea' || x.kind == 'study') continue;
      n++;
      if (x.id == b.id) return n;
    }
    return null;
  }

  String nameOf(MapBranch b, bool ko) {
    switch (b.kind) {
      case 'bigidea':
        return 'Big Idea';
      case 'intro':
        return ko ? '서론' : 'Introduction';
      case 'conclusion':
        return ko ? '결론' : 'Conclusion';
      case 'study':
        return ko ? '추가 공부 주제' : 'Further Study';
      default:
        final bodies = ordered.where((x) => x.kind == 'body').toList();
        final i = bodies.indexWhere((x) => x.id == b.id) + 1;
        return ko ? '본론 $i' : 'Point $i';
    }
  }

  MapBranch? branch(String id) => branches.where((b) => b.id == id).firstOrNull;

  /// 카드와 그 카드가 든 목록 찾기
  (List<MapCard>, int)? locate(String cardId) {
    (List<MapCard>, int)? walk(List<MapCard> list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id == cardId) return (list, i);
        final r = walk(list[i].children);
        if (r != null) return r;
      }
      return null;
    }

    for (final b in branches) {
      final r = walk(b.cards);
      if (r != null) return r;
    }
    return null;
  }

  MapCard? removeCard(String cardId) {
    final at = locate(cardId);
    if (at == null) return null;
    return at.$1.removeAt(at.$2);
  }

  /// 순서대로 쓴 개요 (plain=true 면 AI 에게 줄 글: 카드 전체 글 포함)
  String outline(bool ko, {String? onlyBranchId}) {
    final sb = StringBuffer();
    void cardsOut(List<MapCard> list, String prefix) {
      for (var i = 0; i < list.length; i++) {
        final c = list[i];
        final no = '$prefix.${i + 1}';
        sb.writeln('$no ${c.title}${c.source.isNotEmpty ? ' [${c.source}]' : ''}');
        if (c.text.trim().isNotEmpty && c.text.trim() != c.title.trim()) sb.writeln(c.text.trim());
        cardsOut(c.children, no);
      }
    }

    for (final b in ordered) {
      if (onlyBranchId != null && b.id != onlyBranchId) continue;
      if (b.kind == 'bigidea') {
        if (b.thesis.trim().isNotEmpty || b.cards.isNotEmpty) {
          sb.writeln('Big Idea: ${b.thesis.trim()}');
          cardsOut(b.cards, '*');
          sb.writeln();
        }
        continue;
      }
      final n = numberOf(b);
      sb.writeln('${n != null ? '$n. ' : ''}${nameOf(b, ko)}${b.thesis.trim().isNotEmpty ? ' — ${b.thesis.trim()}' : ''}');
      cardsOut(b.cards, '${n ?? '*'}');
      sb.writeln();
    }
    return sb.toString().trim();
  }
}

/// 왼쪽 단계 글에서 끌어 온 글 (끌어 놓기)
class MapTextDrag {
  final String text;
  final String source;
  const MapTextDrag(this.text, this.source);
}

class _CardDrag {
  final String cardId;
  const _CardDrag(this.cardId);
}

// 가지 색 (보여 주신 화면처럼 가지마다 다른 색)
const _kindColor = {
  'bigidea': Color(0xFFD99A1E),
  'intro': Color(0xFF16A34A),
  'conclusion': Color(0xFF0D9488),
  'study': Color(0xFFB7791F),
};
const _bodyColors = [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFDB2777), Color(0xFFEA580C), Color(0xFF0891B2)];
const _infoColor = Color(0xFFDC2626);
const _dropGreen = Color(0xFF16A34A);

Color branchColor(SermonMap map, MapBranch b) {
  if (b.kind != 'body') return _kindColor[b.kind] ?? const Color(0xFF534AB7);
  final bodies = map.ordered.where((x) => x.kind == 'body').toList();
  final i = bodies.indexWhere((x) => x.id == b.id);
  return _bodyColors[math.max(0, i) % _bodyColors.length];
}

// ── 화면 ───────────────────────────────────────────────────────────────────

class SermonMapView extends StatefulWidget {
  final SermonMap map;
  final String lang;
  final String? title;
  final String? passage;
  final String? date;
  final String? category;
  final int speechRate;
  final bool aiBusy;
  final ValueChanged<SermonMap> onChanged;

  /// 개요로 붙이기 (AI 없이)
  final VoidCallback onPasteOutline;

  /// AI로 풀어 쓰기 — branchId 가 null 이면 전체, chars 는 목표 글자 수
  final void Function(String? branchId, int chars) onAiWrite;

  const SermonMapView({
    super.key,
    required this.map,
    required this.lang,
    required this.onChanged,
    required this.onPasteOutline,
    required this.onAiWrite,
    this.title,
    this.passage,
    this.date,
    this.category,
    this.speechRate = 300,
    this.aiBusy = false,
  });

  @override
  State<SermonMapView> createState() => _SermonMapViewState();
}

class _SermonMapViewState extends State<SermonMapView> {
  String view = 'map'; // map | order
  String layout = 'both'; // both(양쪽, 시계 방향) | right(오른쪽에 위→아래)
  static const _layoutKey = 'bibleblok-map-layout';
  final _tc = TransformationController(); // 그림 옮기기·크게 작게
  bool _needFit = true;
  Size _viewport = Size.zero;
  final _stackKey = GlobalKey();
  final _centerKey = GlobalKey();
  final Map<String, GlobalKey> _chipKeys = {};
  List<(Offset, Offset, Color)> _lines = [];

  bool get ko => widget.lang != 'en';
  SermonMap get map => widget.map;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(_layoutKey);
      if (mounted && (v == 'both' || v == 'right') && v != layout) {
        setState(() {
          layout = v!;
          _needFit = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _setLayout(String v) {
    setState(() {
      layout = v;
      _needFit = true;
    });
    SharedPreferences.getInstance().then((p) => p.setString(_layoutKey, v));
  }

  /// 그림 전체가 창에 들어오게 (크면 줄이고, 작으면 원래 크기로 가운데)
  void _fit() {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _viewport.isEmpty) return;
    final w = box.size.width + 48, h = box.size.height + 48;
    final s = math.min(1.0, math.min(_viewport.width / w, _viewport.height / h)).clamp(0.25, 1.0);
    final tx = math.max(0.0, (_viewport.width - w * s) / 2), ty = math.max(0.0, (_viewport.height - h * s) / 2);
    _tc.value = Matrix4.diagonal3Values(s, s, 1)..setTranslationRaw(tx, ty, 0);
  }

  /// 창 가운데를 기준으로 크게(f>1)·작게
  void _zoom(double f) {
    final cur = _tc.value.getMaxScaleOnAxis();
    final next = (cur * f).clamp(0.25, 2.0);
    final focal = Offset(_viewport.width / 2, _viewport.height / 2);
    final scene = _tc.toScene(focal);
    _tc.value = Matrix4.diagonal3Values(next, next, 1)..setTranslationRaw(focal.dx - scene.dx * next, focal.dy - scene.dy * next, 0);
  }

  void changed() {
    widget.onChanged(map);
    setState(() {});
  }

  GlobalKey _chipKey(String id) => _chipKeys.putIfAbsent(id, () => GlobalKey());

  /// 가운데 → 가지 선을 그리기 위해 자리를 잰다 (그린 뒤에)
  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || view != 'map') return;
      final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
      final centerBox = _centerKey.currentContext?.findRenderObject() as RenderBox?;
      if (stackBox == null || centerBox == null || !stackBox.attached || !centerBox.attached) return;
      final center = stackBox.globalToLocal(centerBox.localToGlobal(centerBox.size.center(Offset.zero)));
      final lines = <(Offset, Offset, Color)>[];
      for (final entry in _sides().expand((s) => s)) {
        final box = _chipKeys[entry.$1]?.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final rect = stackBox.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
        final end = rect.center.dx > center.dx ? rect.centerLeft : rect.centerRight;
        lines.add((center, end, entry.$2));
      }
      bool same = lines.length == _lines.length;
      for (var i = 0; same && i < lines.length; i++) {
        same = (lines[i].$1 - _lines[i].$1).distance < 0.5 && (lines[i].$2 - _lines[i].$2).distance < 0.5;
      }
      if (!same) setState(() => _lines = lines);
    });
  }

  /// 시계 방향: 오른쪽 위→아래(설교 정보·Big Idea·서론·본론…), 왼쪽 아래→위(나머지)
  List<List<(String, Color)>> _sides() {
    final all = <(String, Color)>[('info', _infoColor), for (final b in map.ordered) (b.id, branchColor(map, b))];
    if (layout == 'right') return [all, const []]; // 오른쪽: 위→아래 설교 순서
    final rightCount = (all.length / 2).ceil();
    return [all.sublist(0, rightCount), all.sublist(rightCount).reversed.toList()];
  }

  // ── 고치기 창 ──

  Future<String?> _askText({required String title, String initial = '', String hint = '', bool multiline = false}) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: multiline ? 8 : 1,
            decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
            onSubmitted: multiline ? null : (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ko ? '취소' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ko ? '확인' : 'OK')),
        ],
      ),
    );
  }

  Future<void> _editThesis(MapBranch b) async {
    final v = await _askText(
      title: '${map.nameOf(b, ko)} — ${ko ? (b.kind == 'bigidea' ? '한 문장' : '대지 한 문장') : 'One sentence'}',
      initial: b.thesis,
      hint: b.kind == 'bigidea' ? (ko ? '이 설교가 말하려는 단 하나의 생각' : 'The one idea of this sermon') : (ko ? '이 가지에서 말할 한 문장' : 'What this part says'),
    );
    if (v == null) return;
    b.thesis = v.trim();
    changed();
  }

  /// 복사해 둔 글을 카드로 (출처: 붙여넣기)
  Future<void> _pasteCard(List<MapCard> into) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(ko ? '복사해 둔 글이 없습니다.' : 'Nothing to paste.')));
      return;
    }
    into.add(MapCard.fromText(text, ko ? '붙여넣기' : 'Pasted'));
    changed();
  }

  Future<void> _writeCard(List<MapCard> into) async {
    final v = await _askText(title: ko ? '직접 쓰기' : 'Write', hint: ko ? '내용을 쓰거나 붙여 넣으세요 (첫 문장이 카드 제목이 됩니다)' : 'Type or paste (first sentence becomes the title)', multiline: true);
    if (v == null || v.trim().isEmpty) return;
    into.add(MapCard.fromText(v, ko ? '직접' : 'Typed'));
    changed();
  }

  Future<void> _openCard(MapCard card) async {
    final titleCtrl = TextEditingController(text: card.title);
    final textCtrl = TextEditingController(text: card.text);
    final c = context.c;
    final targets = [for (final b in map.ordered) (b.id, map.nameOf(b, ko))];
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Expanded(child: Text(ko ? '카드' : 'Card', style: const TextStyle(fontSize: 15))),
          if (card.source.isNotEmpty) Text(card.source, style: TextStyle(fontSize: 12, color: c.textMuted)),
        ]),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              key: const ValueKey('map-card-title'),
              controller: titleCtrl,
              decoration: InputDecoration(labelText: ko ? '제목' : 'Title', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textCtrl,
              maxLines: 10,
              minLines: 4,
              decoration: InputDecoration(labelText: ko ? '내용' : 'Content', border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton(onPressed: () => Navigator.pop(ctx, 'child'), child: Text(ko ? '+ 하위 가지' : '+ Sub-item')),
              OutlinedButton(onPressed: () => Navigator.pop(ctx, 'pasteChild'), child: Text(ko ? '붙여넣기로 하위 가지' : 'Paste as sub-item')),
              OutlinedButton(onPressed: () => Navigator.pop(ctx, 'up'), child: Text(ko ? '위로' : 'Up')),
              OutlinedButton(onPressed: () => Navigator.pop(ctx, 'down'), child: Text(ko ? '아래로' : 'Down')),
              PopupMenuButton<String>(
                tooltip: '',
                onSelected: (id) => Navigator.pop(ctx, 'move:$id'),
                itemBuilder: (_) => [for (final t in targets) PopupMenuItem(value: t.$1, child: Text(t.$2))],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(ko ? '다른 가지로 ▾' : 'Move to ▾', style: TextStyle(color: c.accent)),
                ),
              ),
              TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(ko ? '빼기' : 'Remove', style: const TextStyle(color: AppColors.danger))),
            ]),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(ko ? '확인' : 'OK'))],
      ),
    );
    if (action == null) return;
    card.title = titleCtrl.text.trim().isEmpty ? shortTitle(textCtrl.text) : titleCtrl.text.trim();
    card.text = textCtrl.text;
    final at = map.locate(card.id);
    if (action == 'child') {
      changed();
      await _writeCard(card.children);
      return;
    }
    if (action == 'pasteChild') {
      await _pasteCard(card.children);
      return;
    }
    if (at != null) {
      final (list, i) = at;
      if (action == 'up' && i > 0) {
        list.insert(i - 1, list.removeAt(i));
      } else if (action == 'down' && i < list.length - 1) {
        list.insert(i + 1, list.removeAt(i));
      } else if (action == 'delete') {
        list.removeAt(i);
      } else if (action.startsWith('move:')) {
        final to = map.branch(action.substring(5));
        if (to != null) to.cards.add(list.removeAt(i));
      }
    }
    changed();
  }

  /// card 의 하위(자손) 목록인지 — 자기 밑으로는 옮길 수 없다
  bool _isInside(MapCard card, List<MapCard> list) => identical(card.children, list) || card.children.any((ch) => _isInside(ch, list));

  /// list 의 index 자리에 넣기 — 카드 옮기기면 원래 자리에서 빼고, 왼쪽 글이면 새 카드
  void _insertAt(List<MapCard> list, int index, Object data) {
    MapCard? card;
    if (data is _CardDrag) {
      final at = map.locate(data.cardId);
      if (at == null || _isInside(at.$1[at.$2], list)) return;
      if (identical(at.$1, list) && at.$2 < index) index--;
      card = at.$1.removeAt(at.$2);
    } else if (data is MapTextDrag) {
      card = MapCard.fromText(data.text, data.source);
    }
    if (card == null) return;
    list.insert(index.clamp(0, list.length), card);
    changed();
  }

  void _acceptInto(MapBranch b, Object data) {
    _insertAt(b.cards, b.cards.length, data);
  }

  void _addBody() {
    final lastBody = map.branches.lastIndexWhere((b) => b.kind == 'body');
    final at = lastBody >= 0 ? lastBody + 1 : map.branches.indexWhere((b) => b.kind == 'conclusion');
    map.branches.insert(at < 0 ? map.branches.length : at, MapBranch(kind: 'body'));
    changed();
  }

  Future<void> _removeBranch(MapBranch b) async {
    final ok = b.cards.isEmpty && b.thesis.trim().isEmpty
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              content: Text(ko ? '${map.nameOf(b, ko)}을(를) 빼면 안의 카드도 함께 빠집니다.' : 'Remove this point and its cards?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ko ? '취소' : 'Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ko ? '빼기' : 'Remove')),
              ],
            ),
          );
    if (ok != true) return;
    map.branches.remove(b);
    changed();
  }

  Future<void> _askAiWrite() async {
    final branches = map.ordered.where((b) => b.kind != 'study').toList();
    String target = 'all';
    final minutesCtrl = TextEditingController(text: '25');
    final c = context.c;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final mins = int.tryParse(minutesCtrl.text.trim()) ?? 0;
          return AlertDialog(
            title: Text(ko ? 'AI로 설교문 풀어 쓰기' : 'Write sermon with AI', style: const TextStyle(fontSize: 15)),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(ko ? '설계도를 뼈대로, 카드의 자료를 재료로 이어지는 설교문을 씁니다. 쓴 글은 초안 끝에 붙습니다.' : 'Writes a sermon from this map; appended to the draft.',
                    style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.5)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  decoration: InputDecoration(labelText: ko ? '쓸 범위' : 'Scope', border: const OutlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: 'all', child: Text(ko ? '설교 전체' : 'Whole sermon')),
                    for (final b in branches) DropdownMenuItem(value: b.id, child: Text(map.nameOf(b, ko))),
                  ],
                  onChanged: (v) => setD(() {
                    target = v ?? 'all';
                    minutesCtrl.text = target == 'all' ? '25' : '5';
                  }),
                ),
                const SizedBox(height: 12),
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
              ]),
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
    widget.onAiWrite(target == 'all' ? null : target, math.max(300, mins * widget.speechRate));
  }

  // ── 그리기 ──

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget seg(String key, String label) => InkWell(
          onTap: () => setState(() => view = key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: view == key ? c.accent : null, borderRadius: BorderRadius.circular(5)),
            child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: view == key ? Colors.white : c.textMuted)),
          ),
        );
    Widget tool(String label, VoidCallback? onTap, {bool accent = false}) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: accent ? c.accentLight : null,
              foregroundColor: c.accent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: accent ? c.accent : c.border)),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: Text(label),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(7)),
              child: Row(children: [seg('map', ko ? '마인드맵' : 'Mind map'), seg('order', ko ? '순서 보기' : 'Outline')]),
            ),
            if (view == 'map') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(7)),
                child: Row(children: [
                  InkWell(
                    key: const ValueKey('map-layout-both'),
                    onTap: () => _setLayout('both'),
                    child: _segBox(c, ko ? '양쪽' : 'Both sides', layout == 'both'),
                  ),
                  InkWell(
                    key: const ValueKey('map-layout-right'),
                    onTap: () => _setLayout('right'),
                    child: _segBox(c, ko ? '오른쪽' : 'Right', layout == 'right'),
                  ),
                ]),
              ),
            ],
            tool(ko ? '+ 본론 더하기' : '+ Point', _addBody),
            tool(ko ? '개요로 붙이기' : 'Paste outline', map.isEmpty ? null : widget.onPasteOutline),
            tool(widget.aiBusy ? (ko ? '쓰는 중...' : 'Writing...') : (ko ? 'AI로 풀어 쓰기' : 'Write with AI'), map.isEmpty || widget.aiBusy ? null : _askAiWrite,
                accent: true),
          ]),
        ),
      ),
      Expanded(child: view == 'map' ? _mindMap(c) : _orderView(c)),
    ]);
  }

  Widget _segBox(AppColors c, String label, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: on ? c.accentLight : null, borderRadius: BorderRadius.circular(5)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? c.accent : c.textMuted)),
      );

  // 마인드맵 보기
  Widget _mindMap(AppColors c) {
    _measure();
    final sides = _sides();
    Widget column(List<(String, Color)> list, bool left) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: left ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            for (final (id, color) in list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: id == 'info' ? _infoBlock(c, left) : _branchBlock(c, map.branch(id)!, color, left),
              ),
          ],
        );
    final centerNode = Container(
      key: _centerKey,
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(color: const Color(0xFF1F4D3A), borderRadius: BorderRadius.circular(10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text((widget.title?.trim().isNotEmpty == true ? widget.title! : (ko ? '설교 제목' : 'Sermon title')),
            textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF5C451), fontSize: 15, fontWeight: FontWeight.w700)),
        if (widget.passage?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(widget.passage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ]),
    );
    final content = Stack(key: _stackKey, children: [
      Positioned.fill(child: CustomPaint(painter: _LinePainter(_lines))),
      layout == 'right'
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              centerNode,
              const SizedBox(width: 60),
              SizedBox(width: 430, child: column(sides[0], false)),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 380, child: column(sides[1], true)),
              const SizedBox(width: 40),
              centerNode,
              const SizedBox(width: 40),
              SizedBox(width: 380, child: column(sides[0], false)),
            ]),
    ]);
    Widget zoomBtn(String key, IconData icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.bg, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 16, color: c.textMuted),
            ),
          ),
        );
    return LayoutBuilder(builder: (context, box) {
      _viewport = box.biggest;
      if (_needFit) {
        _needFit = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit();
        });
      }
      return Stack(children: [
        // 빈 곳을 잡고 끌면 그림 전체가 움직이고, 두 손가락 벌리기·휠로 크게·작게
        InteractiveViewer(
          transformationController: _tc,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(1500),
          minScale: 0.25,
          maxScale: 2.0,
          child: Padding(padding: const EdgeInsets.all(24), child: content),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Row(children: [
            zoomBtn('map-zoom-out', Icons.remove, ko ? '작게' : 'Zoom out', () => _zoom(1 / 1.2)),
            const SizedBox(width: 4),
            zoomBtn('map-fit', Icons.fit_screen_outlined, ko ? '전체 보기' : 'Fit', _fit),
            const SizedBox(width: 4),
            zoomBtn('map-zoom-in', Icons.add, ko ? '크게' : 'Zoom in', () => _zoom(1.2)),
          ]),
        ),
      ]);
    });
  }

  Widget _chip(AppColors c, String key, String label, Color color, {int? count, VoidCallback? onTap, Widget? menu}) => Container(
        key: _chipKey(key),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.bg, border: Border.all(color: color, width: 1.6), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            onTap: onTap,
            child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 11, color: c.textMuted)),
          ],
          ?menu,
        ]),
      );

  Widget _infoBlock(AppColors c, bool left) {
    final rows = <(String, String)>[
      if (widget.date?.isNotEmpty == true) (ko ? '설교 일자' : 'Date', widget.date!),
      if (widget.passage?.isNotEmpty == true) (ko ? '본문' : 'Passage', widget.passage!),
      if (widget.category?.isNotEmpty == true) (ko ? '분류' : 'Category', widget.category!),
    ];
    final chip = _chip(c, 'info', ko ? '설교 정보' : 'Sermon info', _infoColor);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final (k, v) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text('$k  $v', style: TextStyle(fontSize: 11.5, color: c.textMuted)),
        ),
      if (rows.isEmpty) Text(ko ? '기본정보에서 날짜·본문을 넣으세요' : 'Add date and passage in Info', style: TextStyle(fontSize: 11, color: c.textMuted)),
    ]);
    return Row(mainAxisSize: MainAxisSize.min, children: left ? [Flexible(child: body), const SizedBox(width: 10), chip] : [chip, const SizedBox(width: 10), Flexible(child: body)]);
  }

  Widget _branchBlock(AppColors c, MapBranch b, Color color, bool left) {
    final n = map.numberOf(b);
    final label = '${n != null ? '$n ' : (b.kind == 'bigidea' ? '★ ' : '')}${map.nameOf(b, ko)}';
    final menu = PopupMenuButton<String>(
      key: ValueKey('map-branch-menu-${b.id}'),
      tooltip: '',
      padding: EdgeInsets.zero,
      iconSize: 16,
      icon: Icon(Icons.more_horiz, size: 16, color: c.textMuted),
      onSelected: (v) {
        if (v == 'thesis') _editThesis(b);
        if (v == 'write') _writeCard(b.cards);
        if (v == 'paste') _pasteCard(b.cards);
        if (v == 'remove') _removeBranch(b);
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'thesis', child: Text(b.kind == 'bigidea' ? (ko ? '한 문장 쓰기' : 'Write sentence') : (ko ? '대지 한 문장 쓰기' : 'Write main sentence'))),
        PopupMenuItem(value: 'write', child: Text(ko ? '직접 쓰기' : 'Write a card')),
        PopupMenuItem(value: 'paste', child: Text(ko ? '붙여넣기' : 'Paste')),
        if (b.kind == 'body') PopupMenuItem(value: 'remove', child: Text(ko ? '이 본론 빼기' : 'Remove this point')),
      ],
    );
    final chip = DragTarget<Object>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _acceptInto(b, d.data),
      builder: (context, cand, _) => Container(
        decoration: cand.isNotEmpty ? BoxDecoration(boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]) : null,
        child: _chip(c, b.id, label, color, count: b.cards.length, onTap: () => _editThesis(b), menu: menu),
      ),
    );
    final thesis = InkWell(
      onTap: () => _editThesis(b),
      child: Container(
        width: 250,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: b.kind == 'bigidea' && b.thesis.isNotEmpty ? const Color(0x14D99A1E) : null,
          border: Border.all(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          b.thesis.trim().isNotEmpty
              ? b.thesis
              : (b.kind == 'bigidea' ? (ko ? '이 설교의 단 하나의 생각' : 'The one idea') : (b.kind == 'study' ? (ko ? '더 공부할 주제' : 'To study more') : (ko ? '대지 — 이 가지에서 말할 한 문장' : 'Main sentence'))),
          style: TextStyle(fontSize: 12, fontWeight: b.thesis.isNotEmpty ? FontWeight.w600 : FontWeight.w400, color: b.thesis.isNotEmpty ? c.text : c.textMuted),
        ),
      ),
    );
    final body = DragTarget<Object>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _acceptInto(b, d.data),
      builder: (context, cand, _) => Container(
        padding: const EdgeInsets.all(2),
        decoration: cand.isNotEmpty ? BoxDecoration(border: Border.all(color: const Color(0xFF16A34A), width: 2), borderRadius: BorderRadius.circular(6)) : null,
        child: Column(crossAxisAlignment: left ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          thesis,
          const SizedBox(height: 4),
          _cardList(c, b.cards, '${n ?? '•'}', color, 0),
          if (b.cards.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(ko ? '왼쪽 글을 골라 넣거나 끌어 놓기' : 'Add from the left or drop here', style: TextStyle(fontSize: 10.5, color: c.textMuted)),
            ),
        ]),
      ),
    );
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: left ? [Flexible(child: body), const SizedBox(width: 10), chip] : [chip, const SizedBox(width: 10), Flexible(child: body)]);
  }

  /// 카드 사이 놓는 자리 — 끌어 오면 초록 가로선, 놓으면 그 자리에
  Widget _gap(List<MapCard> list, int index, double width) => DragTarget<Object>(
        key: ValueKey('map-gap-${identityHashCode(list)}-$index'),
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => _insertAt(list, index, d.data),
        builder: (context, cand, _) => SizedBox(
          width: width,
          height: cand.isNotEmpty ? 12 : 5,
          child: cand.isNotEmpty ? Center(child: Container(height: 3, decoration: BoxDecoration(color: _dropGreen, borderRadius: BorderRadius.circular(2)))) : null,
        ),
      );

  Widget _cardList(AppColors c, List<MapCard> list, String prefix, Color color, int depth) {
    final w = 250 - depth * 14.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < list.length; i++) ...[
        _gap(list, i, w),
        _cardTile(c, list[i], '$prefix.${i + 1}', color, depth),
      ],
      if (list.isNotEmpty) _gap(list, list.length, w),
    ]);
  }

  Widget _cardTile(AppColors c, MapCard card, String no, Color color, int depth) {
    Widget tile(bool target) => Container(
          width: 250 - depth * 14.0,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: target ? const Color(0x1416A34A) : c.bg,
            border: target ? Border.all(color: _dropGreen, width: 2) : Border(left: BorderSide(color: color, width: 2.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$no ${card.title}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.text, fontWeight: FontWeight.w600)),
            if (card.source.isNotEmpty) Text(card.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: c.textMuted)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      // 카드 위에 놓으면 이 카드의 하위 가지로
      DragTarget<Object>(
        key: ValueKey('map-card-drop-${card.id}'),
        onWillAcceptWithDetails: (d) => !(d.data is _CardDrag && (d.data as _CardDrag).cardId == card.id),
        onAcceptWithDetails: (d) => _insertAt(card.children, card.children.length, d.data),
        builder: (context, cand, _) => Draggable<Object>(
          data: _CardDrag(card.id),
          feedback: Material(color: Colors.transparent, child: Opacity(opacity: 0.85, child: tile(false))),
          childWhenDragging: Opacity(opacity: 0.3, child: tile(false)),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(key: ValueKey('map-card-${card.id}'), onTap: () => _openCard(card), child: tile(cand.isNotEmpty)),
          ),
        ),
      ),
      if (card.children.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 14), child: _cardList(c, card.children, no, color, depth + 1)),
    ]);
  }

  // 순서 보기
  Widget _orderView(AppColors c) {
    Widget cards(List<MapCard> list, String prefix, Color color, double indent) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < list.length; i++) ...[
            InkWell(
              onTap: () => _openCard(list[i]),
              child: Container(
                margin: EdgeInsets.only(left: indent, top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 2.5))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$prefix.${i + 1} ${list[i].title}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
                  if (list[i].source.isNotEmpty) Text(list[i].source, style: TextStyle(fontSize: 11, color: c.textMuted)),
                  if (list[i].text.trim().isNotEmpty && list[i].text.trim() != list[i].title.trim())
                    Padding(padding: const EdgeInsets.only(top: 3), child: Text(list[i].text.trim(), style: TextStyle(fontSize: 12.5, height: 1.6, color: c.text))),
                ]),
              ),
            ),
            if (list[i].children.isNotEmpty) cards(list[i].children, '$prefix.${i + 1}', color, indent + 16),
          ],
        ]);
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.title?.trim().isNotEmpty == true ? widget.title! : (ko ? '설교 제목' : 'Sermon title'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textHeading)),
      if (widget.passage?.isNotEmpty == true) Text(widget.passage!, style: TextStyle(fontSize: 13, color: c.textMuted)),
      const SizedBox(height: 12),
      for (final b in map.ordered)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: branchColor(map, b), width: 4), top: BorderSide(color: c.border), right: BorderSide(color: c.border), bottom: BorderSide(color: c.border)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('${map.numberOf(b) != null ? '${map.numberOf(b)}. ' : ''}${map.nameOf(b, ko)}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: branchColor(map, b))),
              ),
              TextButton(onPressed: () => _pasteCard(b.cards), child: Text(ko ? '붙여넣기' : 'Paste', style: const TextStyle(fontSize: 12))),
              TextButton(onPressed: () => _writeCard(b.cards), child: Text(ko ? '+ 직접 쓰기' : '+ Write', style: const TextStyle(fontSize: 12))),
            ]),
            InkWell(
              onTap: () => _editThesis(b),
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(5)),
                child: Text(
                  b.thesis.trim().isNotEmpty ? b.thesis : (ko ? '대지 — 이 가지에서 말할 한 문장' : 'Main sentence'),
                  style: TextStyle(fontSize: 13, color: b.thesis.trim().isNotEmpty ? c.text : c.textMuted),
                ),
              ),
            ),
            cards(b.cards, '${map.numberOf(b) ?? '•'}', branchColor(map, b), 0),
          ]),
        ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  final List<(Offset, Offset, Color)> lines;
  _LinePainter(this.lines);

  @override
  void paint(Canvas canvas, Size size) {
    for (final (a, b, color) in lines) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final mid = (a.dx + b.dx) / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.lines != lines;
}
