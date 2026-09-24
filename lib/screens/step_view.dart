// 설교·예배·새벽 단계 화면 — 웹 StepView.jsx 와 같은 배치·동작
// 위: 단계 탭 + 교재 뱃지 + 기본정보·저장·내보내기
// 왼쪽: AI 결과 (지시 항목·글자 크기·생성) / 가운데: 너비 조절 / 오른쪽: 설교문 초안 (설교 탭만)
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants.dart';
import '../models/item.dart';
import '../providers/app_state.dart';
import '../providers/plan.dart';
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

class StepView extends ConsumerStatefulWidget {
  final Item item;
  final String lang;
  final String bible;
  final double fontSize;
  final ValueChanged<double> onFontSizeChange;
  final bool isMobile;
  final ValueChanged<Item> onGoToCell;
  const StepView({
    super.key,
    required this.item,
    required this.lang,
    required this.bible,
    required this.fontSize,
    required this.onFontSizeChange,
    required this.isMobile,
    required this.onGoToCell,
  });

  @override
  ConsumerState<StepView> createState() => _StepViewState();
}

class _StepViewState extends ConsumerState<StepView> {
  Item get item => widget.item;
  String get tab => item.tab;
  String get lang => widget.lang;
  bool get ko => lang == 'ko';
  bool get en => lang == 'en';
  List<StepDef> get steps => stepsForTab(tab);
  Store get store => ref.read(folderProvider).store!;

  int currentStep = 0;
  String content = '';
  late final TextHistory draftHistory = TextHistory(item.draft ?? '');
  final TextHistory resultHistory = TextHistory('');
  bool editing = false;
  bool draftEditing = false;
  bool refining = false;
  bool manualSaved = false;
  bool loading = false;
  String? error;
  bool instructionsOpen = false;
  List<String> selectedItems = [];
  Map<String, List<String>> stepSelectedItems = {};
  final keywordCtrl = TextEditingController();
  List<String> selectedCustomKeys = [];
  Map<String, List<String>> stepSelectedCustomKeys = {};
  bool infoOpen = false;
  double leftPct = 50;
  bool stepPanelVisible = true;
  String mobilePanel = 'result';
  String lastSelection = '';
  Timer? draftTimer;
  Timer? resultEditTimer;

  StepDef get step => currentStep < steps.length ? steps[currentStep] : steps.first;
  Map<String, List<StepItem>> get stepItemsDefs => switch (tab) {
        'sermon' => sermonStepItems,
        'worship' => worshipStepItems,
        _ => dawnStepItems,
      };
  List<StepItem> get currentItems => stepItemsDefs[step.key] ?? const [];
  List<CustomStepItem> get customItems => store.customItemsFor(tab, step.key);
  bool get hasItems => currentItems.length >= 2 || customItems.isNotEmpty;
  int get storedIndex => tab == 'sermon' ? currentStep : 0;

  @override
  void initState() {
    super.initState();
    _onStepChanged();
    selectedCustomKeys = customItems.map((c) => c.id).toList();
    draftHistory.addListener(_rebuild);
    resultHistory.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    draftTimer?.cancel();
    resultEditTimer?.cancel();
    draftHistory.dispose();
    resultHistory.dispose();
    keywordCtrl.dispose();
    super.dispose();
  }

  /// 단계가 바뀔 때 — 웹의 여러 useEffect 를 한곳에
  void _onStepChanged() {
    content = item.steps[storedIndex] ?? '';
    error = null;
    instructionsOpen = false;
    selectedItems = currentItems.map((i) => i.key).toList();
    stepSelectedItems = {};
    stepSelectedCustomKeys = {};
    editing = false;
    // 이전에 고른 사용자 항목은 유지하고, 새 항목은 선택 상태로 더한다
    final allIds = customItems.map((c) => c.id).toList();
    selectedCustomKeys = [...selectedCustomKeys.where(allIds.contains), ...allIds.where((id) => !selectedCustomKeys.contains(id))];
    keywordCtrl.text = store.keywordFor(tab, step.key);
  }

  void selectStep(int index) => setState(() {
        currentStep = index;
        _onStepChanged();
      });

  // ── 지시 항목 ─────────────────────────────────────────────────────────────

  List<String> get displaySelected => tab == 'sermon' ? selectedItems : (stepSelectedItems[step.key] ?? currentItems.map((i) => i.key).toList());
  List<String> get displayCustomSelected =>
      tab == 'sermon' ? selectedCustomKeys : (stepSelectedCustomKeys[step.key] ?? customItems.map((i) => i.id).toList());

  void toggleItem(String key) => setState(() {
        if (tab == 'sermon') {
          selectedItems = selectedItems.contains(key) ? (selectedItems..remove(key)) : [...selectedItems, key];
        } else {
          final current = [...(stepSelectedItems[step.key] ?? currentItems.map((i) => i.key))];
          current.contains(key) ? current.remove(key) : current.add(key);
          stepSelectedItems[step.key] = current;
        }
      });

  void toggleCustomItem(String id) => setState(() {
        if (tab == 'sermon') {
          selectedCustomKeys = selectedCustomKeys.contains(id) ? (selectedCustomKeys..remove(id)) : [...selectedCustomKeys, id];
        } else {
          final current = [...(stepSelectedCustomKeys[step.key] ?? customItems.map((i) => i.id))];
          current.contains(id) ? current.remove(id) : current.add(id);
          stepSelectedCustomKeys[step.key] = current;
        }
      });

  Future<void> addCustomItem(String label) async {
    await store.addCustomItem(tab, step.key, label);
    setState(() => selectedCustomKeys = [...selectedCustomKeys, customItems.last.id]);
  }

  Future<void> deleteCustomItem(String id) async {
    await store.deleteCustomItem(id);
    setState(() {
      selectedCustomKeys.remove(id);
      stepSelectedCustomKeys[step.key] = [...(stepSelectedCustomKeys[step.key] ?? [])]..remove(id);
    });
  }

  // ── AI 생성 ───────────────────────────────────────────────────────────────

  static final _rememberRe = RegExp(r'기억해(?:줘|주세요)?');

  Future<void> generate() async {
    // 구독 확인 (판별은 providers/plan.dart 한 곳에서만)
    if (!canUseAi(ref.read(subscriptionProvider).valueOrNull)) {
      setState(() => error = ko ? '구독이 필요합니다.' : 'A subscription is required.');
      return;
    }
    setState(() {
      editing = false;
      loading = true;
      error = null;
    });

    // "기억해(줘/주세요)" — 지시어를 기억하고, 그 말을 뺀 지시어로 생성
    var effectiveKeyword = keywordCtrl.text;
    if (_rememberRe.hasMatch(effectiveKeyword)) {
      final cleaned = effectiveKeyword.replaceAll(_rememberRe, '').replaceAll(RegExp(r'^[,\s]+|[,\s]+$'), '').trim();
      await store.setKeyword(tab, step.key, cleaned);
      if (cleaned.isNotEmpty) await store.addMemory(tab, step.key, cleaned);
      effectiveKeyword = cleaned;
      keywordCtrl.text = cleaned;
    }

    final prevContent = content;
    final sep = prevContent.isNotEmpty ? '\n\n${'─' * 30}\n\n' : '';
    final activeItems = hasItems ? selectedItems : null;
    final memory = store.buildMemoryPrompt(tab, step.key);
    String customTextOf(List<String> ids, List<CustomStepItem> items) =>
        items.where((i) => ids.contains(i.id)).map((i) => i.text).join('\n');
    Map<String, String> customStepTexts() {
      final all = store.customItemsForTab(tab);
      final out = <String, String>{};
      for (final s in steps) {
        final stepCustom = all.where((i) => i.stepKey == s.key).toList();
        final ids = stepSelectedCustomKeys[s.key] ?? stepCustom.map((i) => i.id).toList();
        final text = customTextOf(ids, stepCustom);
        if (text.isNotEmpty) out[s.key] = text;
      }
      return out;
    }

    void onChunk(String text) {
      if (mounted) setState(() => content = prevContent + sep + text);
    }

    final idx = storedIndex;
    try {
      final String full;
      if (tab == 'sermon') {
        final seriesCtx = store.getSeriesContext('sermon', item.category, item.id);
        full = await generateSermonStep(step.key, item.passage, item.emphasis, lang, widget.bible, seriesCtx, onChunk,
            activeItems, effectiveKeyword, customTextOf(selectedCustomKeys, customItems), memory);
      } else if (tab == 'worship') {
        full = await generateWorshipCombined(item.date, item.season, item.lectionary, lang, widget.bible, stepSelectedItems, onChunk,
            effectiveKeyword, customStepTexts(), memory);
      } else {
        final seriesCtx = store.getSeriesContext('dawn', item.category, item.id);
        full = await generateDawnCombined(item.passage, item.emphasis, lang, widget.bible, seriesCtx, stepSelectedItems, onChunk,
            effectiveKeyword, customStepTexts(), memory);
      }
      final combined = prevContent + sep + full;
      await store.saveStep(item, idx, combined);
      if (mounted) setState(() => content = combined);
    } on AbortedException {
      // 사용자가 중지 — 에러 표시 없이 지금까지 받은 내용 유지
    } catch (e) {
      if (mounted) setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ── 초안 ─────────────────────────────────────────────────────────────────

  void handleDraftChange(String text) {
    draftHistory.onChange(text);
    draftTimer?.cancel();
    draftTimer = Timer(const Duration(milliseconds: 500), () {
      item.draft = text;
      store.saveItem(item);
    });
  }

  /// 선택한 글(없으면 전체)을 설교문 초안 끝에 붙인다
  void applyToSermon() {
    if (content.isEmpty) return;
    final textToAdd = lastSelection.isNotEmpty ? lastSelection : content;
    lastSelection = '';
    final existing = draftHistory.text;
    final addHtml = isHtml(textToAdd) ? textToAdd : linesToHtml(textToAdd);
    final separator = stripHtml(existing).trim().isNotEmpty ? '<p><br></p>' : '';
    handleDraftChange(existing + separator + addHtml);
  }

  Future<void> refineSermonDraft() async {
    final plain = stripHtml(draftHistory.text);
    if (plain.trim().isEmpty || refining || loading) return;
    final original = draftHistory.text;
    draftHistory.forceSnapshot();
    setState(() => refining = true);
    try {
      final refined = await refineDraft(plain, lang, widget.bible, (text) => draftHistory.onChange(text));
      handleDraftChange(refined);
    } catch (_) {
      handleDraftChange(original);
    } finally {
      if (mounted) setState(() => refining = false);
    }
  }

  // ── // 명령 · 드래그해서 고치기 ─────────────────────────────────────────────

  /// //- · //+ 명령에 함께 보낼 내 연구 — 내용이 있는 단계만 (excludeIndex 단계는 제외)
  List<StepData>? collectStepsData(int? excludeIndex) {
    final defs = tab == 'sermon' ? steps : const [StepDef(0, 'research', '연구 내용', 'Research')];
    final list = <StepData>[
      for (final s in defs)
        if (s.index != excludeIndex && stripHtml(item.steps[s.index]).trim().isNotEmpty)
          (label: s.label(lang), content: stripHtml(item.steps[s.index])),
    ];
    return list.isEmpty ? null : list;
  }

  /// 결과 창의 // 명령 — "내 연구" 는 지금 단계를 뺀 다른 단계들 (예배·새벽은 단계가 하나라 없음)
  Future<void> handleStepSlashCommand(SlashCommand cmd) async {
    resultHistory.forceSnapshot();
    setState(() => refining = true);
    final useTheological = cmd.mode != 'research';
    final useContext = cmd.mode != 'fresh';
    final stepsData = useContext && tab == 'sermon' ? collectStepsData(currentStep) : null;
    try {
      await executeInlineCommand(cmd.instruction, useContext ? cmd.contextBefore : '', useContext ? cmd.contextAfter : '', lang,
          widget.bible, item.passage, item.title, cmd.write, stepsData, useTheological);
    } catch (_) {
      cmd.write('');
    } finally {
      if (mounted) setState(() => refining = false);
    }
  }

  /// 초안 창의 // 명령 — "내 연구" 는 모든 단계
  Future<void> handleDraftSlashCommand(SlashCommand cmd) async {
    draftHistory.forceSnapshot();
    setState(() => refining = true);
    final useTheological = cmd.mode != 'research';
    final useContext = cmd.mode != 'fresh';
    final stepsData = useContext ? collectStepsData(null) : null;
    try {
      await executeInlineCommand(cmd.instruction, useContext ? cmd.contextBefore : '', useContext ? cmd.contextAfter : '', lang,
          widget.bible, item.passage, item.title, cmd.write, stepsData, useTheological);
    } catch (_) {
      cmd.write('');
    } finally {
      if (mounted) setState(() => refining = false);
    }
  }

  /// 드래그해서 고친 결과를 단계 내용에 반영·저장
  Future<void> applyResultEdit(String html) async {
    setState(() => content = html);
    await store.saveStep(item, storedIndex, html);
  }

  /// 드래그해서 고친 결과를 초안에 반영 (되돌리기 기록 유지)
  Future<void> applyDraftEdit(String html) async {
    draftHistory.forceSnapshot();
    handleDraftChange(html);
  }

  SelectionEditConfig selectionEdit(Future<void> Function(String) onApply) =>
      SelectionEditConfig(lang: lang, bible: widget.bible, passage: item.passage, title: item.title, onApply: onApply);

  // ── 결과 편집 · 저장 ──────────────────────────────────────────────────────

  void startEdit() => setState(() {
        resultHistory.reset(content);
        instructionsOpen = false;
        editing = true;
      });

  void finishEdit() {
    if (!editing) return;
    setState(() {
      content = resultHistory.text;
      editing = false;
    });
  }

  void onResultEdited(String html) {
    resultHistory.onChange(html);
    resultEditTimer?.cancel();
    resultEditTimer = Timer(const Duration(milliseconds: 800), () async {
      final text = resultHistory.text;
      if (text.trim().isEmpty) return;
      await store.saveStep(item, storedIndex, text);
    });
  }

  Future<void> handleManualSave() async {
    try {
      draftTimer?.cancel();
      if (stripHtml(draftHistory.text).trim().isNotEmpty && tab != 'worship') {
        item.draft = draftHistory.text;
        await store.saveItem(item);
      }
      final saveContent = editing ? resultHistory.text : content;
      if (saveContent.trim().isNotEmpty) {
        resultEditTimer?.cancel();
        await store.saveStep(item, storedIndex, saveContent);
        if (editing) content = saveContent;
      }
      setState(() => manualSaved = true);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => manualSaved = false);
      });
    } catch (e) {
      if (mounted) showAlert(context, '저장 실패: $e');
    }
  }

  Future<void> handleSaveInfo(Map<String, String?> data) async {
    item.date = data['date'];
    if (tab == 'worship') {
      item.season = data['season'];
      item.lectionary = data['lectionary'];
    } else {
      item.category = data['category'];
      item.title = data['title'];
      item.passage = data['passage'];
      item.emphasis = data['emphasis'];
    }
    try {
      await store.saveItem(item);
      setState(() => infoOpen = false);
    } catch (e) {
      if (mounted) showAlert(context, '${ko ? '저장 실패: ' : 'Save failed: '}$e');
    }
  }

  /// 이 항목을 .json 파일로 (웹 handleExportItem 과 같은 형식)
  Future<void> exportItem() async {
    final j = item.toJson();
    final data = {
      'version': 2,
      'tab': tab,
      'item': {
        'id': item.id, 'date': item.date, 'category': item.category, 'title': item.title, 'passage': item.passage,
        'emphasis': item.emphasis, 'season': item.season, 'lectionary': item.lectionary, 'draft': item.draft,
        'folderId': null, 'createdAt': item.createdAt,
      },
      'steps': j['steps'],
    };
    final name = '${item.date ?? 'item'}-${(item.title?.isNotEmpty == true ? item.title : null) ?? (item.passage?.isNotEmpty == true ? item.passage : null) ?? 'export'}.json';
    await saveTextFile(name, const JsonEncoder.withIndent('  ').convert(data));
  }

  Item? matchedCell() {
    final passage = item.passage;
    if (passage == null || passage.isEmpty) return null;
    String norm(String? s) => (s ?? '').replaceAll(RegExp(r'\s'), '').toLowerCase();
    final sp = norm(passage);
    for (final c in store.items['cell']!) {
      final cp = norm(c.passage);
      if (cp == sp || cp.contains(sp) || sp.contains(cp)) return c;
    }
    return null;
  }

  // ── 화면 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.watch(folderProvider); // 저장소 변경(사용자 항목 등)에 맞춰 다시 그린다
    final c = context.c;
    final isSermon = tab == 'sermon';
    final isMobile = widget.isMobile;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _stepBar(c),
      if (infoOpen)
        Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
          decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: tab == 'worship'
                ? WorshipForm(
                    initial: {'date': item.date, 'season': item.season, 'lectionary': item.lectionary},
                    lang: lang,
                    bible: widget.bible,
                    onSave: handleSaveInfo,
                  )
                : SermonDawnForm(
                    isDawn: tab == 'dawn',
                    initial: {'date': item.date, 'category': item.category, 'title': item.title, 'passage': item.passage, 'emphasis': item.emphasis},
                    lang: lang,
                    onSave: handleSaveInfo,
                  ),
          ),
        ),
      if (isMobile && isSermon)
        Container(
          decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            for (final (key, label) in en ? const [('result', 'AI Result'), ('draft', 'Sermon Draft')] : const [('result', 'AI 결과'), ('draft', '설교 초안')])
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => mobilePanel = key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    color: mobilePanel == key ? c.accent : Colors.transparent,
                    child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mobilePanel == key ? Colors.white : c.textMuted)),
                  ),
                ),
              ),
          ]),
        ),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final showResult = !(isMobile && isSermon && mobilePanel == 'draft') && !(isSermon && !isMobile && !stepPanelVisible);
          final showDraft = isSermon && (!isMobile || mobilePanel == 'draft');
          const handleWidth = 16.0;
          final resultWidth = isSermon && !isMobile ? (box.maxWidth - handleWidth) * leftPct / 100 : box.maxWidth;
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (showResult) SizedBox(width: isSermon && !isMobile ? resultWidth : box.maxWidth, child: _resultPanel(c)),
            if (isSermon && !isMobile) _splitHandle(c, box.maxWidth - handleWidth),
            if (showDraft) Expanded(child: _draftPanel(c)),
          ]);
        }),
      ),
    ]);
  }

  Widget _stepBar(AppColors c) {
    final cell = matchedCell();
    return Container(
      decoration: BoxDecoration(color: c.bgSidebar, border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              for (var i = 0; i < steps.length; i++) ...[
                StepTab(
                  step: steps[i],
                  active: steps[i].index == currentStep,
                  hasContent: (item.steps[tab == 'sermon' ? steps[i].index : 0] ?? '').isNotEmpty,
                  lang: lang,
                  onTap: () => selectStep(steps[i].index),
                ),
                if (i < steps.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Opacity(opacity: 0.4, child: Text('›', style: TextStyle(fontSize: 18, color: c.textMuted))),
                  ),
              ],
            ]),
          ),
        ),
        if (cell != null)
          Tooltip(
            message: en ? 'A cell material with the same passage exists. Click to go.' : '같은 본문의 나눔 교재가 있습니다. 클릭하면 이동합니다.',
            child: InkWell(
              onTap: () => widget.onGoToCell(cell),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: c.border))),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: c.accentLight, border: Border.all(color: c.accent), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(en ? 'Cell' : '교재', style: TextStyle(fontSize: 11, color: c.accent, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: Text((cell.title?.isNotEmpty == true ? cell.title : cell.passage) ?? '',
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
            SmallButton(
              label: en ? 'Info ${infoOpen ? '▲' : '▼'}' : '기본정보 ${infoOpen ? '▲' : '▼'}',
              active: infoOpen,
              onPressed: () => setState(() => infoOpen = !infoOpen),
            ),
            const SizedBox(height: 4),
            SmallButton(
              label: manualSaved ? (en ? 'Saved' : '저장됨') : (en ? 'Save' : '저장'),
              active: manualSaved,
              onPressed: handleManualSave,
            ),
            const SizedBox(height: 4),
            Tooltip(
              message: en ? 'Export this item as .json (for AirDrop / sharing)' : '이 항목을 .json 파일로 내보내기 (에어드롭·공유용)',
              child: SmallButton(label: en ? 'Export' : '내보내기', onPressed: exportItem),
            ),
          ])),
        ),
      ]),
    );
  }

  Widget _resultPanel(AppColors c) {
    return TapRegion(
      // 결과창 바깥을 누르면 편집 끝 (웹 mousedown 바깥 감지)
      onTapOutside: (_) => finishEdit(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            if (hasItems)
              SmallButton(
                label: '${en ? 'Instructions' : '지시 항목'} ${displaySelected.length + displayCustomSelected.length}/${currentItems.length + customItems.length}',
                active: instructionsOpen,
                onPressed: () => setState(() => instructionsOpen = !instructionsOpen),
              ),
            const Spacer(),
            if (content.isNotEmpty && !loading) ...[
              FontSizeButtons(fontSize: widget.fontSize, onChange: widget.onFontSizeChange, height: 28, fontSize11: false),
              const SizedBox(width: 8),
            ],
            AccentButton(
              loading
                  ? (ko ? '중지' : 'Stop')
                  : (content.isNotEmpty ? (ko ? '다시 생성' : 'Regenerate') : (ko ? 'AI 생성' : 'Generate')),
              fontSize: 13,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: loading ? AppColors.danger : null,
              onPressed: loading ? stopCurrentGeneration : generate,
            ),
          ]),
        ),
        if (!editing && instructionsOpen && hasItems)
          InstructionsPanel(
            items: currentItems,
            selected: displaySelected,
            onToggle: toggleItem,
            customItems: customItems,
            customSelected: displayCustomSelected,
            onToggleCustom: toggleCustomItem,
            onAddCustom: addCustomItem,
            onDeleteCustom: deleteCustomItem,
            onReorderCustom: (ids) => store.setCustomItemOrders(ids),
            keywordCtrl: keywordCtrl,
            lang: lang,
          ),
        Expanded(child: _resultBody(c)),
        if (tab == 'sermon' && content.isNotEmpty && !loading)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            child: TextButton(
              onPressed: applyToSermon,
              style: TextButton.styleFrom(
                backgroundColor: c.accentLight,
                foregroundColor: c.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide(color: c.accent)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text(ko ? '설교문에 반영' : 'Add to Sermon'),
            ),
          ),
      ]),
    );
  }

  Widget _resultBody(AppColors c) {
    if (editing) {
      return RichView(
        key: const ValueKey('result-edit'),
        source: resultHistory.text,
        fontSize: widget.fontSize,
        editable: true,
        autoFocus: true,
        showToolbar: true,
        onChanged: onResultEdited,
        onEnterCommand: handleStepSlashCommand,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null)
        Container(
          margin: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            border: Border.all(color: const Color(0xFFFECACA)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ),
      Expanded(
        child: content.isNotEmpty
            ? TapToEdit(
                enabled: !loading,
                onTap: startEdit,
                child: RichView(
                  key: const ValueKey('result-view'),
                  source: content,
                  fontSize: widget.fontSize,
                  streaming: loading,
                  onSelectedText: (t) => lastSelection = t,
                  selectionEdit: loading || refining ? null : selectionEdit(applyResultEdit),
                ),
              )
            : (loading
                ? const SizedBox()
                : Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Text(ko ? 'AI 생성 버튼을 눌러 내용을 생성하세요' : 'Click Generate to create content',
                        textAlign: TextAlign.center, style: TextStyle(color: c.textMuted, fontSize: 13)),
                  )),
      ),
    ]);
  }

  Widget _splitHandle(AppColors c, double totalWidth) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: stepPanelVisible
          ? (d) => setState(() => leftPct = (leftPct + d.delta.dx / totalWidth * 100).clamp(20, 80))
          : null,
      child: MouseRegion(
        cursor: stepPanelVisible ? SystemMouseCursors.resizeColumn : SystemMouseCursors.basic,
        child: Container(
          width: 16,
          decoration: BoxDecoration(
            color: c.bgSidebar,
            border: Border(left: BorderSide(color: c.border), right: BorderSide(color: c.border)),
          ),
          alignment: Alignment.center,
          child: Tooltip(
            message: en ? (stepPanelVisible ? 'Hide step panel' : 'Show step panel') : (stepPanelVisible ? '단계 패널 감추기' : '단계 패널 보이기'),
            child: InkWell(
              onTap: () => setState(() => stepPanelVisible = !stepPanelVisible),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                // 웹의 ◀ / ▶ (글꼴에 없는 기호라 아이콘으로)
                child: Icon(stepPanelVisible ? Icons.arrow_left : Icons.arrow_right, size: 16, color: c.textMuted),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _draftPanel(AppColors c) {
    final draftHasContent = stripHtml(draftHistory.text).trim().isNotEmpty;
    return TapRegion(
      onTapOutside: (_) {
        if (draftEditing) setState(() => draftEditing = false);
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            Text((ko ? '설교문 초안' : 'Sermon Draft').toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: c.textMuted)),
            const SizedBox(width: 18),
            Expanded(
              child: TextField(
                controller: keywordCtrl,
                style: TextStyle(fontSize: 12, color: c.text),
                decoration: appInputDecoration(context, hint: ko ? '키워드 지시어 (예: 청년 대상)' : 'Keyword directive',
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
              ),
            ),
            const SizedBox(width: 18),
            Opacity(
              opacity: draftHasContent ? 1 : 0.4,
              child: TextButton(
                onPressed: (refining || loading || !draftHasContent) ? null : refineSermonDraft,
                style: TextButton.styleFrom(
                  backgroundColor: refining ? c.border : c.accentLight,
                  foregroundColor: refining ? c.textMuted : c.accent,
                  disabledForegroundColor: refining ? c.textMuted : c.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5), side: BorderSide(color: refining ? c.border : c.accent)),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
                child: Text(refining ? (ko ? '다듬는 중...' : 'Refining...') : (ko ? 'AI 다듬기' : 'AI Refine')),
              ),
            ),
            const SizedBox(width: 8),
            FontSizeButtons(fontSize: widget.fontSize, onChange: widget.onFontSizeChange, height: 24, fontSize11: true),
            const SizedBox(width: 8),
            UndoButton(icon: Icons.undo, enabled: draftHistory.canUndo, onPressed: draftHistory.undo),
            const SizedBox(width: 8),
            UndoButton(icon: Icons.redo, enabled: draftHistory.canRedo, onPressed: draftHistory.redo),
          ]),
        ),
        Expanded(
          child: draftEditing
              ? RichView(
                  key: const ValueKey('draft-edit'),
                  source: draftHistory.text,
                  fontSize: widget.fontSize,
                  editable: true,
                  autoFocus: true,
                  showToolbar: true,
                  onChanged: handleDraftChange,
                  onEnterCommand: handleDraftSlashCommand,
                )
              : draftHistory.text.isNotEmpty
                  ? TapToEdit(
                      enabled: true,
                      onTap: () => setState(() => draftEditing = true),
                      child: RichView(
                        key: const ValueKey('draft-view'),
                        source: draftHistory.text,
                        fontSize: widget.fontSize,
                        streaming: refining,
                        selectionEdit: loading || refining ? null : selectionEdit(applyDraftEdit),
                      ),
                    )
                  : InkWell(
                      onTap: () => setState(() => draftEditing = true),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 60),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Text(ko ? '클릭하여 설교문 초안을 작성하세요' : 'Click to start writing',
                              style: TextStyle(color: c.textMuted, fontSize: 13)),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}
