import 'package:finan/app/app_scope.dart';
import 'package:finan/presentation/backup/pick_finance_backup.dart';
import 'package:finan/application/categories/category_seeds.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum _Path { fresh, restore }

enum _ObStep {
  welcome,
  path,
  restore,
  name,
  currency,
  privacy,
  account,
  balance,
  categories,
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _accountName = TextEditingController();
  final TextEditingController _balance = TextEditingController();
  AccountType _type = AccountType.checking;
  _Path? _path;
  int _index = 0;
  bool _saving = false;
  bool _restoring = false;
  String? _error;
  String? _backupFileName;
  List<Category> _categories = const [];
  bool _loadedCategories = false;

  List<_ObStep> get _flow {
    if (_path == _Path.restore) {
      return const [_ObStep.welcome, _ObStep.path, _ObStep.restore];
    }
    if (_path == _Path.fresh) {
      return const [
        _ObStep.welcome,
        _ObStep.path,
        _ObStep.name,
        _ObStep.currency,
        _ObStep.privacy,
        _ObStep.account,
        _ObStep.balance,
        _ObStep.categories,
      ];
    }
    return const [_ObStep.welcome, _ObStep.path];
  }

  _ObStep get _step => _flow[_index.clamp(0, _flow.length - 1)];

  @override
  void dispose() {
    _name.dispose();
    _accountName.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    if (_loadedCategories) return;
    final scope = AppScope.of(context);
    final categories = await scope.graph.listCategories(scope.session.user.id);
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _loadedCategories = true;
    });
  }

  void _next() {
    final step = _step;
    if (step == _ObStep.path && _path == null) {
      setState(() => _error = 'Escolha como deseja começar.');
      return;
    }
    if (step == _ObStep.name && _name.text.trim().isEmpty) {
      setState(() => _error = 'Informe seu nome.');
      return;
    }
    if (step == _ObStep.account && _accountName.text.trim().isEmpty) {
      setState(() => _error = 'Informe o nome da conta.');
      return;
    }
    if (step == _ObStep.balance && _balance.text.trim().isNotEmpty) {
      final parsed = tryParseMoney(_balance.text, allowNegative: true);
      if (parsed == null) {
        setState(() => _error = 'Informe um saldo inicial válido.');
        return;
      }
    }
    if (step == _ObStep.restore) {
      _pickAndRestore();
      return;
    }
    if (step == _ObStep.categories) {
      _finish();
      return;
    }

    final nextIndex = _index + 1;
    if (nextIndex >= _flow.length) return;
    setState(() {
      _error = null;
      _index = nextIndex;
    });
    if (_flow[nextIndex] == _ObStep.categories) _loadCategories();
  }

  void _back() {
    if (_index == 0 || _saving || _restoring) return;
    setState(() {
      _error = null;
      _index -= 1;
      if (_step == _ObStep.path) {
        // Mantém a escolha visual; o fluxo ainda depende de _path.
      }
    });
  }

  Future<void> _pickAndRestore() async {
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final picked = await pickFinanceBackup(
        dialogTitle: 'Escolher backup do Finn',
      );
      if (!mounted) return;
      if (picked == null) {
        setState(() => _restoring = false);
        return;
      }
      setState(() => _backupFileName = picked.name);

      final bytes = picked.bytes;
      if (!mounted) return;
      final scope = AppScope.of(context);
      await scope.graph.restoreBackup(bytes);
      final user = await scope.graph.open();
      if (!mounted) return;
      scope.session.setUser(user);
      if (user.needsOnboarding) {
        setState(() {
          _restoring = false;
          _error =
              'Backup restaurado, mas o perfil ainda está incompleto. Continue o cadastro.';
          _path = _Path.fresh;
          _index = _flow.indexOf(_ObStep.name);
        });
      }
      // Se o usuário tem nome, o AppHome troca para HomeShell sozinho.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _restoring = false;
        _error = friendlyError(error);
      });
    }
  }

  Future<void> _finish() async {
    final scope = AppScope.of(context);
    final parsed = _balance.text.trim().isEmpty
        ? const Money(0)
        : tryParseMoney(_balance.text, allowNegative: true);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Informe seu nome.');
      return;
    }
    if (_accountName.text.trim().isEmpty) {
      setState(() => _error = 'Informe o nome da conta.');
      return;
    }
    if (parsed == null) {
      setState(() => _error = 'Informe um saldo inicial válido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final userId = scope.session.user.id;
      final accounts = await scope.graph.listAccounts(userId);
      if (accounts.isEmpty) {
        await scope.graph.createAccount(
          userId: userId,
          name: _accountName.text,
          type: _type,
          initialBalance: parsed,
          currency: scope.session.user.currency,
        );
      }
      final user = await scope.graph.updateUserProfile(
        name: _name.text,
        currency: scope.session.user.currency,
      );
      if (!mounted) return;
      scope.session.setUser(user);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(error);
      });
    }
  }

  String get _primaryLabel {
    if (_saving) return 'Salvando…';
    if (_restoring) return 'Restaurando…';
    return switch (_step) {
      _ObStep.welcome => 'Começar',
      _ObStep.restore => 'Selecionar backup',
      _ObStep.categories => 'Entrar no Finn',
      _ => 'Continuar',
    };
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final total = _flow.length;
    final progress = (_index + 1) / total;

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
        body: Stack(
          children: [
            const _AmbientOrbs(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  children: [
                    _TopBar(
                      step: _index + 1,
                      total: total,
                      progress: progress,
                      reduceMotion: reduceMotion,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          if (reduceMotion) return child;
                          final offset = Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(_step),
                          child: _content(scheme),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _BottomActions(
                      showBack: _index > 0,
                      busy: _saving || _restoring,
                      primaryLabel: _primaryLabel,
                      onBack: _back,
                      onPrimary: _saving || _restoring ? null : _next,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(ColorScheme scheme) {
    return switch (_step) {
      _ObStep.welcome => _CenteredCopy(
        eyebrow: 'Finn',
        eyebrowStyle: AppTypography.display(scheme.primary),
        title: 'Seu dinheiro,\ncom clareza.',
        body:
            'Contas, receitas e despesas num só lugar. O saldo nasce do histórico — não de um número solto.',
      ),
      _ObStep.path => _PathStep(
        selected: _path,
        onSelect: (path) {
          setState(() {
            _path = path;
            _error = null;
            // Recalcula o fluxo mantendo o índice em "path".
            _index = 1;
          });
        },
      ),
      _ObStep.restore => _CenteredCopy(
        icon: CupertinoIcons.arrow_down_doc,
        title: 'Continue de onde parou',
        body:
            'Selecione um arquivo .financebackup. Seus dados locais serão substituídos pelo conteúdo do backup.',
        footer: _backupFileName == null
            ? null
            : Text(
                _backupFileName!,
                textAlign: TextAlign.center,
                style: AppTypography.label(scheme.primary),
              ),
      ),
      _ObStep.name => _CenteredField(
        title: 'Como podemos\nte chamar?',
        child: TextField(
          controller: _name,
          autofocus: true,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.words,
          style: AppTypography.headline(scheme.onSurface),
          decoration: const InputDecoration(
            hintText: 'Seu nome',
            alignLabelWithHint: true,
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _next(),
        ),
      ),
      _ObStep.currency => const _CenteredCopy(
        icon: CupertinoIcons.money_dollar_circle,
        title: 'Real brasileiro',
        body:
            'Nesta versão o Finn trabalha em BRL — valores e saldos no formato que você já conhece.',
      ),
      _ObStep.privacy => const _CenteredCopy(
        icon: CupertinoIcons.lock_shield,
        title: 'Só neste aparelho',
        body:
            'Seus dados ficam neste dispositivo. Nada é enviado a um servidor. Backup fica sob o seu controle.',
      ),
      _ObStep.account => _CenteredField(
        title: 'Sua primeira conta',
        child: Column(
          children: [
            TextField(
              controller: _accountName,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.sentences,
              style: AppTypography.headline(scheme.onSurface),
              decoration: const InputDecoration(hintText: 'Ex.: Conta corrente'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final type in AccountType.values)
                  ChoiceChip(
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
          ],
        ),
      ),
      _ObStep.balance => _CenteredField(
        title: 'Saldo inicial',
        body: 'Quanto há nessa conta agora? Pode deixar zero e lançar depois.',
        child: TextField(
          controller: _balance,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: AppTypography.display(scheme.onSurface),
          decoration: const InputDecoration(hintText: '0,00'),
          onSubmitted: (_) => _next(),
        ),
      ),
      _ObStep.categories => _CategoryStep(
        categories: _categories.isEmpty
            ? [
                for (final seed in CategorySeeds.all)
                  Category(
                    id: seed.id,
                    name: seed.name,
                    type: seed.type,
                    icon: seed.icon,
                    color: seed.color,
                    isSystem: true,
                    isActive: true,
                    createdAt: DateTime.utc(2026),
                    updatedAt: DateTime.utc(2026),
                  ),
              ]
            : _categories,
      ),
    };
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.step,
    required this.total,
    required this.progress,
    required this.reduceMotion,
  });

  final int step;
  final int total;
  final double progress;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          'Finn',
          style: AppTypography.label(scheme.primary),
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 4,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                  color: scheme.primary,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$step de $total',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
        ),
      ],
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.showBack,
    required this.busy,
    required this.primaryLabel,
    required this.onBack,
    required this.onPrimary,
  });

  final bool showBack;
  final bool busy;
  final String primaryLabel;
  final VoidCallback onBack;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onBack,
              child: const Text('Voltar'),
            ),
          ),
        if (showBack) const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: showBack ? 1 : 1,
          child: FilledButton(
            onPressed: onPrimary,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(primaryLabel),
          ),
        ),
      ],
    );
  }
}

class _AmbientOrbs extends StatelessWidget {
  const _AmbientOrbs();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final accent = isLight ? AppColors.accentSoft : AppColors.accentDark;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Orb(color: accent.withValues(alpha: isLight ? 0.14 : 0.12), size: 220),
          ),
          Positioned(
            bottom: 80,
            left: -90,
            child: _Orb(color: accent.withValues(alpha: isLight ? 0.10 : 0.08), size: 260),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _CenteredCopy extends StatelessWidget {
  const _CenteredCopy({
    required this.title,
    required this.body,
    this.eyebrow,
    this.eyebrowStyle,
    this.icon,
    this.footer,
  });

  final String title;
  final String body;
  final String? eyebrow;
  final TextStyle? eyebrowStyle;
  final IconData? icon;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow!,
                        textAlign: TextAlign.center,
                        style: eyebrowStyle ?? AppTypography.label(scheme.primary),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (icon != null) ...[
                      Icon(icon, size: 44, color: scheme.primary),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.title(scheme.onSurface),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.72),
                            height: 1.45,
                          ),
                    ),
                    if (footer != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CenteredField extends StatelessWidget {
  const _CenteredField({
    required this.title,
    required this.child,
    this.body,
  });

  final String title;
  final String? body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.title(scheme.onSurface),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        body!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.72),
                            ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    child,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PathStep extends StatelessWidget {
  const _PathStep({required this.selected, required this.onSelect});

  final _Path? selected;
  final ValueChanged<_Path> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Você é novo\npor aqui?',
                      textAlign: TextAlign.center,
                      style: AppTypography.title(scheme.onSurface),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Escolha como prefere começar.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.72),
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _PathCard(
                      selected: selected == _Path.fresh,
                      icon: CupertinoIcons.sparkles,
                      title: 'Começar do zero',
                      subtitle: 'Criar perfil, conta e categorias iniciais.',
                      onTap: () => onSelect(_Path.fresh),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _PathCard(
                      selected: selected == _Path.restore,
                      icon: CupertinoIcons.arrow_counterclockwise,
                      title: 'Já uso o Finn',
                      subtitle: 'Restaurar um backup e continuar de onde parei.',
                      onTap: () => onSelect(_Path.restore),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: selected ? 1.02 : 1,
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surface.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.08),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(icon, color: scheme.primary, size: 28),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.headline(scheme.onSurface)),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: selected ? 1 : 0,
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryStep extends StatelessWidget {
  const _CategoryStep({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          'Categorias prontas',
          textAlign: TextAlign.center,
          style: AppTypography.title(scheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Você pode editar ou criar outras depois.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final category in categories)
                      Chip(
                        avatar: Icon(iconFromName(category.icon), size: 16),
                        label: Text(category.name),
                        side: BorderSide(
                          color: scheme.onSurface.withValues(alpha: 0.08),
                        ),
                        backgroundColor: scheme.surface.withValues(alpha: 0.6),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
