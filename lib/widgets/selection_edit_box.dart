// 드래그해서 고치기 입력칸 — 웹 SelectionEdit.jsx 의 SelectionEditBox 와 같은 모양·동작
// 지시를 입력하고 Enter → AI 가 고치는 과정을 보여 주고 → 선택한 부분을 바꾼 뒤 [되돌리기] [닫기]
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai.dart';
import '../services/prompts.dart';
import '../theme/app_colors.dart';

class SelectionEditRequest {
  final String selectedText;
  final String contextBefore;
  final String contextAfter;
  const SelectionEditRequest(this.selectedText, this.contextBefore, this.contextAfter);
}

class SelectionEditBox extends StatefulWidget {
  final SelectionEditRequest request;
  final String lang;
  final String bible;
  final String? passage;
  final String? title;

  /// AI 결과 글로 선택 부분을 바꾼다 (성공하면 되돌리기용 함수 반환)
  final Future<Future<void> Function()> Function(String result) onApply;
  final VoidCallback onClose;

  const SelectionEditBox({
    super.key,
    required this.request,
    required this.lang,
    required this.bible,
    required this.passage,
    required this.title,
    required this.onApply,
    required this.onClose,
  });

  @override
  State<SelectionEditBox> createState() => _SelectionEditBoxState();
}

class _SelectionEditBoxState extends State<SelectionEditBox> {
  final ctrl = TextEditingController();
  final inputFocus = FocusNode();
  String status = 'input'; // input | loading | done | error
  String preview = '';
  String error = '';
  Future<void> Function()? undoFn;

  bool get en => widget.lang == 'en';

  @override
  void initState() {
    super.initState();
    // 드래그가 끝난 직후 편집기가 초점을 다시 가져가므로, 뜬 뒤에 입력칸으로 초점을 옮긴다
    WidgetsBinding.instance.addPostFrameCallback((_) => inputFocus.requestFocus());
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted && status == 'input') inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final text = ctrl.text.replaceFirst(RegExp(r'^//'), '').trim();
    if (text.isEmpty || status == 'loading') return;
    setState(() {
      status = 'loading';
      preview = '';
      error = '';
    });
    try {
      final r = widget.request;
      final result = await executeSelectionEdit(
        r.selectedText, text, r.contextBefore, r.contextAfter,
        widget.lang, widget.bible, widget.passage, widget.title,
        (chunk) {
          if (mounted) setState(() => preview = chunk);
        },
      );
      undoFn = await widget.onApply(result);
      if (mounted) setState(() => status = 'done');
    } on AbortedException {
      if (mounted) setState(() => status = 'input');
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e'.replaceFirst('Exception: ', '');
          status = 'error';
        });
      }
    }
  }

  Future<void> undo() async {
    await undoFn?.call();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget btn(String label, VoidCallback onTap, {bool primary = false}) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: primary ? c.accent : c.bg,
            foregroundColor: primary ? Colors.white : c.text,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: primary ? c.accent : c.border)),
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: Text(label),
        );

    return TapRegion(
      // 바깥을 누르면 닫기 (고치는 중에는 유지)
      onTapOutside: (_) {
        if (status != 'loading') widget.onClose();
      },
      child: Material(
        color: c.bg,
        elevation: 8,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(en ? 'Edit selection with AI' : '선택한 부분 AI 수정',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.accent)),
            ),
            if (status == 'input' || status == 'error')
              CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): widget.onClose},
                child: TextField(
                  controller: ctrl,
                  focusNode: inputFocus,
                  autofocus: true,
                  onSubmitted: (_) => submit(),
                  style: TextStyle(fontSize: 13, color: c.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: en ? 'Instruction (e.g. shorten, soften) · Enter' : '수정 지시 (예: 짧게 줄여, 부드럽게) · Enter',
                    hintStyle: TextStyle(fontSize: 13, color: c.textMuted),
                    filled: true,
                    fillColor: c.bg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: c.border)),
                  ),
                ),
              ),
            if (status == 'loading') ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: c.bgSidebar, borderRadius: BorderRadius.circular(6)),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(preview.isEmpty ? (en ? 'Editing...' : '고치는 중...') : preview,
                      style: TextStyle(fontSize: 12, height: 1.6, color: c.text)),
                ),
              ),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: btn(en ? 'Stop' : '중지', stopCurrentGeneration)),
            ],
            if (status == 'done')
              Row(children: [
                Expanded(child: Text(en ? 'Applied.' : '고친 글로 바꿨습니다.', style: TextStyle(fontSize: 12, color: c.textMuted))),
                btn(en ? 'Undo' : '되돌리기', undo),
                const SizedBox(width: 6),
                btn(en ? 'Close' : '닫기', widget.onClose, primary: true),
              ]),
            if (status == 'error')
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(error, style: const TextStyle(fontSize: 12, color: AppColors.danger))),
          ]),
        ),
      ),
    );
  }
}
