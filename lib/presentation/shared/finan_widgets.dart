import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/material.dart';

/// Cartão de destaque em degradê (mesmo estilo do patrimônio na dashboard).
class FinanHero extends StatelessWidget {
  const FinanHero({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.badge,
    this.stats = const [],
    this.trend = const [],
    this.side,
    this.footer,
    super.key,
  });

  final IconData icon;
  final String label;
  final Money value;
  final String? caption;

  /// Pílula à direita do rótulo (ex.: variação).
  final Widget? badge;
  final List<HeroStat> stats;

  /// Valores para a linha de tendência ao fundo (opcional).
  final List<int> trend;

  /// Widget à direita do valor (ex.: anel de progresso).
  final Widget? side;
  final Widget? footer;

  static const onHero = Colors.white;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final soft = onHero.withValues(alpha: 0.72);
    final hasTrend = trend.length >= 2;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg + 4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight ? AppColors.heroLight : AppColors.heroDark,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: isLight ? 0.3 : 0.4),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(right: -60, top: -80, child: _Glow(size: 220)),
          const Positioned(
            left: -40,
            bottom: -90,
            child: _Glow(size: 180, alpha: 0.07),
          ),
          if (hasTrend)
            Positioned(
              left: 0,
              right: 0,
              bottom: stats.isEmpty ? 0 : 84,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0.5,
                  child: Sparkline(values: trend, color: onHero, height: 56),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: soft),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(label, style: AppTypography.label(soft)),
                    ),
                    ?badge,
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: AnimatedMoney(
                              value: value,
                              style: AppTypography.display(onHero)
                                  .copyWith(fontSize: 38),
                            ),
                          ),
                          if (caption != null) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              caption!,
                              style: AppTypography.label(soft)
                                  .copyWith(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (side != null) ...[
                      const SizedBox(width: AppSpacing.md),
                      side!,
                    ],
                  ],
                ),
                if (stats.isNotEmpty) ...[
                  SizedBox(height: hasTrend ? 64 : AppSpacing.lg),
                  Row(
                    children: [
                      for (var i = 0; i < stats.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.xs),
                        Expanded(child: stats[i]),
                      ],
                    ],
                  ),
                ],
                if (footer != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  DefaultTextStyle.merge(
                    style: AppTypography.label(soft)
                        .copyWith(fontWeight: FontWeight.w500, fontSize: 12),
                    child: footer!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, this.alpha = 0.12});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

/// Mini-bloco translúcido dentro do [FinanHero].
class HeroStat extends StatelessWidget {
  const HeroStat({
    required this.icon,
    required this.label,
    this.money,
    this.text,
    super.key,
  }) : assert(money != null || text != null);

  final IconData icon;
  final String label;
  final Money? money;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final soft = Colors.white.withValues(alpha: 0.7);
    final style = AppTypography.label(Colors.white)
        .copyWith(fontSize: 15, fontWeight: FontWeight.w700);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: soft),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(soft).copyWith(fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: money != null
                ? AnimatedMoney(value: money!, style: style)
                : Text(text!, style: style),
          ),
        ],
      ),
    );
  }
}

/// Pílula de filtro/seleção com animação (mesma da dashboard).
class FinanPill extends StatelessWidget {
  const FinanPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailingIcon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected
        ? scheme.onPrimary
        : scheme.onSurface.withValues(alpha: 0.72);
    return Semantics(
      selected: selected,
      button: true,
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
              width: AppSpacing.hairline,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(fg),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                Icon(trailingIcon, size: 13, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícone da categoria com a cor dela (clareada no tema escuro).
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({
    required this.category,
    this.fallbackIcon = Icons.label_outline,
    this.fallbackColor,
    this.size = 38,
    super.key,
  });

  final Category? category;
  final IconData fallbackIcon;
  final Color? fallbackColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final raw = colorFromHex(
      category?.color,
      fallbackColor ?? Theme.of(context).colorScheme.primary,
    );
    final tint = brightness == Brightness.dark && category?.color != null
        ? Color.lerp(raw, Colors.white, 0.4)!
        : raw;
    final icon = category?.icon == null
        ? fallbackIcon
        : iconFromName(category!.icon);
    return IconBadge(icon: icon, color: tint, size: size);
  }
}

/// Indicador compacto: ícone, rótulo, valor e legenda.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.icon,
    required this.color,
    required this.label,
    this.money,
    this.text,
    this.caption,
    this.trailing,
    super.key,
  }) : assert(money != null || text != null);

  final IconData icon;
  final Color color;
  final String label;
  final Money? money;
  final String? text;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = AppTypography.headline(scheme.onSurface);
    return FinanCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppSpacing.radius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, color: color, size: 32),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.label(
              scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: money != null
                ? AnimatedMoney(value: money!, style: style)
                : Text(text!, style: style),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.5)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Distribui [children] em linhas de [columns] colunas com altura igual.
class TileGrid extends StatelessWidget {
  const TileGrid({
    required this.children,
    required this.columns,
    this.spacing = AppSpacing.sm,
    super.key,
  });

  final List<Widget> children;
  final int columns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      if (i > 0) rows.add(SizedBox(height: spacing));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: spacing),
                Expanded(
                  child: i + c < children.length
                      ? children[i + c]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// Padding padrão das listas de tela, com respiro para a barra inferior.
EdgeInsets screenPadding(BuildContext context) => EdgeInsets.fromLTRB(
  AppSpacing.lg,
  AppSpacing.xs,
  AppSpacing.lg,
  AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
);

/// Colunas para grades de cards conforme a largura disponível.
int gridColumns(double width, {int max = 3}) {
  if (width >= 1100 && max >= 3) return 3;
  if (width >= 700) return 2;
  return 1;
}
