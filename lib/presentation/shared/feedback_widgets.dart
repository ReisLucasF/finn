import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Aviso curto no topo da tela (não cobre botões da parte de baixo).
void showSuccess(BuildContext context, String message) =>
    _showToast(context, message, error: false);

/// Como [showSuccess], com ícone de alerta.
void showError(BuildContext context, String message) =>
    _showToast(context, message, error: true);

void _showToast(BuildContext context, String message, {required bool error}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
    return;
  }
  _Toast.show(overlay, message, error: error);
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.error,
    required this.onDone,
  });

  final String message;
  final bool error;
  final VoidCallback onDone;

  static OverlayEntry? _current;

  static void show(OverlayState overlay, String message, {bool error = false}) {
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _Toast(
        message: message,
        error: error,
        onDone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _motion.forward();
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    if (!mounted) return;
    await _motion.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top + AppSpacing.md;
    return Positioned(
      top: top,
      left: AppSpacing.md,
      right: AppSpacing.md,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _motion,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, -0.4), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: _motion,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Material(
                  color: scheme.inverseSurface,
                  elevation: 8,
                  shadowColor: Colors.black38,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    onTap: () async {
                      await _motion.reverse();
                      if (mounted) widget.onDone();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.error
                                ? CupertinoIcons.exclamationmark_circle_fill
                                : CupertinoIcons.checkmark_circle_fill,
                            size: 18,
                            color: widget.error
                                ? scheme.error
                                : scheme.onInverseSurface,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              widget.message,
                              style: TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = CupertinoIcons.tray,
    this.detail,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: FadeSlideIn(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Halo(icon: icon, color: scheme.primary),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (detail != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    detail!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(CupertinoIcons.add, size: 18),
                    label: Text(actionLabel!),
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

class _Halo extends StatelessWidget {
  const _Halo({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Icon(icon, size: 36, color: color),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: FadeSlideIn(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Halo(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  color: scheme.error,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18),
                  label: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder de carregamento com brilho deslizante (shimmer).
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({super.key});

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final glow = isLight
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.06);
    return LayoutBuilder(
      builder: (context, constraints) {
        final blocks = _fittedBlocks(constraints.maxHeight);
        if (reduceMotion) {
          return ColorFiltered(
            colorFilter: ColorFilter.mode(base, BlendMode.srcIn),
            child: blocks,
          );
        }
        return AnimatedBuilder(
          animation: _controller,
          child: blocks,
          builder: (context, child) {
            final t = _controller.value * 3 - 1;
            return ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment(t - 1, -0.3),
                end: Alignment(t + 1, 0.3),
                colors: [base, Color.alphaBlend(glow, base), base],
                stops: const [0.35, 0.5, 0.65],
              ).createShader(rect),
              child: child,
            );
          },
        );
      },
    );
  }

  Widget _fittedBlocks(double maxHeight) {
    const padding = AppSpacing.lg;
    const gap = AppSpacing.md;
    const design = 180.0 + 96.0 + 140.0;
    final budget = maxHeight.isFinite
        ? (maxHeight - padding * 2 - gap * 2).clamp(0.0, design)
        : design;
    return Padding(
      padding: const EdgeInsets.all(padding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Block(height: budget * 180 / design),
          const SizedBox(height: gap),
          Row(
            children: [
              Expanded(child: _Block(height: budget * 96 / design)),
              const SizedBox(width: gap),
              Expanded(child: _Block(height: budget * 96 / design)),
            ],
          ),
          const SizedBox(height: gap),
          _Block(height: budget * 140 / design),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
    );
  }
}
