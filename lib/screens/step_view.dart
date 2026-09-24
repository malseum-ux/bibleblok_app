// 설교·예배·새벽 단계 화면 — 웹 StepView.jsx (2단계에서 전체 구현)
import 'package:flutter/material.dart';

import '../models/item.dart';
import '../theme/app_colors.dart';

class StepView extends StatelessWidget {
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
  Widget build(BuildContext context) => _Pending(item: item, lang: lang);
}

class _Pending extends StatelessWidget {
  final Item item;
  final String lang;
  const _Pending({super.key, required this.item, required this.lang});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.label(lang), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.textHeading)),
        const SizedBox(height: 8),
        Text(item.passage ?? '', style: TextStyle(color: c.text)),
        const SizedBox(height: 24),
        Text('단계 화면은 2단계에서 만듭니다.', style: TextStyle(color: c.textMuted, fontSize: 13)),
      ]),
    );
  }
}

class PendingView extends _Pending {
  const PendingView({super.key, required super.item, required super.lang});
}
