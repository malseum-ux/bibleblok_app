// 교재 화면 — 웹 CellView.jsx 와 같은 배치·동작
// 위: 교재 탭 6개 + 같은 본문 설교 뱃지 + 기본정보·저장·내보내기
// 아래: 지시 항목(사용자 항목)·복사·글자 크기·생성 / 결과
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../models/item.dart';
import '../providers/app_state.dart';
import '../services/ai.dart';
import '../services/file_io.dart';
import '../services/prompts.dart';
import '../services/rich_doc.dart';
import '../services/store.dart';
import '../services/text_history.dart';
import '../theme/app_colors.dart';
import '../widgets/forms.dart';
import '../widgets/rich_view.dart';
import '../widgets/step_widgets.dart';
import '../widgets/ui.dart';

const cellSubtitles = {
  'sharing': '삶으로 나누는 말씀',
  'theological': '뿌리에서 열매까지',
  'gospel': '그리스도 안에서',
  'literary': '이야기 속으로',
  'psychological': '말씀 앞에 나를 내려놓기',
  'communal': '함께 세상으로',
};

class CellView extends ConsumerStatefulWidget {
  final Item item;
  final String lang;
  final String bible;
  final double fontSize;
  final ValueChanged<double> onFontSizeChange;
  final bool isMobile;
  final ValueChanged<Item> onGoToSermon;
  const CellView({
    super.key,
    required this.item,
    required this.lang,
    required this.bible,
    required this.fontSize,
    required this.onFontSizeChange,
    required this.isMobile,
    required this.onGoToSermon,
  });

  @override
  ConsumerState<CellView> createState() => _CellViewState();
}

class _CellViewState extends ConsumerState<CellView> {
  Item get item => widget.item;
  String get lang => widget.lang;
  bool get en => lang == 'en';
  Store get store => ref.read(folderProvider).store!;

  int currentStep = 0;
  String aiContent = '';
  final TextHistory resultHistory = TextHistory('');
  bool loading = false;
  bool refining = false;
  String? error;
  bool editing = false;
  bool instructionsOpen = false;
  List<String> selectedCustomKeys = [];
  final keywordCtrl = TextEditingController();
  bool aiCopied = false;
  bool saved = false;
  bool infoOpen = false;
  Timer? editTimer;

  StepDef get step => cellSteps[currentStep];
  List<CustomStepItem> get customItems => store.customItemsFor('cell', step.key);

  @override
  void initState() {
    super.initState();
    _onStepChanged();
    resultHistory.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    editTimer?.cancel();
    resultHistory.dispose();
    keywordCtrl.dispose();
    super.dispose();
  }

  void _onStepChanged() {
    aiContent = item.steps[currentStep] ?? '';
    resultHistory.reset(aiContent);
    instructionsOpen = false;
    error = null;
    editing = false;
    final allIds = customItems.map((c) => c.id).toList();
    selectedCustomKeys = [...selectedCustomKeys.where(allIds.contains), ...allIds.where((id) => !selectedCustomKeys.contains(id))];
    keywordCtrl.text = store.keywordFor('cell', step.key);
  }

  void selectStep(int index) => setState(() {
        if (editing) _commitEdit();
        currentStep = index;
        _onStepChanged();
      });

  Item? matchedSermon() {
    final passage = item.passage;
    if (passage == null || passage.isEmpty) return null;
    String norm(String? s) => (s ?? '').replaceAll(RegExp(r'\s'), '').toLowerCase();
    final cp = norm(passage);
    for (final s in [...store.items['sermon']!, ...store.items['dawn']!]) {
      final sp = norm(s.passage);
      if (sp == cp || sp.contains(cp) || cp.contains(sp)) return s;
    }
    return null;
  }

  static final _rememberRe = RegExp(r'기억해(?:줘|주세요)?');

  Future<void> generate() async {
    setState(() {
      loading = true;
      editing = false;
      error = null;
    });

    var effectiveKeyword = keywordCtrl.text;
    if (_rememberRe.hasMatch(effectiveKeyword)) {
      final cleaned = effectiveKeyword.replaceAll(_rememberRe, '').replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '').trim();
      await store.setKeyword('cell', step.key, cleaned);
      if (cleaned.isNotEmpty) await store.addMemory('cell', step.key, cleaned);
      effectiveKeyword = cleaned;
      keywordCtrl.text = cleaned;
    }

    final prevContent = aiContent;
    final sep = prevContent.isNotEmpty ? '\n\n${'─' * 30}\n\n' : '';
    final titleLine = '# ${step.ko} — ${cellSubtitles[step.key] ?? ''}\n\n';
    var accumulated = prevContent + sep + titleLine;
    setState(() => aiContent = accumulated);

    // 같은 본문의 설교 연구를 참고 자료로 (단계 순서대로, HTML 태그는 뺀다)
    var sermonContext = '';
    final sermon = matchedSermon();
    if (sermon != null) {
      final keys = sermon.steps.keys.toList()..sort();
      final parts = [
        for (final k in keys)
          if ((sermon.steps[k] ?? '').isNotEmpty) sermon.steps[k]!.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
      ].where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) sermonContext = parts.join('\n\n---\n\n');
    }

    final memory = store.buildMemoryPrompt('cell', step.key);
    final customText = customItems.where((i) => selectedCustomKeys.contains(i.id)).map((i) => i.text).join('\n');
    final idx = currentStep;

    try {
      await generateCellMaterial(item.passage, widget.bible, lang, step.key, (text) {
        accumulated = prevContent + sep + titleLine + text;
        if (mounted) setState(() => aiContent = accumulated);
      }, customText, effectiveKeyword, sermonContext, memory);
      resultHistory.reset(accumulated);
      await _saveStep(idx, accumulated);
    } on AbortedException {
      // 사용자가 중지
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveStep(int idx, String text) async {
    item.finalSteps.remove(idx); // 웹과 같이 final_content 는 비운다
    await store.saveStep(item, idx, text);
  }

  /// 교재의 // 명령 — 교재는 연구 단계가 없어 문맥·신학자 관점만
  Future<void> handleAiSlashCommand(SlashCommand cmd) async {
    resultHistory.forceSnapshot();
    setState(() => refining = true);
    final useTheological = cmd.mode != 'research';
    final useContext = cmd.mode != 'fresh';
    try {
      await executeInlineCommand(cmd.instruction, useContext ? cmd.contextBefore : '', useContext ? cmd.contextAfter : '', lang,
          widget.bible, item.passage, item.title, cmd.write, null, useTheological);
    } catch (_) {
      cmd.write('');
    } finally {
      if (mounted) setState(() => refining = false);
    }
  }

  /// 드래그해서 고친 결과를 교재 내용에 반영·저장
  Future<void> applyAiEdit(String html) async {
    setState(() => aiContent = html);
    await _saveStep(currentStep, html);
  }

  void startEdit() => setState(() {
        resultHistory.reset(aiContent);
        instructionsOpen = false;
        editing = true;
      });

  void _commitEdit() {
    editing = false;
    aiContent = resultHistory.text;
    _saveStep(currentStep, aiContent);
  }

  void onEdited(String html) {
    resultHistory.onChange(html);
    editTimer?.cancel();
    editTimer = Timer(const Duration(milliseconds: 800), () => _saveStep(currentStep, resultHistory.text));
  }

  Future<void> handleSave() async {
    for (final e in item.steps.entries.toList()) {
      if (e.value.isNotEmpty) await _saveStep(e.key, e.value);
    }
    setState(() => saved = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => saved = false);
    });
  }

  Future<void> handleSaveInfo(Map<String, String?> data) async {
    item.passage = data['passage'];
    item.title = data['title'];
    item.date = data['date'];
    try {
      await store.saveItem(item);
      setState(() => infoOpen = false);
    } catch (e) {
      if (mounted) showAlert(context, '${en ? 'Save failed: ' : '저장 실패: '}$e');
    }
  }

  Future<void> exportItem() async {
    final data = {
      'version': 2,
      'tab': 'cell',
      'item': {'id': item.id, 'passage': item.passage, 'title': item.title, 'date': item.date, 'folderId': null, 'createdAt': item.createdAt},
      'steps': item.toJson()['steps'],
    };
    final name = '${item.date ?? 'item'}-${(item.title?.isNotEmpty == true ? item.title : null) ?? (item.passage?.isNotEmpty == true ? item.passage : null) ?? 'export'}.json';
    await saveTextFile(name, const JsonEncoder.withIndent('  ').convert(data));
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(folderProvider);
    final c = context.c;
    final display = editing ? resultHistory.text : aiContent;
    final sermon = matchedSermon();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 교재 탭 + 설교 뱃지 + 버튼
      Container(
        decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                for (var i = 0; i < cellSteps.length; i++) ...[
                  // 웹 교재 탭은 언어와 관계없이 한국어 이름 + 영어 이름
                  StepTab(
                    step: cellSteps[i],
                    active: cellSteps[i].index == currentStep,
                    hasContent: (item.steps[cellSteps[i].index] ?? '').isNotEmpty,
                    lang: 'ko',
                    onTap: () => selectStep(cellSteps[i].index),
                  ),
                  if (i < cellSteps.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Opacity(opacity: 0.4, child: Text('›', style: TextStyle(fontSize: 18, color: c.textMuted))),
                    ),
                ],
              ]),
            ),
          ),
          if (sermon != null)
            Tooltip(
              message: '같은 본문의 설교가 있습니다. 클릭하면 이동합니다.',
              child: InkWell(
                onTap: () => widget.onGoToSermon(sermon),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: c.accentLight, border: Border.all(color: c.accent), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('설교', style: TextStyle(fontSize: 11, color: c.accent, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text((sermon.title?.isNotEmpty == true ? sermon.title : sermon.passage) ?? '',
                            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.accent)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))),
            child: IntrinsicWidth(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SmallButton(label: en ? 'Info ${infoOpen ? '▲' : '▼'}' : '기본정보 ${infoOpen ? '▲' : '▼'}', active: infoOpen, onPressed: () => setState(() => infoOpen = !infoOpen)),
              const SizedBox(height: 4),
              SmallButton(label: saved ? (en ? 'Saved' : '저장됨') : (en ? 'Save' : '저장'), active: saved, onPressed: handleSave),
              const SizedBox(height: 4),
              Tooltip(
                message: en ? 'Export as .json file' : '이 항목을 .json 파일로 내보내기 (에어드롭·공유용)',
                child: SmallButton(label: en ? 'Export' : '내보내기', onPressed: exportItem),
              ),
            ])),
          ),
        ]),
      ),
      if (infoOpen)
        Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
          decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: CellForm(initial: {'passage': item.passage, 'title': item.title, 'date': item.date}, isEdit: true, lang: lang, onSave: handleSaveInfo),
          ),
        ),
      Expanded(
        child: TapRegion(
          onTapOutside: (_) {
            if (editing) setState(_commitEdit);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
              child: Row(children: [
                SmallButton(
                  label: '${en ? 'Instructions' : '지시 항목'} ${selectedCustomKeys.length}/${customItems.length}',
                  active: instructionsOpen,
                  onPressed: () => setState(() => instructionsOpen = !instructionsOpen),
                ),
                const Spacer(),
                if (display.isNotEmpty && !loading) ...[
                  SmallButton(
                    label: aiCopied ? (en ? 'Copied' : '복사됨') : (en ? 'Copy' : '복사'),
                    active: aiCopied,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: stripHtml(display)));
                      setState(() => aiCopied = true);
                      Future.delayed(const Duration(milliseconds: 1500), () {
                        if (mounted) setState(() => aiCopied = false);
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  FontSizeButtons(fontSize: widget.fontSize, onChange: widget.onFontSizeChange),
                  const SizedBox(width: 8),
                ],
                AccentButton(
                  loading ? (en ? 'Stop' : '중지') : (aiContent.isNotEmpty ? (en ? 'Regenerate' : '다시 생성') : (en ? 'Generate' : 'AI 생성')),
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  color: loading ? AppColors.danger : null,
                  onPressed: loading ? stopCurrentGeneration : generate,
                ),
              ]),
            ),
            if (!editing && instructionsOpen)
              InstructionsPanel(
                items: const [],
                selected: const [],
                onToggle: (_) {},
                customItems: customItems,
                customSelected: selectedCustomKeys,
                onToggleCustom: (id) => setState(() {
                  selectedCustomKeys = selectedCustomKeys.contains(id) ? (selectedCustomKeys..remove(id)) : [...selectedCustomKeys, id];
                }),
                onAddCustom: (label) async {
                  await store.addCustomItem('cell', step.key, label);
                  setState(() => selectedCustomKeys = [...selectedCustomKeys, customItems.last.id]);
                },
                onDeleteCustom: (id) async {
                  await store.deleteCustomItem(id);
                  setState(() => selectedCustomKeys.remove(id));
                },
                onReorderCustom: (ids) => store.setCustomItemOrders(ids),
                keywordCtrl: keywordCtrl,
                lang: lang,
              ),
            Expanded(child: _body(c)),
          ]),
        ),
      ),
    ]);
  }

  Widget _body(AppColors c) {
    if (editing) {
      return RichView(
        key: const ValueKey('cell-edit'),
        source: resultHistory.text,
        fontSize: widget.fontSize,
        editable: true,
        autoFocus: true,
        showToolbar: true,
        onChanged: onEdited,
        onEnterCommand: handleAiSlashCommand,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null)
        Container(
          margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(8)),
          child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ),
      Expanded(
        child: aiContent.isNotEmpty
            ? TapToEdit(
                enabled: !loading,
                onTap: startEdit,
                child: RichView(
                  key: const ValueKey('cell-view'),
                  source: aiContent,
                  fontSize: widget.fontSize,
                  streaming: loading,
                  selectionEdit: loading || refining
                      ? null
                      : SelectionEditConfig(lang: lang, bible: widget.bible, passage: item.passage, title: item.title, onApply: applyAiEdit),
                ),
              )
            : (loading
                ? const SizedBox()
                : Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Text(
                      (item.passage?.isNotEmpty == true)
                          ? (en ? 'Click Generate to create ${step.en}.' : 'AI 생성 버튼을 눌러 ${step.ko}을 생성합니다.')
                          : (en ? 'Enter a Bible passage in Info first.' : '기본정보에서 성경 본문을 먼저 입력하세요.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textMuted, fontSize: 13, height: 1.7),
                    ),
                  )),
      ),
    ]);
  }
}
