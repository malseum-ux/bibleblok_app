// 교회력 절기 — 웹(WorshipForm.jsx)과 같은 결과인지 2026~2027년 모든 날짜로 비교
import 'dart:convert';
import 'dart:io';

import 'package:bibleblok_app/services/church_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('웹과 같은 절기 계산 (2026~2027)', () {
    final expected = jsonDecode(File('test/season_expected.json').readAsStringSync()) as Map<String, dynamic>;
    final diffs = <String>[];
    expected.forEach((date, season) {
      final got = getChurchSeason(date);
      if (got != season) diffs.add('$date: 웹=$season 플러터=$got');
    });
    expect(diffs, isEmpty);
  });
}
