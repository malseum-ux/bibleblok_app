// 기본정보 입력 양식 — 웹 SermonForm / DawnForm / WorshipForm / CellForm 과 같은 배치
import 'package:flutter/material.dart';

import '../services/ai.dart';
import '../services/church_calendar.dart';
import '../theme/app_colors.dart';
import 'ui.dart';

typedef FormSave = Future<void> Function(Map<String, String?> data);

// ── 설교 · 새벽 (같은 배치, 제목 안내 문구만 다름) ───────────────────────────────

class SermonDawnForm extends StatefulWidget {
  final bool isDawn;
  final Map<String, String?>? initial;
  final String lang;
  final String? defaultCategory;
  final FormSave onSave;
  const SermonDawnForm({super.key, required this.isDawn, this.initial, required this.lang, this.defaultCategory, required this.onSave});

  @override
  State<SermonDawnForm> createState() => _SermonDawnFormState();
}

class _SermonDawnFormState extends State<SermonDawnForm> {
  late String? date = widget.initial?['date'] ?? todayString();
  late final category = TextEditingController(text: widget.initial?['category'] ?? widget.defaultCategory ?? '');
  late final title = TextEditingController(text: widget.initial?['title'] ?? '');
  late final passage = TextEditingController(text: widget.initial?['passage'] ?? '');
  late final emphasis = TextEditingController(text: widget.initial?['emphasis'] ?? '');

  @override
  Widget build(BuildContext context) {
    final ko = widget.lang == 'ko';
    final en = widget.lang == 'en';
    Widget col(String label, Widget field) =>
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [FieldLabel(label), field]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        col(ko ? '날짜' : 'Date', DateField(value: date, onChanged: (v) => setState(() => date = v))),
        const SizedBox(width: 12),
        col(ko ? '구분' : 'Category', AppInput(controller: category, hint: ko ? '강해, 주제, 시리즈명 등' : 'Expository, Topical, Series...')),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        col(
          widget.isDawn ? (ko ? '제목' : 'Title') : (ko ? '설교 제목' : 'Title'),
          AppInput(controller: title, hint: widget.isDawn ? (ko ? '새벽 기도 제목' : 'Title') : (ko ? '설교 제목' : 'Sermon title')),
        ),
        const SizedBox(width: 12),
        col(
          ko ? '본문' : 'Passage',
          AppInput(
            controller: passage,
            hint: widget.isDawn ? (en ? 'e.g. Gen 1:1-5' : '예: 창세기 1:1-5') : (en ? 'e.g. Gen 1:1-10' : '예: 창세기 1:1-10'),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      FieldLabel(ko ? '키워드' : 'Keywords'),
      Row(children: [
        Expanded(child: AppInput(controller: emphasis, hint: ko ? '강조할 단어나 문구 (선택)' : 'Word or phrase to emphasize (optional)')),
        const SizedBox(width: 8),
        AccentButton(
          ko ? '저장' : 'Save',
          height: 38,
          onPressed: () => widget.onSave({
            'date': date,
            'category': category.text,
            'title': title.text,
            'passage': passage.text,
            'emphasis': emphasis.text,
          }),
        ),
      ]),
    ]);
  }
}

// ── 예배인도 ─────────────────────────────────────────────────────────────────

class WorshipForm extends StatefulWidget {
  final Map<String, String?>? initial;
  final String lang;
  final String bible;
  final FormSave onSave;
  const WorshipForm({super.key, this.initial, required this.lang, required this.bible, required this.onSave});

  @override
  State<WorshipForm> createState() => _WorshipFormState();
}

class _WorshipFormState extends State<WorshipForm> {
  late String date = widget.initial?['date'] ?? todayString();
  late String season = widget.initial?['season'] ?? getChurchSeason(date);
  late final lectionary = TextEditingController(text: widget.initial?['lectionary'] ?? '');
  bool loadingLectionary = false;

  Future<void> autoFill() async {
    setState(() => loadingLectionary = true);
    try {
      final result = await fetchLectionary(date, season, widget.lang, widget.bible);
      lectionary.text = result;
    } catch (e) {
      if (mounted) showAlert(context, '${widget.lang == 'ko' ? '성서정과 조회 실패: ' : 'Lectionary lookup failed: '}$e');
    } finally {
      if (mounted) setState(() => loadingLectionary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ko = widget.lang == 'ko';
    final color = getSeasonColor(season);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FieldLabel(ko ? '날짜' : 'Date'),
            DateField(
              value: date,
              onChanged: (v) => setState(() {
                date = v ?? todayString();
                season = getChurchSeason(date);
              }),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FieldLabel(ko ? '교회력 절기' : 'Church Season'),
            InputDecorator(
              decoration: appInputDecoration(context, fill: c.bgSidebar),
              child: Row(children: [
                Flexible(
                  child: Text(
                    season.isNotEmpty ? season : (ko ? '날짜 선택 시 자동 입력' : 'Auto-filled'),
                    style: TextStyle(fontSize: 14, color: c.accent, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (color != null) ...[
                  const SizedBox(width: 6),
                  Text('(${color.label})', style: TextStyle(fontSize: 13, color: color.color, fontWeight: FontWeight.w500)),
                ],
              ]),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      FieldLabel(ko ? '성서정과 본문' : 'Lectionary'),
      Row(children: [
        Expanded(child: AppInput(controller: lectionary, hint: ko ? '예: 사 40:1-11 | 시 85 | 막 1:1-8' : 'E.g. Isa 40:1-11 | Ps 85 | Mark 1:1-8')),
        const SizedBox(width: 8),
        Tooltip(
          message: ko ? 'AI로 성서정과 조회' : 'Auto-fill lectionary',
          child: AccentButton(
            loadingLectionary ? (ko ? '조회 중...' : 'Loading...') : (ko ? 'AI 조회' : 'AI Fill'),
            height: 38,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: loadingLectionary ? null : autoFill,
          ),
        ),
        const SizedBox(width: 48), // 웹: 간격 8 + 빈 칸 32 + 간격 8
        AccentButton(
          ko ? '저장' : 'Save',
          height: 38,
          fontSize: 13,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          onPressed: () => widget.onSave({'date': date, 'season': season, 'lectionary': lectionary.text}),
        ),
      ]),
    ]);
  }
}

// ── 교재 ─────────────────────────────────────────────────────────────────────

class CellForm extends StatefulWidget {
  final Map<String, String?>? initial;
  final bool isEdit;
  final String lang;
  final FormSave onSave;
  const CellForm({super.key, this.initial, this.isEdit = false, required this.lang, required this.onSave});

  @override
  State<CellForm> createState() => _CellFormState();
}

class _CellFormState extends State<CellForm> {
  late final passage = TextEditingController(text: widget.initial?['passage'] ?? '');
  late final title = TextEditingController(text: widget.initial?['title'] ?? '');
  late String? date = widget.initial?['date'];

  void submit() {
    if (passage.text.trim().isEmpty) return;
    widget.onSave({
      'passage': passage.text.trim(),
      'title': title.text.trim().isEmpty ? null : title.text.trim(),
      'date': (date == null || date!.isEmpty) ? null : date,
    });
  }

  @override
  Widget build(BuildContext context) {
    final ko = widget.lang == 'ko';
    final en = widget.lang == 'en';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FieldLabel(ko ? '성경 본문 (필수)' : 'Passage (required)', upper: false),
        AppInput(controller: passage, fontSize: 13, hint: en ? 'e.g. John 8:1-11' : '예: 요한복음 8:1-11', onSubmitted: (_) => submit()),
        const SizedBox(height: 14),
        FieldLabel(ko ? '제목 (선택)' : 'Title (optional)', upper: false),
        AppInput(controller: title, fontSize: 13, hint: en ? 'Cell material title' : '나눔 교재 제목', onSubmitted: (_) => submit()),
        const SizedBox(height: 14),
        FieldLabel(ko ? '날짜 (선택)' : 'Date (optional)', upper: false),
        DateField(value: date, fontSize: 13, allowClear: true, onChanged: (v) => setState(() => date = v)),
        const SizedBox(height: 14),
        AccentButton(
          widget.isEdit ? (ko ? '저장' : 'Save') : (ko ? '교재 만들기' : 'Create'),
          fontSize: 13,
          onPressed: submit,
        ),
      ]),
    );
  }
}
