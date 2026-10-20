import 'package:flutter/material.dart';

/// Paleta Finn: pinho e papel fresco — longe do Material roxo padrão.
class AppColors {
  const AppColors._();

  static const Color accent = Color(0xFF0F5C45);
  static const Color accentSoft = Color(0xFF3D8F72);
  static const Color accentDark = Color(0xFF7DCFB0);
  static const Color expense = Color(0xFF9B3B32);
  static const Color expenseDark = Color(0xFFF0A89E);
  static const Color ink = Color(0xFF15201B);
  static const Color inkDark = Color(0xFFF2F7F4);
  static const Color background = Color(0xFFEEF4F1);
  static const Color backgroundDark = Color(0xFF101613);
  static const Color surface = Color(0xFFF9FCFA);
  static const Color surfaceDark = Color(0xFF1A221E);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color surfaceElevatedDark = Color(0xFF232C28);
  static const Color line = Color(0xFFD5E0DA);
  static const Color lineDark = Color(0xFF2E3A34);
  static const Color muted = Color(0xFF5C6B64);
  static const Color mutedDark = Color(0xFF9AADA3);
  static const Color washStart = Color(0xFFE4F0EA);
  static const Color washEnd = Color(0xFFEEF4F1);
  static const Color washStartDark = Color(0xFF15241E);
  static const Color washEndDark = Color(0xFF101613);

  static const Color warning = Color(0xFFB7791F);
  static const Color warningDark = Color(0xFFF2C46D);
  static const Color info = Color(0xFF3E5C9A);
  static const Color infoDark = Color(0xFF9DB6EE);

  /// Gradiente do cartão de destaque (patrimônio).
  static const List<Color> heroLight = [
    Color(0xFF0B4A37),
    Color(0xFF0F5C45),
    Color(0xFF1C7A5C),
  ];
  static const List<Color> heroDark = [
    Color(0xFF0E3328),
    Color(0xFF145140),
    Color(0xFF1D6B53),
  ];

  static Color incomeOf(Brightness b) =>
      b == Brightness.light ? accentSoft : accentDark;
  static Color expenseOf(Brightness b) =>
      b == Brightness.light ? expense : expenseDark;
  static Color warningOf(Brightness b) =>
      b == Brightness.light ? warning : warningDark;
  static Color infoOf(Brightness b) => b == Brightness.light ? info : infoDark;
}
