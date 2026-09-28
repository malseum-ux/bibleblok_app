// 성경나침반 내설교 한 편 보기·수정 — 설교문 초안 칸과 같은 모양
// 수정: 워드블록 편집과 같이 구절 입력 + 본문, [저장][취소]. 저장하면 원래 .scb 에 바로 저장된다.
// 본문은 설교문 초안과 같은 편집기 — //지시 · //-지시 · //+지시 + Enter 로 AI 가 그 자리에 쓴다.
// .scb 는 서식 없는 글이라 저장할 때 글자만 남긴다.
// 웹 WordblokSermonView.jsx 와 같은 구성
import 'package:flutter/material.dart';

import '../services/prompts.dart';
import '../services/wordblok_sermons.dart';
import '../theme/app_colors.dart';
import '../widgets/rich_view.dart';
import '../widgets/ui.dart';

/// 편집기 HTML → 글자 (문단은 줄바꿈) — 웹 htmlToText 와 같은 규칙
String _htmlToText(String html) {
  if (!html.trimLeft().startsWith('<')) return html;
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class WordblokSermonView extends StatefulWidget {
  final WordblokItem item;
  final String file;
  final String lang;
  final double fontSize;
  final String bible;

  /// 저장한 뒤 — 구절이 바뀐 항목
  final ValueChanged<WordblokItem>? onSaved;
  const WordblokSermonView({super.key, required this.item, required this.file, this.lang = 'ko', this.fontSize = 14, required this.bible, this.onSaved});

  @override
  State<WordblokSermonView> createState() => _WordblokSermonViewState();
}

class _WordblokSermonViewState extends State<WordblokSermonView> {
  String? text; // null = 불러오는 중
  bool editing = false;
  bool saving = false;
  bool refining = false; // // 명령으로 AI 가 쓰는 중
  final refCtrl = TextEditingController();
  String editText = ''; // 편집기 값 (글자 또는 HTML)

  @override
  void initState() {
    super.initState();
    readWordblokSermon(widget.item.path, widget.item.id).then((t) {
      if (mounted) setState(() => text = t);
    }).catchError((_) {
      if (mounted) setState(() => text = '');
    });
  }

  @override
  void dispose() {
    refCtrl.dispose();
    super.dispose();
  }

  void openEdit() {
    final item = widget.item;
    refCtrl.text = passageLabel(item.book, item.chapter, item.verse);
    editText = text ?? '';
    setState(() => editing = true);
  }

  /// 설교문 초안과 같은 // 명령 (연구 단계가 없으므로 //-·//+ 도 문맥만 함께 보낸다)
  Future<void> handleSlashCommand(SlashCommand cmd) async {
    setState(() => refining = true);
    final useTheological = cmd.mode != 'research';
    final useContext = cmd.mode != 'fresh';
    final item = widget.item;
    final ref = refCtrl.text.trim();
    try {
      await executeInlineCommand(cmd.instruction, useContext ? cmd.contextBefore : '', useContext ? cmd.contextAfter : '', widget.lang,
          widget.bible, ref.isNotEmpty ? ref : passageLabel(item.book, item.chapter, item.verse), item.title, cmd.write, null, useTheological);
    } catch (_) {
      cmd.write('');
    } finally {
      if (mounted) setState(() => refining = false);
    }
  }

  Future<void> handleSave() async {
    if (saving || refining) return;
    setState(() => saving = true);
    final ko = widget.lang == 'ko';
    try {
      final item = widget.item;
      final plain = _htmlToText(editText);
      final ref = await saveWordblokSermon(item.path, item.id, refCtrl.text.trim(), plain);
      if (!mounted) return;
      setState(() {
        text = plain.trim();
        editing = false;
      });
      widget.onSaved?.call(item.withRef(ref.book, ref.chapter, ref.verse));
    } catch (e) {
      if (mounted) showAlert(context, '${ko ? '저장하지 못했습니다: ' : 'Save failed: '}${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// 웹의 작은 버튼 — primary 는 강조색 바탕, 아니면 테두리만
  Widget _btn(String label, VoidCallback? onPressed, {bool primary = false}) {
    final c = context.c;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: primary ? c.accent : Colors.transparent,
        foregroundColor: primary ? Colors.white : c.textMuted,
        disabledForegroundColor: primary ? Colors.white : c.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: primary ? BorderSide.none : BorderSide(color: c.border)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ko = widget.lang == 'ko';
    final item = widget.item;
    final meta = [item.date, passageLabel(item.book, item.chapter, item.verse), widget.file].where((s) => s.isNotEmpty).join(' · ');
    OutlineInputBorder border() => OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.border));
    InputDecoration deco({String? hint, EdgeInsets? padding}) => InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: c.textMuted),
          filled: true,
          fillColor: c.bg,
          contentPadding: padding,
          border: border(),
          enabledBorder: border(),
          focusedBorder: border(),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          Text((ko ? '설교문 초안' : 'Sermon Draft').toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: c.textMuted)),
          const SizedBox(width: 8),
          Expanded(
            child: Opacity(
              opacity: 0.8,
              child: Text(ko ? '· 성경나침반 내설교' : '· WordBlok sermon',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.textMuted)),
            ),
          ),
          if (!editing && text != null) ...[
            const SizedBox(width: 8),
            _btn(ko ? '수정' : 'Edit', openEdit),
          ],
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          // 편집기는 높이가 정해져야 해서 — 화면에 맞게, 최소 360 (웹 minHeight 360)
          final editorHeight = (box.maxHeight - 250).clamp(360.0, double.infinity);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(item.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textHeading)),
              const SizedBox(height: 6),
              if (meta.isNotEmpty) ...[
                Text(meta, style: TextStyle(fontSize: 12, color: c.textMuted)),
                const SizedBox(height: 20),
              ],
              if (editing) ...[
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: refCtrl,
                      style: TextStyle(fontSize: 14, color: c.text),
                      decoration: deco(hint: ko ? '예) 요 3:16' : 'e.g. John 3:16', padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(ko ? '맵핑' : 'Passage', style: TextStyle(fontSize: 10, color: c.textMuted)),
                ]),
                const SizedBox(height: 8),
                // 설교문 초안과 같은 편집기 (도구 막대 + // 명령)
                Opacity(
                  opacity: refining ? 0.7 : 1,
                  child: Container(
                    height: editorHeight,
                    decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(4)),
                    clipBehavior: Clip.antiAlias,
                    child: RichView(
                      source: editText,
                      fontSize: widget.fontSize,
                      editable: !refining && !saving,
                      showToolbar: true,
                      onChanged: (html) => editText = html, // 화면을 다시 그리지 않고 값만 기억 (다음 그리기 때 source 로 쓰인다)
                      onEnterCommand: handleSlashCommand,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Opacity(
                    opacity: saving || refining ? 0.5 : 1,
                    child: _btn(saving ? (ko ? '저장 중...' : 'Saving...') : (ko ? '저장' : 'Save'), saving || refining ? null : handleSave, primary: true),
                  ),
                  const SizedBox(width: 8),
                  _btn(ko ? '취소' : 'Cancel', () => setState(() => editing = false)),
                ]),
              ] else if (text == null)
                Text(ko ? '불러오는 중...' : 'Loading...', style: TextStyle(fontSize: 13, color: c.textMuted))
              else
                SelectableText(
                  text!.isNotEmpty ? text! : (ko ? '내용이 없습니다' : 'No content'),
                  style: TextStyle(fontSize: widget.fontSize, height: 1.8, color: c.text),
                ),
            ]),
          );
        }),
      ),
    ]);
  }
}
