// 단계 화면(설교·예배·새벽·교재)에서 같이 쓰는 작은 부품 — 웹 StepView/CellView 의 인라인 스타일과 같은 모양
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../services/prompts.dart' show StepItem;
import '../services/store.dart' show CustomStepItem;
import '../theme/app_colors.dart';

/// 단계 탭 한 칸 — 번호 원(40px) + 이름(18px) + 영어 이름 + 내용 표시 점
class StepTab extends StatelessWidget {
  final StepDef step;
  final bool active;
  final bool hasContent;
  final String lang;
  final VoidCallback onTap;
  final String? subtitle; // 교재: 부제 (웹 CELL_SUBTITLES)
  const StepTab({super.key, required this.step, required this.active, required this.hasContent, required this.lang, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final en = lang == 'en';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: active ? c.accent : c.accentLight),
            child: Text('${step.index + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: active ? Colors.white : c.accent)),
          ),
          const SizedBox(width: 8),
          Text(step.label(lang), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: active ? c.accent : c.text)),
          if (subtitle != null) ...[
            const SizedBox(width: 6),
            Opacity(opacity: 0.8, child: Text(subtitle!, style: TextStyle(fontSize: 13, color: active ? c.accent : c.textMuted))),
          ] else if (!en && step.en != step.ko) ...[
            const SizedBox(width: 6),
            Opacity(opacity: 0.8, child: Text(step.en, style: TextStyle(fontSize: 13, color: active ? c.accent : c.textMuted))),
          ],
          if (hasContent) ...[
            const SizedBox(width: 8),
            // 웹의 ● (7px)
            Opacity(opacity: 0.7, child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent))),
          ],
        ]),
      ),
    );
  }
}

/// 작은 테두리 버튼 (웹 padding 4px 10px, 12px, 굵게) — 누른 상태면 강조색
class SmallButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onPressed;
  const SmallButton({super.key, required this.label, this.active = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: active ? c.accent : Colors.transparent,
        foregroundColor: active ? Colors.white : c.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: active ? c.accent : c.border)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label, softWrap: false),
    );
  }
}

/// A- / A+ 글자 크기 (11~24)
class FontSizeButtons extends StatelessWidget {
  final double fontSize;
  final ValueChanged<double> onChange;
  final double height;
  final bool fontSize11;
  const FontSizeButtons({super.key, required this.fontSize, required this.onChange, this.height = 28, this.fontSize11 = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget btn(String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: fontSize11 ? 6 : 7),
            alignment: Alignment.center,
            child: Text(label, style: TextStyle(fontSize: fontSize11 ? 11 : 12, color: c.textMuted)),
          ),
        );
    return Container(
      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(fontSize11 ? 5 : 6)),
      clipBehavior: Clip.antiAlias,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn('A-', () => onChange((fontSize - 1).clamp(11, 24))),
        Container(width: 1, height: height, color: c.border),
        btn('A+', () => onChange((fontSize + 1).clamp(11, 24))),
      ]),
    );
  }
}

/// 되돌리기·다시하기 (웹의 ↩ ↪)
class UndoButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  const UndoButton({super.key, required this.icon, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(5)),
          child: Icon(icon, size: 13, color: c.textMuted),
        ),
      ),
    );
  }
}

/// 보기 화면을 누르면 편집으로 — 끌어서 글을 고르는 동작은 누름으로 치지 않는다
class TapToEdit extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  const TapToEdit({super.key, required this.enabled, required this.onTap, required this.child});

  @override
  State<TapToEdit> createState() => _TapToEditState();
}

class _TapToEditState extends State<TapToEdit> {
  Offset? _down;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
        child: Listener(
          onPointerDown: (e) => _down = e.position,
          onPointerUp: (e) {
            final d = _down;
            _down = null;
            if (!widget.enabled || d == null) return;
            if ((e.position - d).distance < 6) widget.onTap();
          },
          child: widget.child,
        ),
      );
}

/// 지시 항목 패널 — 기본 항목 체크 · 사용자 항목(편집: 끌어서 순서, ×, 추가) · 추가 키워드
class InstructionsPanel extends StatefulWidget {
  final List<StepItem> items;
  final List<String> selected;
  final ValueChanged<String> onToggle;
  final List<CustomStepItem> customItems;
  final List<String> customSelected;
  final ValueChanged<String> onToggleCustom;
  final Future<void> Function(String label) onAddCustom;
  final Future<void> Function(String id) onDeleteCustom;
  final Future<void> Function(List<String> ids) onReorderCustom;
  final TextEditingController keywordCtrl;
  final String lang;
  const InstructionsPanel({
    super.key,
    required this.items,
    required this.selected,
    required this.onToggle,
    required this.customItems,
    required this.customSelected,
    required this.onToggleCustom,
    required this.onAddCustom,
    required this.onDeleteCustom,
    required this.onReorderCustom,
    required this.keywordCtrl,
    required this.lang,
  });

  @override
  State<InstructionsPanel> createState() => _InstructionsPanelState();
}

class _InstructionsPanelState extends State<InstructionsPanel> {
  bool editingCustom = false;
  final newCtrl = TextEditingController();
  String? draggedId;
  String? dragOverId;

  bool get en => widget.lang == 'en';

  @override
  void dispose() {
    newCtrl.dispose();
    super.dispose();
  }

  Future<void> add() async {
    final label = newCtrl.text.trim();
    if (label.isEmpty) return;
    await widget.onAddCustom(label);
    newCtrl.clear();
  }

  Future<void> drop(String targetId) async {
    final from = draggedId;
    setState(() {
      draggedId = null;
      dragOverId = null;
    });
    if (from == null || from == targetId) return;
    final ids = widget.customItems.map((c) => c.id).toList();
    final fromIdx = ids.indexOf(from);
    final toIdx = ids.indexOf(targetId);
    ids.removeAt(fromIdx);
    ids.insert(toIdx, from);
    await widget.onReorderCustom(ids);
  }

  Widget _check(String label, bool checked, VoidCallback onTap, Color color) {
    final c = context.c;
    return InkWell(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 14,
          height: 14,
          child: Checkbox(
            value: checked,
            onChanged: (_) => onTap(),
            activeColor: c.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: c.textMuted),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 13, color: color)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final ci in widget.items) _check(ci.label, widget.selected.contains(ci.key), () => widget.onToggle(ci.key), c.text),
          for (final ci in widget.customItems)
            if (editingCustom)
              DragTarget<String>(
                onWillAcceptWithDetails: (_) {
                  setState(() => dragOverId = ci.id);
                  return true;
                },
                onLeave: (_) => setState(() => dragOverId = null),
                onAcceptWithDetails: (_) => drop(ci.id),
                builder: (context, _, _) => Draggable<String>(
                  data: ci.id,
                  onDragStarted: () => setState(() => draggedId = ci.id),
                  onDragEnd: (_) => setState(() {
                    draggedId = null;
                    dragOverId = null;
                  }),
                  feedback: Material(color: Colors.transparent, child: _chip(ci, over: true)),
                  childWhenDragging: Opacity(opacity: 0.4, child: _chip(ci)),
                  child: _chip(ci, over: dragOverId == ci.id),
                ),
              )
            else
              _check(ci.label, widget.customSelected.contains(ci.id), () => widget.onToggleCustom(ci.id), c.accent),
          if (editingCustom)
            SizedBox(
              width: 90,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () => setState(() {
                        editingCustom = false;
                        newCtrl.clear();
                      }),
                },
                child: TextField(
                  controller: newCtrl,
                  autofocus: true,
                  onSubmitted: (_) => add(),
                  style: TextStyle(fontSize: 13, color: c.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: en ? 'New item' : '새 항목',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: c.bg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.border)),
                  ),
                ),
              ),
            ),
          if (!editingCustom)
            InkWell(
              onTap: () => setState(() => editingCustom = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(5)),
                child: Text(en ? 'Edit' : '편집', style: TextStyle(fontSize: 12, color: c.textMuted)),
              ),
            )
          else
            InkWell(
              onTap: () => setState(() {
                editingCustom = false;
                newCtrl.clear();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(5)),
                child: Text(en ? 'Done' : '완료', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: widget.keywordCtrl,
          style: TextStyle(fontSize: 13, color: c.text),
          decoration: InputDecoration(
            isDense: true,
            hintText: en ? 'Additional keywords or instructions (e.g. youth audience, Easter theme)' : '추가 키워드나 지시사항 (예: 청년 대상, 부활절 주제)',
            hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
            filled: true,
            fillColor: c.bg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
          ),
        ),
      ]),
    );
  }

  Widget _chip(CustomStepItem ci, {bool over = false}) {
    final c = context.c;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: over ? c.accent : const Color(0x1F6366F1),
          border: Border.all(color: draggedId == ci.id ? Colors.transparent : c.accent),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('≡ ${ci.label}', style: TextStyle(fontSize: 13, color: over ? Colors.white : c.accent)),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => widget.onDeleteCustom(ci.id),
            child: Opacity(opacity: 0.7, child: Text('×', style: TextStyle(fontSize: 15, color: over ? Colors.white : c.accent))),
          ),
        ]),
      ),
    );
  }
}
