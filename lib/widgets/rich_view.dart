// 글 보기·편집 — 웹의 plain-view / rich-view(보기)와 RichEditor(편집) 자리
// 저장 형식은 웹과 같은 HTML(또는 일반 글), 화면에서는 flutter_quill 문서로 다룬다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../services/rich_doc.dart';
import '../theme/app_colors.dart';

/// 웹 .plain-view p { margin: 0 0 1em } · line-height 1.8 과 같은 모양
DefaultStyles richStyles(BuildContext context, double fontSize) {
  final c = context.c;
  final base = TextStyle(fontSize: fontSize, height: 1.8, color: c.text);
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(base, HorizontalSpacing.zero, VerticalSpacing(0, fontSize), VerticalSpacing.zero, null),
    placeHolder: DefaultTextBlockStyle(base.copyWith(color: c.textMuted), HorizontalSpacing.zero, VerticalSpacing.zero, VerticalSpacing.zero, null),
  );
}

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
  final ScrollController? scrollController;

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
    this.scrollController,
  });

  @override
  State<RichView> createState() => RichViewState();
}

class RichViewState extends State<RichView> {
  late QuillController controller;
  final focusNode = FocusNode();
  late final ScrollController _scroll = widget.scrollController ?? ScrollController();
  String _lastSource = '';
  StreamSubscription? _docSub;

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
    _docSub?.cancel();
    controller.removeListener(_onControllerChange);
    controller.dispose();
    focusNode.dispose();
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

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
    return QuillEditor(
      controller: controller,
      focusNode: focusNode,
      scrollController: _scroll,
      config: QuillEditorConfig(
        padding: widget.padding,
        autoFocus: widget.autoFocus,
        expands: true,
        showCursor: widget.editable,
        customStyles: richStyles(context, widget.fontSize),
      ),
    );
  }
}
