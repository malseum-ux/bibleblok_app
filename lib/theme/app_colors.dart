import 'package:flutter/material.dart';

// 웹(bibleblok/src/index.css)의 CSS 변수와 같은 색
class AppColors extends ThemeExtension<AppColors> {
  final Color bg;
  final Color bgSidebar;
  final Color bgCard;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color textHeading;
  final Color accent;
  final Color accentLight;

  const AppColors({
    required this.bg,
    required this.bgSidebar,
    required this.bgCard,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textHeading,
    required this.accent,
    required this.accentLight,
  });

  static const light = AppColors(
    bg: Color(0xFFFFFFFF),
    bgSidebar: Color(0xFFF7F7F8),
    bgCard: Color(0xFFFFFFFF),
    border: Color(0xFFE5E7EB),
    text: Color(0xFF374151),
    textMuted: Color(0xFF9CA3AF),
    textHeading: Color(0xFF111827),
    accent: Color(0xFF4F46E5),
    accentLight: Color(0xFFEEF2FF),
  );

  static const dark = AppColors(
    bg: Color(0xFF111827),
    bgSidebar: Color(0xFF1F2937),
    bgCard: Color(0xFF1F2937),
    border: Color(0xFF374151),
    text: Color(0xFFD1D5DB),
    textMuted: Color(0xFF6B7280),
    textHeading: Color(0xFFF9FAFB),
    accent: Color(0xFF818CF8),
    accentLight: Color(0xFF1E1B4B),
  );

  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: colors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
      primary: colors.accent,
      surface: colors.bg,
    ),
    textTheme: Typography.material2021().black.apply(
          bodyColor: colors.text,
          displayColor: colors.textHeading,
        ).copyWith(
          bodyMedium: TextStyle(fontSize: 14, color: colors.text),
        ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: colors.accent),
    dividerColor: colors.border,
    extensions: [colors],
  );
}
