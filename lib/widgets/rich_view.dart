// 글 보기·편집 — 웹의 plain-view / rich-view(보기)와 RichEditor(편집) 자리
// 저장 형식은 웹과 같은 HTML(또는 일반 글), 화면에서는 flutter_quill 문서로 다룬다.
//
// 편집: 위쪽 도구 막대 (B I U | A- A+ | 좌 중 우 | 색) + // 명령 (Enter)
// 보기: 드래그해서 고치기 (선택 → 지시 입력칸)
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../services/rich_doc.dart';
import '../theme/app_colors.dart';
import 'selection_edit_box.dart';

/// 웹 .plain-view p { margin: 0 0 1em } · line-height 1.8 과 같은 모양
DefaultStyles richStyles(BuildContext context, double fontSize) {
  final c = context.c;
  final base = TextStyle(fontSize: fontSize, height: 1.8, color: c.text);
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(base, HorizontalSpacing.zero, VerticalSpacing(0, fontSize), VerticalSpacing.zero, null),
    placeHolder: DefaultTextBlockStyle(base.copyWith(color: c.textMuted), HorizontalSpacing.zero, VerticalSpacing.zero, VerticalSpacing.zero, null),
  );
}

/// // 명령 한 번 — 명령 자리에 AI 글을 흘려 넣는다
class SlashCommand {
  final String instruction;
  final String contextBefore;
  final String contextAfter;

  /// 'research' (//-지시) | 'theological' (//+지시) | 'fresh' (//지시)
  final String mode;
  final void Function(String text) write;
  const SlashCommand({required this.instruction, required this.contextBefore, required this.contextAfter, required this.mode, required this.write});
}

/// 드래그해서 고치기 설정 — 없으면 끈다
class SelectionEditConfig {
  final String lang;
  final String bible;
  final String? passage;
  final String? title;

  /// 고친 뒤 저장할 HTML
  final Future<void> Function(String html) onApply;
  const SelectionEditConfig({required this.lang, required this.bible, required this.passage, required this.title, required this.onApply});
}

// 웹 RichEditor FONT_SIZES (0.75 0.85 1 1.2 1.5 2 em) 를 14px 기준으로
const _fontSizesPx = [10.5, 11.9, 14.0, 16.8, 21.0, 28.0];
const List<Attribute> _inlineAttrs = [Attribute.bold, Attribute.italic, Attribute.underline, Attribute.strikeThrough, Attribute.color, Attribute.size, Attribute.background];
const _colors = ['#000000', '#dc2626', '#2563eb', '#16a34a', '#d97706', '#7c3aed', '#6b7280'];

class RichView extends StatefulWidget {
  /// 저장된 글 (HTML 또는 일반 글)
  final String source;
  final double fontSize;
  final bool editable;
  final bool autoFocus;

  /// 편집할 때마다 HTML 로 알려 준다
  final ValueChanged<String>? onChanged;

  /// 선택한 글이 바뀔 때 (보기 상태에서 "설교문에 반영" 에 쓰인다)
  final ValueChanged<String>? onSelectedText;

  /// AI 가 쓰는 중에는 서식 없이 가볍게 보여 준다
  final bool streaming;
  final EdgeInsets padding;

  /// 편집 도구 막대 (웹 fixedToolbar)
  final bool showToolbar;

  /// // 명령 처리 (편집 중 Enter)
  final Future<void> Function(SlashCommand cmd)? onEnterCommand;

  /// 드래그해서 고치기 (보기 상태)
  final SelectionEditConfig? selectionEdit;

  const RichView({
    super.key,
    required this.source,
    required this.fontSize,
    this.editable = false,
    this.autoFocus = false,
    this.onChanged,
    this.onSelectedText,
    this.streaming = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    this.showToolbar = false,
    this.onEnterCommand,
    this.selectionEdit,
  });

  @override
  State<RichView> createState() => RichViewState();
}

class RichViewState extends State<RichView> {
  late QuillController controller;
  final focusNode = FocusNode();
  final _scroll = ScrollController();
  String _lastSource = '';
  StreamSubscription? _docSub;
  Offset? _pointerDown;
  OverlayEntry? _editBox;

  @override
  void initState() {
    super.initState();
    controller = _makeController(widget.source);
  }

  QuillController _makeController(String source) {
    _lastSource = source;
    final ctrl = QuillController(
      document: docFromSource(source),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: !widget.editable,
    );
    ctrl.addListener(_onControllerChange);
    _docSub?.cancel();
    _docSub = ctrl.document.changes.listen((_) => _onDocChange());
    return ctrl;
  }

  void _onControllerChange() {
    final sel = controller.selection;
    if (widget.onSelectedText != null) {
      final text = sel.isCollapsed ? '' : controller.document.getPlainText(sel.start, sel.end - sel.start).trim();
      widget.onSelectedText!(text);
    }
    if (widget.showToolbar && mounted) setState(() {}); // 도구 막대의 눌림 표시
  }

  void _onDocChange() {
    if (!widget.editable || widget.onChanged == null) return;
    final html = htmlFromDoc(controller.document);
    _lastSource = html;
    widget.onChanged!(html);
  }

  @override
  void didUpdateWidget(covariant RichView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editable != widget.editable) controller.readOnly = !widget.editable;
    // 바깥에서 글이 바뀌었으면 (AI 생성·되돌리기 등) 문서를 새로 만든다
    if (widget.source != _lastSource && !widget.streaming) {
      final prev = controller;
      controller = _makeController(widget.source);
      prev.removeListener(_onControllerChange);
      WidgetsBinding.instance.addPostFrameCallback((_) => prev.dispose());
    }
  }

  @override
  void dispose() {
    _closeEditBox();
    _docSub?.cancel();
    controller.removeListener(_onControllerChange);
    controller.dispose();
    focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── // 명령 ────────────────────────────────────────────────────────────

  KeyEventResult? _onKey(KeyEvent event, Node? node) {
    if (widget.onEnterCommand == null || event is! KeyDownEvent) return null;
    if (event.logicalKey != LogicalKeyboardKey.enter && event.logicalKey != LogicalKeyboardKey.numpadEnter) return null;
    if (HardwareKeyboard.instance.isShiftPressed) return null;
    final sel = controller.selection;
    if (!sel.isCollapsed) return null;
    final text = controller.document.toPlainText();
    final cursor = sel.baseOffset;
    final lineStart = cursor == 0 ? 0 : text.lastIndexOf('\n', cursor - 1) + 1;
    final lineText = text.substring(lineStart, cursor);
    final slashIdx = lineText.indexOf('//');
    if (slashIdx < 0) return null;
    final after = lineText.substring(slashIdx + 2);
    // //-지시: 내 연구 + 문맥 / //+지시: 내 연구 + 문맥 + 신학자 관점 / //지시: 신학자 관점으로 새로 쓰기
    var mode = 'fresh';
    var instruction = after.trim();
    if (after.startsWith('-')) {
      mode = 'research';
      instruction = after.substring(1).trim();
    } else if (after.startsWith('+')) {
      mode = 'theological';
      instruction = after.substring(1).trim();
    }
    if (instruction.isEmpty) return null;

    final slashAbs = lineStart + slashIdx;
    final contextBefore = text.substring(0, slashAbs);
    var contextAfter = text.substring(cursor);
    if (contextAfter.endsWith('\n')) contextAfter = contextAfter.substring(0, contextAfter.length - 1);
    controller.replaceText(slashAbs, cursor - slashAbs, '', TextSelection.collapsed(offset: slashAbs));

    // 명령 자리에 흘려 넣기 — 새 글을 받을 때마다 앞서 넣은 글을 바꾼다 (나머지 글의 서식은 그대로)
    var insertedLen = 0;
    void write(String t) {
      final clean = t.replaceAll(RegExp(r'\n{2,}'), '\n');
      controller.replaceText(slashAbs, insertedLen, clean, TextSelection.collapsed(offset: slashAbs + clean.length));
      insertedLen = clean.length;
      // AI 글은 서식 없이 — 앞 글자의 굵게·색 등이 이어지지 않도록 지운다
      if (clean.isNotEmpty) {
        for (final a in _inlineAttrs) {
          controller.formatText(slashAbs, clean.length, Attribute.clone(a, null));
        }
      }
    }

    widget.onEnterCommand!(SlashCommand(instruction: instruction, contextBefore: contextBefore, contextAfter: contextAfter, mode: mode, write: write));
    return KeyEventResult.handled;
  }

  // ── 드래그해서 고치기 ──────────────────────────────────────────────────────

  void _closeEditBox() {
    _editBox?.remove();
    _editBox = null;
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _pointerDown;
    _pointerDown = null;
    final cfg = widget.selectionEdit;
    if (cfg == null || widget.editable || down == null || (e.position - down).distance < 6) return;
    // 선택이 반영된 뒤에 확인한다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sel = controller.selection;
      if (!mounted || sel.isCollapsed) return;
      final plain = controller.document.toPlainText();
      // 단어 중간에서 끊긴 선택은 단어 끝까지 넓힌다 (AI 가 잘린 단어를 이어 쓰다 앞뒤 글까지 다시 쓰지 않도록)
      bool boundary(String ch) => ch.trim().isEmpty;
      var start = sel.start;
      var end = sel.end;
      while (start > 0 && !boundary(plain[start - 1])) {
        start--;
      }
      while (end < plain.length && !boundary(plain[end])) {
        end++;
      }
      if (start != sel.start || end != sel.end) {
        controller.updateSelection(TextSelection(baseOffset: start, extentOffset: end), ChangeSource.local);
      }
      final selected = plain.substring(start, end);
      if (selected.trim().isEmpty) return;
      final request = SelectionEditRequest(
        selected,
        plain.substring(math.max(0, start - 600), start),
        plain.substring(end, math.min(plain.length, end + 600)).trimRight(),
      );
      _showEditBox(cfg, request, start, end, e.position);
    });
  }

  void _showEditBox(SelectionEditConfig cfg, SelectionEditRequest request, int start, int end, Offset at) {
    _closeEditBox();
    final screen = MediaQuery.sizeOf(context);
    const width = 340.0;
    final double left = at.dx.clamp(8.0, math.max(8.0, screen.width - width - 8)).toDouble();
    final double top = at.dy + 12 + 220 > screen.height ? math.max(8.0, at.dy - 232) : at.dy + 12;
    final theme = Theme.of(context);

    _editBox = OverlayEntry(
      builder: (_) => Positioned(
        left: left,
        top: top,
        child: Theme(
          data: theme,
          child: SelectionEditBox(
            request: request,
            lang: cfg.lang,
            bible: cfg.bible,
            passage: cfg.passage,
            title: cfg.title,
            onClose: _closeEditBox,
            onApply: (result) async {
              final before = htmlFromDoc(controller.document);
              _replaceKeepingStyle(start, end - start, result);
              final html = htmlFromDoc(controller.document);
              _lastSource = html;
              await cfg.onApply(html);
              return () async => cfg.onApply(before);
            },
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_editBox!);
  }

  /// 선택 부분을 새 글로 바꾸되, 맨 앞 글자의 서식(굵게·색 등)은 그대로 이어 쓴다
  void _replaceKeepingStyle(int index, int len, String text) {
    final clean = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n');
    final style = controller.document.collectStyle(index, 0);
    controller.replaceText(index, len, clean, TextSelection.collapsed(offset: index + clean.length));
    for (final attr in style.attributes.values) {
      if (attr.scope == AttributeScope.inline) controller.formatText(index, clean.length, attr);
    }
  }

  // ── 도구 막대 ────────────────────────────────────────────────────────────

  Map<String, Attribute> get _selAttrs => controller.getSelectionStyle().attributes;

  void _toggle(Attribute attr) {
    final on = _selAttrs.containsKey(attr.key);
    controller.formatSelection(on ? Attribute.clone(attr, null) : attr);
  }

  void _changeSize(int direction) {
    final raw = _selAttrs[Attribute.size.key]?.value;
    final current = raw is num ? raw.toDouble() : (double.tryParse('$raw') ?? 14.0);
    var idx = 0;
    for (var i = 0; i < _fontSizesPx.length; i++) {
      if ((current - _fontSizesPx[i]).abs() < (current - _fontSizesPx[idx]).abs()) idx = i;
    }
    final next = _fontSizesPx[(idx + direction).clamp(0, _fontSizesPx.length - 1)];
    controller.formatSelection(next == 14.0 ? Attribute.clone(Attribute.size, null) : Attribute.fromKeyValue(Attribute.size.key, next));
  }

  Widget _toolbar(AppColors c) {
    final attrs = _selAttrs;
    final align = attrs[Attribute.align.key]?.value;
    final color = attrs[Attribute.color.key]?.value;
    Widget btn(String label, bool active, VoidCallback onTap, {TextStyle? style, String? tip}) {
      final w = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: active ? c.accent : Colors.transparent, borderRadius: BorderRadius.circular(4)),
          child: Text(label,
              style: (style ?? const TextStyle()).copyWith(fontSize: 13, fontWeight: style?.fontWeight ?? FontWeight.w600, color: active ? Colors.white : c.text)),
        ),
      );
      return tip == null ? w : Tooltip(message: tip, child: w);
    }

    Widget sep() => Container(width: 1, height: 16, color: c.border, margin: const EdgeInsets.symmetric(horizontal: 3));

    Widget swatch(String hex) {
      final active = color == hex;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: InkWell(
          onTap: () => controller.formatSelection(active ? Attribute.clone(Attribute.color, null) : ColorAttribute(hex)),
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
              border: Border.all(color: active ? c.accent : const Color(0xFFAAAAAA), width: active ? 2 : 1),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
      child: Wrap(spacing: 2, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        btn('B', attrs.containsKey(Attribute.bold.key), () => _toggle(Attribute.bold), style: const TextStyle(fontWeight: FontWeight.w700)),
        btn('I', attrs.containsKey(Attribute.italic.key), () => _toggle(Attribute.italic), style: const TextStyle(fontStyle: FontStyle.italic)),
        btn('U', attrs.containsKey(Attribute.underline.key), () => _toggle(Attribute.underline), style: const TextStyle(decoration: TextDecoration.underline)),
        sep(),
        btn('A-', false, () => _changeSize(-1)),
        btn('A+', false, () => _changeSize(1)),
        sep(),
        btn('좌', align == 'left', () => controller.formatSelection(Attribute.leftAlignment), tip: '왼쪽 정렬'),
        btn('중', align == 'center', () => controller.formatSelection(Attribute.centerAlignment), tip: '가운데 정렬'),
        btn('우', align == 'right', () => controller.formatSelection(Attribute.rightAlignment), tip: '오른쪽 정렬'),
        sep(),
        Tooltip(
          message: '기본 색상',
          child: InkWell(
            onTap: () => controller.formatSelection(Attribute.clone(Attribute.color, null)),
            child: Container(
              width: 15,
              height: 15,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFAAAAAA))),
              child: CustomPaint(painter: _SlashPainter()),
            ),
          ),
        ),
        for (final hex in _colors) swatch(hex),
      ]),
    );
  }

  // ── 화면 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (widget.streaming) {
      // 생성 중 — 일반 글로 가볍게 (빈 줄은 빼고 줄마다 문단)
      final lines = stripHtml(widget.source).split('\n').where((l) => l.trim().isNotEmpty).toList();
      return ListView.builder(
        controller: _scroll,
        padding: widget.padding,
        itemCount: lines.length,
        itemBuilder: (_, i) => Padding(
          padding: EdgeInsets.only(bottom: i == lines.length - 1 ? 0 : widget.fontSize),
          child: Text(lines[i], style: TextStyle(fontSize: widget.fontSize, height: 1.8, color: c.text)),
        ),
      );
    }
    final editor = Listener(
      onPointerDown: (e) => _pointerDown = e.position,
      onPointerUp: _onPointerUp,
      child: QuillEditor(
        controller: controller,
        focusNode: focusNode,
        scrollController: _scroll,
        config: QuillEditorConfig(
          padding: widget.padding,
          autoFocus: widget.autoFocus,
          expands: true,
          showCursor: widget.editable,
          customStyles: richStyles(context, widget.fontSize),
          // Enter 로 // 명령 실행 — flutter_quill 이 '실험 기능'으로 표시한 자리라, 버전을 올릴 때 확인 필요
          // ignore: experimental_member_use
          onKeyPressed: widget.editable && widget.onEnterCommand != null ? _onKey : null,
        ),
      ),
    );
    if (!widget.showToolbar) return editor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toolbar(c),
      Expanded(child: editor),
    ]);
  }
}

/// 기본 색상 버튼의 빨간 사선
class _SlashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
