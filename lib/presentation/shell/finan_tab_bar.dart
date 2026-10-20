import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class FinanTabItem {
  const FinanTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class FinanTabBar extends StatelessWidget {
  const FinanTabBar({
    required this.index,
    required this.items,
    required this.onChanged,
    this.onCompose,
    super.key,
  });

  final int index;
  final List<FinanTabItem> items;
  final ValueChanged<int> onChanged;
  final VoidCallback? onCompose;

  static const itemsDefault = <FinanTabItem>[
    FinanTabItem(
      label: 'Início',
      icon: CupertinoIcons.house,
      activeIcon: CupertinoIcons.house_fill,
    ),
    FinanTabItem(
      label: 'Contas',
      icon: CupertinoIcons.creditcard,
      activeIcon: CupertinoIcons.creditcard_fill,
    ),
    FinanTabItem(
      label: 'Extrato',
      icon: CupertinoIcons.list_bullet,
      activeIcon: CupertinoIcons.list_bullet_below_rectangle,
    ),
    FinanTabItem(
      label: 'Mais',
      icon: CupertinoIcons.ellipsis_circle,
      activeIcon: CupertinoIcons.ellipsis_circle_fill,
    ),
  ];

  /// Destinos da barra lateral. O índice casa com as páginas do shell.
  static const sidebarItems = <FinanTabItem>[
    FinanTabItem(
      label: 'Início',
      icon: CupertinoIcons.house,
      activeIcon: CupertinoIcons.house_fill,
    ),
    FinanTabItem(
      label: 'Contas',
      icon: CupertinoIcons.creditcard,
      activeIcon: CupertinoIcons.creditcard_fill,
    ),
    FinanTabItem(
      label: 'Extrato',
      icon: CupertinoIcons.list_bullet,
      activeIcon: CupertinoIcons.list_bullet_below_rectangle,
    ),
    FinanTabItem(
      label: 'Orçamentos',
      icon: CupertinoIcons.chart_pie,
      activeIcon: CupertinoIcons.chart_pie_fill,
    ),
    FinanTabItem(
      label: 'Investimentos',
      icon: CupertinoIcons.graph_square,
      activeIcon: CupertinoIcons.graph_square_fill,
    ),
    FinanTabItem(
      label: 'Metas',
      icon: CupertinoIcons.flag,
      activeIcon: CupertinoIcons.flag_fill,
    ),
    FinanTabItem(
      label: 'Reserva',
      icon: CupertinoIcons.shield,
      activeIcon: CupertinoIcons.shield_fill,
    ),
    FinanTabItem(
      label: 'Cartões',
      icon: CupertinoIcons.rectangle_stack,
      activeIcon: CupertinoIcons.rectangle_stack_fill,
    ),
    FinanTabItem(
      label: 'Mais',
      icon: CupertinoIcons.ellipsis_circle,
      activeIcon: CupertinoIcons.ellipsis_circle_fill,
    ),
  ];

  /// Índices de [sidebarItems] que a barra de baixo do celular mostra.
  static const mobileIndexes = <int>[0, 1, 2, 8];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final showCompose = onCompose != null && (index == 0 || index == 2);

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: (isLight
                  ? AppColors.surfaceElevated
                  : AppColors.surfaceElevatedDark)
              .withValues(alpha: 0.94),
          border: Border(
            top: BorderSide(
              color: scheme.outline.withValues(alpha: 0.7),
              width: AppSpacing.hairline,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i == 2)
                    _ComposeSlot(
                      visible: showCompose,
                      onPressed: onCompose ?? () {},
                    ),
                  Expanded(
                    child: _TabButton(
                      item: items[i],
                      selected: index == i,
                      onTap: () => onChanged(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FinanTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected
        ? scheme.primary
        : scheme.onSurface.withValues(alpha: 0.45);
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              selected ? item.activeIcon : item.icon,
              size: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: AppTypography.label(color).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class FinanComposeFooter extends StatelessWidget {
  const FinanComposeFooter({
    required this.visible,
    required this.onPressed,
    super.key,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (isLight
                ? AppColors.surfaceElevated
                : AppColors.surfaceElevatedDark)
            .withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(
            color: visible
                ? scheme.outline.withValues(alpha: 0.7)
                : Colors.transparent,
            width: AppSpacing.hairline,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          height: visible ? 64 : 0,
          child: ClipRect(
            child: Center(
              child: _ComposeSlot(visible: visible, onPressed: onPressed),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposeSlot extends StatefulWidget {
  const _ComposeSlot({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  State<_ComposeSlot> createState() => _ComposeSlotState();
}

class _ComposeSlotState extends State<_ComposeSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 220),
      value: widget.visible ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _ComposeSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _motion.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _motion.forward();
    } else {
      _motion.reverse();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        final t = _motion.value;
        final scale = widget.visible
            ? Curves.easeOutBack.transform(t)
            : Curves.easeInCubic.transform(t);
        return Align(
          alignment: Alignment.center,
          widthFactor: t.clamp(0.0, 1.0),
          child: IgnorePointer(
            ignoring: !widget.visible || t < 0.85,
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: (1 - t) * -0.35,
                child: Transform.scale(
                  scale: scale,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: _ComposeButton(onPressed: widget.onPressed),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  const _ComposeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Center(
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                CupertinoIcons.add,
                color: scheme.onPrimary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
