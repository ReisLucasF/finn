import 'package:finan/app/app_scope.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/presentation/shell/finan_tab_bar.dart';
import 'package:flutter/material.dart';

class FinanSidebar extends StatelessWidget {
  const FinanSidebar({
    required this.index,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final int index;
  final List<FinanTabItem> items;
  final ValueChanged<int> onChanged;

  static const _itemHeight = 42.0;
  static const _itemGap = 4.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final panel = isLight ? AppColors.surfaceElevated : AppColors.surfaceDark;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: panel,
        border: Border(
          right: BorderSide(
            color: scheme.outline.withValues(alpha: 0.85),
            width: AppSpacing.hairline,
          ),
        ),
      ),
      child: SizedBox(
        width: 240,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Brand(),
                const SizedBox(height: AppSpacing.xl),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    bottom: AppSpacing.xs,
                  ),
                  child: Text(
                    'MENU',
                    style: AppTypography.label(
                      scheme.onSurface.withValues(alpha: 0.4),
                    ).copyWith(fontSize: 11, letterSpacing: 1.2),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Stack(
                      children: [
                        // Indicador que desliza até o item selecionado.
                        AnimatedPositioned(
                          duration: reduce
                              ? Duration.zero
                              : const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          top: index * (_itemHeight + _itemGap),
                          left: 0,
                          right: 0,
                          height: _itemHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 3,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const SizedBox(height: _itemGap),
                              _SideItem(
                                item: items[i],
                                selected: index == i,
                                height: _itemHeight,
                                onTap: () => onChanged(i),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const _UserFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Image.asset(
              'assets/icon.png',
              width: 36,
              height: 36,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'Finn',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Finn', style: AppTypography.headline(scheme.onSurface)),
        ],
      ),
    );
  }
}

class _SideItem extends StatefulWidget {
  const _SideItem({
    required this.item,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final FinanTabItem item;
  final bool selected;
  final double height;
  final VoidCallback onTap;

  @override
  State<_SideItem> createState() => _SideItemState();
}

class _SideItemState extends State<_SideItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final color = selected
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: _hover ? 0.9 : 0.66);
    return Semantics(
      button: true,
      selected: selected,
      label: widget.item.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: _hover && !selected
                  ? scheme.onSurface.withValues(alpha: 0.04)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    selected ? widget.item.activeIcon : widget.item.icon,
                    key: ValueKey(selected),
                    size: 19,
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 160),
                  style: AppTypography.label(color).copyWith(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                  child: Text(widget.item.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = AppScope.of(context).session.user;
    final name = user.name.trim();
    final email = user.email?.trim() ?? '';
    final initials = name.isEmpty
        ? '?'
        : name
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part.characters.first.toUpperCase())
              .join();
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primary.withValues(alpha: 0.16),
            child: Text(
              initials,
              style: AppTypography.label(scheme.primary).copyWith(fontSize: 12),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Você' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label(scheme.onSurface),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label(
                      scheme.onSurface.withValues(alpha: 0.45),
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
