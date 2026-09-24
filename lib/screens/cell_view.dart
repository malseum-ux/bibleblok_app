// 교재 화면 — 웹 CellView.jsx (2단계에서 전체 구현)
import 'package:flutter/material.dart';

import '../models/item.dart';
import 'step_view.dart' show PendingView;

class CellView extends StatelessWidget {
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
  Widget build(BuildContext context) => PendingView(item: item, lang: lang);
}
