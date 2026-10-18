// 연간 설교 계획 — 한 해의 주일을 줄지어 보여 주고, 그날의 설교·진행 상태·교회력 절기를 표시한다
// 따로 저장하는 것은 없다: 이미 있는 설교의 날짜로 채운다 (웹 components/PlanView.jsx 와 같은 화면)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../models/item.dart';
import '../services/church_calendar.dart';
import '../services/rich_doc.dart';
import '../services/store.dart';
import '../theme/app_colors.dart';

String _pad(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

/// 그해의 모든 주일
List<DateTime> sundaysOf(int year) {
  var d = DateTime(year, 1, 1);
  d = d.add(Duration(days: (7 - d.weekday % 7) % 7));
  final out = <DateTime>[];
  while (d.year == year) {
    out.add(d);
    d = DateTime(d.year, d.month, d.day + 7);
  }
  return out;
}

class PlanView extends StatefulWidget {
  final Store store;
  final String lang;
  final void Function(String tab, String id) onOpen;
  final void Function(String date) onCreate;
  const PlanView({super.key, required this.store, required this.lang, required this.onOpen, required this.onCreate});

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  static const _dawnKey = 'bibleblok-plan-dawn';
  int year = DateTime.now().year;
  bool showDawn = false;
  final _currentKey = GlobalKey();

  bool get ko => widget.lang != 'en';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => showDawn = p.getBool(_dawnKey) ?? false);
    });
    _scrollToCurrent();
  }

  void _scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _currentKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.4);
    });
  }

  void _setDawn(bool v) {
    setState(() => showDawn = v);
    SharedPreferences.getInstance().then((p) => p.setBool(_dawnKey, v));
  }

  Map<String, List<Item>> _byDate(List<Item> list) {
    final m = <String, List<Item>>{};
    for (final it in list) {
      final d = it.date;
      if (d != null && d.isNotEmpty) (m[d] ??= []).add(it);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = _ymd(DateTime.now());
    final sermons = _byDate(widget.store.items['sermon']!);
    final dawns = _byDate(widget.store.items['dawn']!);
    final worshipDates = widget.store.items['worship']!.map((w) => w.date).whereType<String>().toSet();
    final total = stepsForTab('sermon').length;

    Widget chip(String text, {Color? bg, Color? fg, Color? border, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: border != null ? Border.all(color: border) : null,
            ),
            child: Text(text, style: TextStyle(fontSize: 11, color: fg ?? c.textMuted)),
          ),
        );

    Widget navBtn(String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: TextStyle(color: c.textMuted)),
          ),
        );

    final weeks = <Widget>[];
    for (final sun in sundaysOf(year)) {
      final date = _ymd(sun);
      final weekEnd = _ymd(DateTime(sun.year, sun.month, sun.day + 6));
      final isCurrent = today.compareTo(date) >= 0 && today.compareTo(weekEnd) <= 0;
      final season = getChurchSeason(date);
      final color = getSeasonColor(season);
      final list = sermons[date] ?? const <Item>[];
      final weekDawns = showDawn
          ? [for (var i = 0; i < 7; i++) ...?dawns[_ymd(DateTime(sun.year, sun.month, sun.day + i))]]
          : const <Item>[];

      weeks.add(Container(
        key: isCurrent ? _currentKey : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent ? c.accentLight : null,
          borderRadius: isCurrent ? BorderRadius.circular(8) : null,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 92,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${sun.month}/${sun.day}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.textHeading)),
              const SizedBox(height: 3),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (color != null)
                  Container(
                    margin: const EdgeInsets.only(top: 3, right: 5),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
                  ),
                Expanded(child: Text(season, style: TextStyle(fontSize: 11, height: 1.3, color: c.textMuted))),
              ]),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => widget.onOpen('sermon', s.id),
                    child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(
                        (s.title?.isNotEmpty == true ? s.title : null) ?? (s.passage?.isNotEmpty == true ? s.passage : null) ?? (ko ? '제목 없음' : 'Untitled'),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text),
                      ),
                      if (s.title?.isNotEmpty == true && s.passage?.isNotEmpty == true)
                        Text(s.passage!, style: TextStyle(fontSize: 12, color: c.textMuted)),
                      if (s.category?.isNotEmpty == true) chip(s.category!, bg: c.bgSidebar, border: c.border),
                      Builder(builder: (_) {
                        final done = s.steps.values.where((v) => stripHtml(v).trim().isNotEmpty).length;
                        final full = done >= total;
                        return chip(ko ? '연구 $done/$total' : 'Research $done/$total',
                            bg: full ? c.accent : null, fg: full ? Colors.white : c.accent, border: c.accent);
                      }),
                      if (stripHtml(s.draft).trim().isNotEmpty)
                        chip(ko ? '초안' : 'Draft', bg: AppColors.success.withValues(alpha: 0.13), fg: AppColors.success),
                    ]),
                  ),
                ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: OutlinedButton(
                    onPressed: () => widget.onCreate(date),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textMuted,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(ko ? '+ 새 설교' : '+ New sermon'),
                  ),
                ),
              if (worshipDates.contains(date))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(ko ? '예배인도 있음' : 'Worship guide ready', style: TextStyle(fontSize: 11, color: c.textMuted)),
                ),
              if (weekDawns.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final d in weekDawns)
                    chip(
                      '${ko ? '새벽' : 'Dawn'} ${d.date!.substring(5).replaceAll('-', '/')} · ${(d.title?.isNotEmpty == true ? d.title : null) ?? (d.passage?.isNotEmpty == true ? d.passage : null) ?? (ko ? '제목 없음' : 'Untitled')}',
                      bg: c.bgSidebar,
                      fg: c.text,
                      border: c.border,
                      onTap: () => widget.onOpen('dawn', d.id),
                    ),
                ]),
            ]),
          ),
        ]),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          navBtn('‹', () {
            setState(() => year--);
            _scrollToCurrent();
          }),
          SizedBox(
            width: 72,
            child: Text(ko ? '$year년' : '$year',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.textHeading)),
          ),
          navBtn('›', () {
            setState(() => year++);
            _scrollToCurrent();
          }),
          const Spacer(),
          InkWell(
            onTap: () => _setDawn(!showDawn),
            child: Row(children: [
              SizedBox(width: 22, height: 22, child: Checkbox(value: showDawn, onChanged: (v) => _setDawn(v ?? false), activeColor: c.accent)),
              const SizedBox(width: 6),
              Text(ko ? '새벽설교 함께 보기' : 'Show dawn sermons', style: TextStyle(fontSize: 13, color: c.text)),
            ]),
          ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: weeks),
        ),
      ),
    ]);
  }
}
