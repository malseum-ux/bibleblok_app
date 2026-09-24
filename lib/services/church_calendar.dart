// 교회력 절기 계산 — 웹 WorshipForm.jsx 의 getEaster / getChurchSeason / getSeasonColor 와 같은 규칙
import 'package:flutter/material.dart';

const _dayMs = 86400000;

// 요일: 0 = 주일 (자바스크립트 getDay 와 같게)
int _dow(DateTime d) => d.weekday % 7;

// 부활절 날짜 계산 (Anonymous Gregorian algorithm)
DateTime getEaster(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String getChurchSeason(String? dateStr) {
  if (dateStr == null || dateStr.isEmpty) return '';
  final date = DateTime.tryParse(dateStr);
  if (date == null) return '';
  final year = date.year;
  final month = date.month;
  final day = date.day;

  final easter = getEaster(year);
  final easterMs = easter.millisecondsSinceEpoch;
  final dateMs = date.millisecondsSinceEpoch;

  final ashWed = DateTime.fromMillisecondsSinceEpoch(easterMs - 46 * _dayMs);
  final palmSunday = DateTime.fromMillisecondsSinceEpoch(easterMs - 7 * _dayMs);
  final pentecost = DateTime.fromMillisecondsSinceEpoch(easterMs + 49 * _dayMs);

  final christmas = DateTime(year, 12, 25);
  final christmasDow = _dow(christmas);
  final daysToAdvent = christmasDow == 0 ? 28 : christmasDow + 21;
  final advent = DateTime.fromMillisecondsSinceEpoch(christmas.millisecondsSinceEpoch - daysToAdvent * _dayMs);

  // 고정 날짜
  if (month == 12 && day == 25) return '성탄절';
  if (month == 12 && day == 24) return '성탄전야';
  if (month == 1 && day == 1) return '신년주일';
  if (month == 1 && day == 6) return '주현절';

  // 대림절 (성탄절 전 넷째 주일 ~ 성탄전야)
  if (dateMs >= advent.millisecondsSinceEpoch && (month < 12 || day < 24)) return '대림절';

  // 성탄절 기간 (성탄절 이튿날 ~ 주현절 전날)
  if ((month == 12 && day > 25) || (month == 1 && day <= 5)) return '성탄절';

  // 추수감사주일: 11월 셋째 주일
  if (month == 11) {
    final nov1 = DateTime(year, 11, 1);
    final firstSunday = (7 - _dow(nov1)) % 7;
    final thirdSundayDay = firstSunday + 14 + 1;
    if (day >= thirdSundayDay && day < thirdSundayDay + 7 && _dow(date) == 0) return '추수감사주일';
  }

  // 종교개혁주일: 10월 31일에 가장 가까운 주일 (11월 초에 걸릴 수 있음)
  final oct31 = DateTime(year, 10, 31);
  final oct31dow = _dow(oct31);
  final reformSunday = oct31dow <= 3
      ? DateTime.fromMillisecondsSinceEpoch(oct31.millisecondsSinceEpoch - oct31dow * _dayMs)
      : DateTime.fromMillisecondsSinceEpoch(oct31.millisecondsSinceEpoch + (7 - oct31dow) * _dayMs);
  if (_sameDay(date, reformSunday)) return '종교개혁주일';

  // 성령강림주일 (오순절 당일)
  if (_sameDay(date, pentecost)) return '성령강림주일';

  // 주현절 기간: 1/7 ~ 재의 수요일 전날
  final jan7 = DateTime(year, 1, 7);
  if (dateMs >= jan7.millisecondsSinceEpoch && dateMs < ashWed.millisecondsSinceEpoch) return '주현절';

  // 사순절: 재의 수요일 ~ 종려주일 전날
  if (dateMs >= ashWed.millisecondsSinceEpoch && dateMs < palmSunday.millisecondsSinceEpoch) return '사순절';

  // 성주간: 종려주일 ~ 부활절 전날
  if (dateMs >= palmSunday.millisecondsSinceEpoch && dateMs < easterMs) return '성주간';

  // 부활절: 부활절 ~ 오순절 전날
  if (dateMs >= easterMs && dateMs < pentecost.millisecondsSinceEpoch) return '부활절';

  // 오순절 이후: 삼위일체 주일 / 오순절 후 N번째 주일
  if (dateMs > pentecost.millisecondsSinceEpoch) {
    final thisSunday = dateMs - _dow(date) * _dayMs;
    final weeks = ((thisSunday - pentecost.millisecondsSinceEpoch) / (7 * _dayMs)).round();
    if (weeks == 0) return '성령강림절';
    if (weeks == 1) return '삼위일체 주일';
    return '오순절 후 $weeks번째 주일';
  }

  return '일반 주일';
}

class SeasonColor {
  final String label;
  final Color color;
  const SeasonColor(this.label, this.color);
}

const _green = SeasonColor('초록', Color(0xFF16A34A));
const _purple = SeasonColor('보라', Color(0xFF7C3AED));
const _white = SeasonColor('흰색', Color(0xFFD97706));
const _red = SeasonColor('빨강', Color(0xFFDC2626));
const _crimson = SeasonColor('자주', Color(0xFF9F1239));

SeasonColor? getSeasonColor(String? season) {
  if (season == null) return null;
  if (season.startsWith('오순절 후')) return _green;
  return const {
    '대림절': _purple,
    '성탄절': _white,
    '성탄전야': _white,
    '신년주일': _white,
    '주현절': _green,
    '사순절': _purple,
    '성주간': _crimson,
    '부활절': _white,
    '성령강림주일': _red,
    '성령강림절': _green,
    '삼위일체 주일': _white,
    '추수감사주일': _green,
    '종교개혁주일': _red,
    '일반 주일': _green,
  }[season];
}
