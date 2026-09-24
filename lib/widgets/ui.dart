// 여러 화면에서 같이 쓰는 입력칸·버튼·라벨 — 웹의 inline style 과 같은 크기·색
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 웹 labelStyle — 12px, 굵게, 흐린 색, 대문자, 자간 0.05em
class FieldLabel extends StatelessWidget {
  final String text;
  final bool upper;
  const FieldLabel(this.text, {super.key, this.upper = true});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          upper ? text.toUpperCase() : text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.c.textMuted, letterSpacing: 0.6),
        ),
      );
}

InputDecoration appInputDecoration(BuildContext context, {String? hint, EdgeInsets? padding, Color? fill}) {
  final c = context.c;
  OutlineInputBorder border(Color color) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: color));
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: c.textMuted),
    filled: true,
    fillColor: fill ?? c.bg,
    contentPadding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    border: border(c.border),
    enabledBorder: border(c.border),
    focusedBorder: border(c.border),
  );
}

/// 웹 inputStyle 입력칸
class AppInput extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final double fontSize;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final Color? textColor;
  const AppInput({
    super.key,
    required this.controller,
    this.hint,
    this.fontSize = 14,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: fontSize, color: textColor ?? context.c.textHeading),
        decoration: appInputDecoration(context, hint: hint),
      );
}

/// 강조색 버튼 (웹 background: var(--accent))
class AccentButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final double fontSize;
  final double? height;
  final Color? color; // 기본은 강조색 (예: 중지 버튼은 빨강)
  const AccentButton(this.label,
      {super.key, this.onPressed, this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 8), this.fontSize = 14, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onPressed != null;
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: enabled ? (color ?? c.accent) : c.border,
          foregroundColor: enabled ? Colors.white : c.textMuted,
          padding: padding,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
        child: Text(label, softWrap: false),
      ),
    );
  }
}

/// 테두리만 있는 버튼 (웹 background: var(--bg); border: 1px solid var(--border))
class OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool alignLeft;
  final bool active;
  final EdgeInsets padding;
  final double fontSize;
  const OutlineBtn(this.label,
      {super.key,
      this.onPressed,
      this.alignLeft = false,
      this.active = false,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: active ? c.accent : c.bg,
        foregroundColor: active ? Colors.white : c.text,
        padding: padding,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: active ? c.accent : c.border),
        ),
        textStyle: TextStyle(fontSize: fontSize, fontWeight: active ? FontWeight.w600 : FontWeight.w400),
      ),
      child: Text(label),
    );
  }
}

/// 헤더의 32x32 네모 아이콘 버튼
class BoxIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool active;
  const BoxIconButton({super.key, required this.icon, required this.onPressed, this.tooltip, this.active = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final btn = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: active ? c.accentLight : Colors.transparent,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: active ? c.accent : c.textMuted),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// 흐린 글자 버튼 (웹 사이드바 btnStyle — 배경 없음, 흐린 색)
class GhostTextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final double fontSize;
  final double opacity;
  final Color? color;
  final String? tooltip;
  const GhostTextButton(this.label,
      {super.key, required this.onPressed, this.fontSize = 13, this.opacity = 0.4, this.color, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final w = InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Opacity(
          opacity: opacity,
          child: Text(label, style: TextStyle(fontSize: fontSize, color: color ?? context.c.textMuted)),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// 날짜 입력칸 — 누르면 달력 (웹 input type="date")
class DateField extends StatelessWidget {
  final String? value; // 'YYYY-MM-DD'
  final ValueChanged<String?> onChanged;
  final double fontSize;
  final bool allowClear;
  const DateField({super.key, required this.value, required this.onChanged, this.fontSize = 14, this.allowClear = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return InkWell(
      onTap: () async {
        final initial = DateTime.tryParse(value ?? '') ?? DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1990),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked.toIso8601String().substring(0, 10));
      },
      child: InputDecorator(
        decoration: appInputDecoration(context),
        child: Row(children: [
          Expanded(
            child: Text(
              (value == null || value!.isEmpty) ? '연도-월-일' : value!,
              style: TextStyle(fontSize: fontSize, color: (value == null || value!.isEmpty) ? c.textMuted : c.textHeading),
            ),
          ),
          if (allowClear && value != null && value!.isNotEmpty)
            InkWell(onTap: () => onChanged(null), child: Icon(Icons.close, size: 14, color: c.textMuted))
          else
            Icon(Icons.calendar_today_outlined, size: 14, color: c.textMuted),
        ]),
      ),
    );
  }
}

String todayString() => DateTime.now().toIso8601String().substring(0, 10);

Future<bool> confirmDialog(BuildContext context, String message) async {
  final c = context.c;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.bg,
      content: Text(message, style: TextStyle(color: c.text, fontSize: 14)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인')),
      ],
    ),
  );
  return ok == true;
}

void showAlert(BuildContext context, String message) {
  final c = context.c;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.bg,
      content: Text(message, style: TextStyle(color: c.text, fontSize: 14)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('확인'))],
    ),
  );
}
