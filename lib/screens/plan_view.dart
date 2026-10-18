// 설교 계획 — 일반 달력(일~토 7칸). 주일 칸에 교회력 절기·설교·진행 상태, 켜면 평일 칸에 새벽설교
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
const _red = Color(0xFFDC2626);

/// 달력에 보일 날짜들 — 그달 1일이 든 주의 일요일부터, 말일이 든 주의 토요일까지
List<DateTime> calendarDays(int year, int month) {
  final first = DateTime(year, month, 1);
  final last = DateTime(year, month + 1, 0);
  final start = DateTime(year, month, 1 - first.weekday % 7);
  final count = (last.day + first.weekday % 7 + (6 - last.weekday % 7));
  return [for (var i = 0; i < count; i++) DateTime(start.year, start.month, start.day + i)];
}

class PlanView extends StatefulWidget {
  final Store store;
  final String lang;
  final bool isMobile;
  final void Function(String tab, String id) onOpen;
  final void Function(String date, String kind) onCreate;
  const PlanView({
    super.key,
    required this.store,
    required this.lang,
    required this.onOpen,
    required this.onCreate,
    this.isMobile = false,
  });

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  static const _dawnKey = 'bibleblok-plan-dawn';
  late int year;
  late int month;
  late String picked; // 휴대폰 폭: 누른 날짜
  bool showDawn = false;

  bool get ko => widget.lang != 'en';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    year = now.year;
    month = now.month;
    picked = _ymd(now);
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => showDawn = p.getBool(_dawnKey) ?? false);
    });
  }

  void _setDawn(bool v) {
    setState(() => showDawn = v);
    SharedPreferences.getInstance().then((p) => p.setBool(_dawnKey, v));
  }

  void _move(int n) => setState(() {
        final d = DateTime(year, month + n, 1);
        year = d.year;
        month = d.month;
      });

  void _goToday() => setState(() {
        final now = DateTime.now();
        year = now.year;
        month = now.month;
        picked = _ymd(now);
      });

  Map<String, List<Item>> _byDate(List<Item> list) {
    final m = <String, List<Item>>{};
    for (final it in list) {
      final d = it.date;
      if (d != null && d.isNotEmpty) (m[d] ??= []).add(it);
    }
    return m;
  }

  String _titleOf(Item it) =>
      (it.title?.isNotEmpty == true ? it.title : null) ??
      (it.passage?.isNotEmpty == true ? it.passage : null) ??
      (ko ? '제목 없음' : 'Untitled');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isMobile = widget.isMobile;
    final today = _ymd(DateTime.now());
    final sermons = _byDate(widget.store.items['sermon']!);
    final dawns = _byDate(widget.store.items['dawn']!);
    final worshipDates = widget.store.items['worship']!.map((w) => w.date).whereType<String>().toSet();
    final total = stepsForTab('sermon').length;
    final dayNames = ko ? ['일', '월', '화', '수', '목', '금', '토'] : ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final days = calendarDays(year, month);
    final rows = days.length ~/ 7;

    Widget chip(String text, {Color? bg, Color? fg, Color? border}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            border: border != null ? Border.all(color: border) : null,
          ),
          child: Text(text, style: TextStyle(fontSize: 10, height: 1.5, color: fg ?? c.textMuted)),
        );

    Widget addBtn(String label, VoidCallback onTap) => Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(5)),
              child: Text(label, style: TextStyle(fontSize: 11, color: c.textMuted)),
            ),
          ),
        );

    Widget navBtn(String label, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(6)),
            child: Text(label, style: TextStyle(fontSize: 13, color: c.textMuted)),
          ),
        );

    // 한 날짜의 내용 (큰 칸 안, 또는 휴대폰 아래 펼침)
    Widget dayContent(String date, bool isSunday, {bool compact = false}) {
      final list = sermons[date] ?? const <Item>[];
      final dayDawns = showDawn ? (dawns[date] ?? const <Item>[]) : const <Item>[];
      final one = TextOverflow.ellipsis;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () => widget.onOpen('sermon', s.id),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_titleOf(s),
                    maxLines: 1,
                    overflow: one,
                    style: TextStyle(fontSize: compact ? 14 : 13, fontWeight: FontWeight.w600, color: c.text)),
                if (s.title?.isNotEmpty == true && s.passage?.isNotEmpty == true)
                  Text(s.passage!, maxLines: 1, overflow: one, style: TextStyle(fontSize: 11, color: c.textMuted)),
                const SizedBox(height: 2),
                Wrap(spacing: 4, runSpacing: 3, children: [
                  Builder(builder: (_) {
                    final done = s.steps.values.where((v) => stripHtml(v).trim().isNotEmpty).length;
                    final full = done >= total;
                    return chip(ko ? '연구 $done/$total' : '$done/$total',
                        bg: full ? c.accent : null, fg: full ? Colors.white : c.accent, border: c.accent);
                  }),
                  if (stripHtml(s.draft).trim().isNotEmpty)
                    chip(ko ? '초안' : 'Draft', bg: AppColors.success.withValues(alpha: 0.13), fg: AppColors.success),
                  if (s.category?.isNotEmpty == true) chip(s.category!, bg: c.bgSidebar, border: c.border),
                ]),
              ]),
            ),
          ),
        if (isSunday && list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: addBtn(ko ? '+ 새 설교' : '+ Sermon', () => widget.onCreate(date, 'sermon')),
          ),
        if (worshipDates.contains(date))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(ko ? '예배인도 있음' : 'Worship ready', style: TextStyle(fontSize: 10, color: c.textMuted)),
          ),
        for (final d in dayDawns)
          InkWell(
            onTap: () => widget.onOpen('dawn', d.id),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: ko ? '새벽 · ' : 'Dawn · ', style: TextStyle(color: c.textMuted)),
                  TextSpan(text: _titleOf(d)),
                ]),
                maxLines: 1,
                overflow: one,
                style: TextStyle(fontSize: compact ? 13 : 11, color: c.text),
              ),
            ),
          ),
        if (showDawn && !isSunday && dayDawns.isEmpty) addBtn(ko ? '+ 새벽' : '+ Dawn', () => widget.onCreate(date, 'dawn')),
      ]);
    }

    Widget dot(Color? fill, {Color? border}) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: border != null ? Border.all(color: border) : null,
          ),
        );

    Widget cell(DateTime d) {
      final date = _ymd(d);
      final inMonth = d.month == month;
      final isSunday = d.weekday == DateTime.sunday;
      final isToday = date == today;
      final season = isSunday ? getChurchSeason(date) : '';
      final color = isSunday ? getSeasonColor(season) : null;
      final hasSermon = sermons[date]?.isNotEmpty == true;
      final hasDawn = showDawn && dawns[date]?.isNotEmpty == true;
      final body = Container(
        padding: isMobile ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(8, 4, 8, 6),
        decoration: BoxDecoration(
          color: isMobile && picked == date
              ? c.accentLight
              : inMonth
                  ? null
                  : c.bgSidebar,
          border: Border(
            top: BorderSide(color: color?.color ?? Colors.transparent, width: 3),
            right: BorderSide(color: c.border),
            bottom: BorderSide(color: c.border),
          ),
        ),
        child: Opacity(
          opacity: inMonth ? 1 : 0.55,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: isToday ? 6 : 0),
                decoration: BoxDecoration(color: isToday ? c.accent : null, borderRadius: BorderRadius.circular(10)),
                child: Text('${d.day}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isToday
                          ? Colors.white
                          : isSunday
                              ? _red
                              : c.text,
                    )),
              ),
              if (!isMobile && season.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(season,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: color?.color ?? c.textMuted)),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            if (isMobile)
              Wrap(spacing: 3, runSpacing: 3, children: [
                if (hasSermon) dot(c.accent),
                if (hasDawn) dot(c.textMuted),
                if (worshipDates.contains(date)) dot(null, border: c.accent),
              ])
            else
              Expanded(child: SingleChildScrollView(child: dayContent(date, isSunday))),
          ]),
        ),
      );
      return isMobile ? GestureDetector(onTap: () => setState(() => picked = date), child: body) : body;
    }

    final grid = Column(children: [
      for (var r = 0; r < rows; r++)
        Builder(builder: (_) {
          final row = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < 7; i++) Expanded(child: cell(days[r * 7 + i])),
          ]);
          return isMobile ? SizedBox(height: 56, child: row) : Expanded(child: row);
        }),
    ]);

    Widget pickedPanel() {
      final d = DateTime.parse(picked);
      final isSunday = d.weekday == DateTime.sunday;
      final season = isSunday ? getChurchSeason(picked) : '';
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: ko ? '${d.month}월 ${d.day}일 (${dayNames[d.weekday % 7]})' : picked),
              if (season.isNotEmpty)
                TextSpan(
                  text: '  $season',
                  style: TextStyle(fontWeight: FontWeight.w400, fontSize: 12, color: getSeasonColor(season)?.color),
                ),
            ]),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.textHeading),
          ),
          const SizedBox(height: 8),
          dayContent(picked, isSunday, compact: true),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          navBtn('‹', () => _move(-1)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: isMobile ? 0 : 104),
            child: Text(ko ? '$year년 $month월' : '$year. $month',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: c.textHeading)),
          ),
          const SizedBox(width: 8),
          navBtn('›', () => _move(1)),
          const SizedBox(width: 8),
          navBtn(ko ? '오늘' : 'Today', _goToday),
          const Spacer(),
          InkWell(
            onTap: () => _setDawn(!showDawn),
            child: Row(children: [
              SizedBox(width: 22, height: 22, child: Checkbox(value: showDawn, onChanged: (v) => _setDawn(v ?? false), activeColor: c.accent)),
              const SizedBox(width: 6),
              Text(isMobile ? (ko ? '새벽' : 'Dawn') : (ko ? '새벽설교 함께 보기' : 'Dawn sermons'),
                  style: TextStyle(fontSize: 13, color: c.text)),
            ]),
          ),
        ]),
      ),
      Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
        child: Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(dayNames[i],
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: i == 0 ? _red : c.textMuted)),
              ),
            ),
        ]),
      ),
      if (isMobile) ...[
        grid,
        Container(height: 1, color: c.border),
        Expanded(child: pickedPanel()),
      ] else
        Expanded(child: grid),
    ]);
  }
}
