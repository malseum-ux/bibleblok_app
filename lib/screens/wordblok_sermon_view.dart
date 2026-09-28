// 성경나침반 내설교 한 편 보기 (읽기 전용) — 설교문 초안 칸과 같은 모양
// 웹 WordblokSermonView.jsx 와 같은 구성
import 'package:flutter/material.dart';

import '../services/wordblok_sermons.dart';
import '../theme/app_colors.dart';

class WordblokSermonView extends StatefulWidget {
  final WordblokItem item;
  final String file;
  final String lang;
  final double fontSize;
  const WordblokSermonView({super.key, required this.item, required this.file, this.lang = 'ko', this.fontSize = 14});

  @override
  State<WordblokSermonView> createState() => _WordblokSermonViewState();
}

class _WordblokSermonViewState extends State<WordblokSermonView> {
  String? text; // null = 불러오는 중

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
  Widget build(BuildContext context) {
    final c = context.c;
    final ko = widget.lang == 'ko';
    final item = widget.item;
    final meta = [item.date, passageLabel(item.book, item.chapter, item.verse), widget.file].where((s) => s.isNotEmpty).join(' · ');

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
              child: Text(ko ? '· 성경나침반 내설교 (읽기 전용)' : '· WordBlok sermon (read only)',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: c.textMuted)),
            ),
          ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(item.title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.textHeading)),
            const SizedBox(height: 6),
            if (meta.isNotEmpty) ...[
              Text(meta, style: TextStyle(fontSize: 12, color: c.textMuted)),
              const SizedBox(height: 20),
            ],
            if (text == null)
              Text(ko ? '불러오는 중...' : 'Loading...', style: TextStyle(fontSize: 13, color: c.textMuted))
            else
              SelectableText(
                text!.isNotEmpty ? text! : (ko ? '내용이 없습니다' : 'No content'),
                style: TextStyle(fontSize: widget.fontSize, height: 1.8, color: c.text),
              ),
          ]),
        ),
      ),
    ]);
  }
}
