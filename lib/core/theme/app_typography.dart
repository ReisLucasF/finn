import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTypography {
  const AppTypography._();

  static TextStyle display(Color color) {
    return GoogleFonts.sora(
      fontSize: 36,
      height: 1.05,
      fontWeight: FontWeight.w600,
      letterSpacing: -1.2,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle title(Color color) {
    return GoogleFonts.sora(
      fontSize: 28,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.8,
      color: color,
    );
  }

  static TextStyle headline(Color color) {
    return GoogleFonts.sora(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: color,
    );
  }

  static TextStyle label(Color color) {
    return GoogleFonts.sourceSans3(
      fontSize: 13,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.15,
      color: color,
    );
  }

  static TextStyle _sora({
    required double size,
    required FontWeight weight,
    required double letterSpacing,
    double height = 1.2,
  }) {
    return GoogleFonts.sora(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle _sans({
    required double size,
    FontWeight weight = FontWeight.w400,
    double height = 1.4,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.sourceSans3(
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );
  }

  /// Monta [TextTheme] do Flutter sem passar pelo helper do google_fonts
  /// (evita conflito com material_ui no Flutter 3.47).
  static TextTheme textTheme(Brightness brightness, Color onSurface) {
    return TextTheme(
      displayLarge: _sora(size: 36, weight: FontWeight.w600, letterSpacing: -1.2)
          .copyWith(color: onSurface),
      displayMedium: _sora(size: 32, weight: FontWeight.w600, letterSpacing: -1)
          .copyWith(color: onSurface),
      displaySmall: _sora(size: 28, weight: FontWeight.w600, letterSpacing: -0.8)
          .copyWith(color: onSurface),
      headlineLarge: _sora(size: 28, weight: FontWeight.w600, letterSpacing: -0.8)
          .copyWith(color: onSurface),
      headlineMedium: _sora(size: 22, weight: FontWeight.w600, letterSpacing: -0.5)
          .copyWith(color: onSurface),
      headlineSmall: _sora(size: 20, weight: FontWeight.w600, letterSpacing: -0.4)
          .copyWith(color: onSurface),
      titleLarge: _sora(size: 18, weight: FontWeight.w600, letterSpacing: -0.3)
          .copyWith(color: onSurface),
      titleMedium: _sans(size: 16, weight: FontWeight.w600)
          .copyWith(color: onSurface),
      titleSmall: _sans(size: 14, weight: FontWeight.w600)
          .copyWith(color: onSurface),
      bodyLarge: _sans(size: 16).copyWith(color: onSurface),
      bodyMedium: _sans(size: 14).copyWith(color: onSurface),
      bodySmall: _sans(size: 12, height: 1.35).copyWith(color: onSurface),
      labelLarge: _sans(size: 14, weight: FontWeight.w600)
          .copyWith(color: onSurface),
      labelMedium: _sans(size: 12, weight: FontWeight.w600, letterSpacing: 0.15)
          .copyWith(color: onSurface),
      labelSmall: _sans(size: 11, weight: FontWeight.w600, letterSpacing: 0.2)
          .copyWith(color: onSurface),
    );
  }
}
