import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final primary = isLight ? AppColors.accent : AppColors.accentDark;
    final onPrimary = isLight ? Colors.white : const Color(0xFF0A241A);
    final surface = isLight ? AppColors.surface : AppColors.surfaceDark;
    final onSurface = isLight ? AppColors.ink : AppColors.inkDark;
    final background = isLight
        ? AppColors.background
        : AppColors.backgroundDark;
    final line = isLight ? AppColors.line : AppColors.lineDark;
    final muted = isLight ? AppColors.muted : AppColors.mutedDark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: isLight ? AppColors.accentSoft : AppColors.accentDark,
      onSecondary: onPrimary,
      error: isLight ? AppColors.expense : AppColors.expenseDark,
      onError: isLight ? Colors.white : const Color(0xFF2A1210),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: isLight
          ? AppColors.washStart
          : AppColors.surfaceElevatedDark,
      outline: line,
      outlineVariant: line,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      borderSide: BorderSide(color: line, width: AppSpacing.hairline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: AppTypography.textTheme(brightness, onSurface),
      splashFactory: NoSplash.splashFactory,
      highlightColor: primary.withValues(alpha: 0.08),
      hoverColor: primary.withValues(alpha: 0.06),
      dividerColor: line,
      dividerTheme: DividerThemeData(
        color: line,
        thickness: AppSpacing.hairline,
        space: AppSpacing.hairline,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.headline(onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? AppColors.surfaceElevated : AppColors.surfaceElevatedDark,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side: BorderSide(color: line.withValues(alpha: 0.65), width: AppSpacing.hairline),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: onSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: isLight ? 0.12 : 0.22),
        disabledColor: surface,
        labelStyle: AppTypography.label(onSurface),
        secondaryLabelStyle: AppTypography.label(primary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          side: BorderSide(color: line, width: AppSpacing.hairline),
        ),
        side: BorderSide(color: line, width: AppSpacing.hairline),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? AppColors.surfaceElevated : AppColors.surfaceElevatedDark,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: primary, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shape: shape,
          textStyle: AppTypography.label(onPrimary).copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: shape,
          side: BorderSide(color: line),
          textStyle: AppTypography.label(onSurface).copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: AppTypography.label(primary).copyWith(fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isLight
            ? AppColors.surfaceElevated
            : AppColors.surfaceElevatedDark,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: line,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight
            ? AppColors.surfaceElevated
            : AppColors.surfaceElevatedDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: onSurface,
        contentTextStyle: AppTypography.label(
          isLight ? AppColors.inkDark : AppColors.ink,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
