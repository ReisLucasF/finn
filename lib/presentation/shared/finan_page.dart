import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Página com título grande e fundo em lavagem suave (estilo iOS).
class FinanPage extends StatelessWidget {
  const FinanPage({
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.leading,
    this.padding,
    this.bottomBar,
    this.showBackWhenCanPop = true,
    this.trailing,
    this.maxContentWidth = 1240,
    super.key,
  });

  /// Widget opcional à direita do título (ex.: botão de ação).
  final Widget? trailing;

  /// Largura máxima do conteúdo em telas largas.
  final double maxContentWidth;

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget> actions;
  final Widget? leading;
  final EdgeInsetsGeometry? padding;
  final Widget? bottomBar;
  final bool showBackWhenCanPop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final canPop = Navigator.of(context).canPop();
    final resolvedLeading =
        leading ??
        (showBackWhenCanPop && canPop
            ? IconButton(
                tooltip: 'Voltar',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(CupertinoIcons.chevron_back, color: scheme.primary),
              )
            : null);
    final showBar = actions.isNotEmpty || resolvedLeading != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isLight
              ? const [AppColors.washStart, AppColors.washEnd]
              : const [AppColors.washStartDark, AppColors.washEndDark],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: showBar
            ? AppBar(
                leading: resolvedLeading,
                actions: actions,
                title: const SizedBox.shrink(),
              )
            : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Constrained(
              maxWidth: maxContentWidth,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  showBar
                      ? 0
                      : MediaQuery.paddingOf(context).top + AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: FadeSlideIn(
                  offset: 10,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: AppTypography.title(scheme.onSurface),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  subtitle!,
                                  key: ValueKey(subtitle),
                                  style: AppTypography.label(
                                    scheme.onSurface.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: _Constrained(
                maxWidth: maxContentWidth,
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: body,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: bottomBar,
      ),
    );
  }
}

class _Constrained extends StatelessWidget {
  const _Constrained({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Padding lateral em vez de Align: mantém as restrições justas do pai.
    return LayoutBuilder(
      builder: (context, constraints) {
        final extra = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - maxWidth).clamp(0.0, double.infinity) / 2
            : 0.0;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: extra),
          child: child,
        );
      },
    );
  }
}

class FinanGroup extends StatelessWidget {
  const FinanGroup({required this.children, this.title, super.key});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                title!.toUpperCase(),
                style: AppTypography.label(
                  scheme.onSurface.withValues(alpha: 0.45),
                ).copyWith(letterSpacing: 0.8, fontSize: 12),
              ),
            ),
          ],
          DecoratedBox(
            decoration: FinanCard.decoration(
              context,
              radius: AppSpacing.radius,
            ),
            // Material transparente: ListTiles pintam hover/ripple acima do fundo.
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: AppSpacing.hairline,
                        indent: AppSpacing.md,
                        endIndent: AppSpacing.md,
                        color: scheme.outline.withValues(alpha: 0.7),
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
