import 'package:finan/app/app_scope.dart';
import 'package:finan/application/budgets/budget_actions.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/services/budget_service.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({this.refreshTick = 0, super.key});

  final int refreshTick;

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  BudgetPlanning? _planning;
  bool _loading = true;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant BudgetsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    if (_planning == null) setState(() => _loading = true);
    try {
      final scope = AppScope.of(context);
      final planning = await scope.graph.getBudgetPlanning(
        scope.session.user.id,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _planning = planning;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _edit({BudgetStatus? status, Category? preset}) async {
    final planning = _planning;
    if (planning == null) return;
    final budgeted = {
      for (final item in planning.overview.items) item.category.id,
    };
    final available = [
      for (final category in planning.categories)
        if (!budgeted.contains(category.id) ||
            category.id == status?.category.id)
          category,
    ];
    if (available.isEmpty) {
      showSuccess(context, 'Todas as categorias de despesa já têm orçamento.');
      return;
    }
    final result = await showModalBottomSheet<_EditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _BudgetEditor(
        categories: available,
        suggestions: planning.suggestions,
        initialCategory: status?.category ?? preset,
        initialLimit: status?.limit,
        editing: status != null,
      ),
    );
    if (result == null || !mounted) return;
    final scope = AppScope.of(context);
    try {
      if (result.delete) {
        final confirmed = await confirmAction(
          context,
          title: 'Excluir orçamento?',
          message:
              'O limite de ${status!.category.name} será removido. '
              'Os lançamentos não são afetados.',
          confirmLabel: 'Excluir',
        );
        if (!confirmed) return;
        await scope.graph.deleteBudget(status.budget.id);
        if (mounted) showSuccess(context, 'Orçamento removido.');
      } else {
        await scope.graph.saveBudget(
          userId: scope.session.user.id,
          categoryId: result.categoryId,
          monthlyLimit: result.limit,
        );
        if (mounted) showSuccess(context, 'Orçamento salvo.');
      }
      await _load();
    } catch (error) {
      if (mounted) showError(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final planning = _planning;
    final overview = planning?.overview;
    return FinanPage(
      title: 'Orçamentos',
      subtitle: overview == null
          ? 'Limites mensais por categoria'
          : '${formatLocalDate(overview.period.startInclusive)} – '
                '${formatLocalDate(overview.period.endInclusive)} · '
                '${overview.daysLeft} ${overview.daysLeft == 1 ? 'dia restante' : 'dias restantes'}',
      trailing: planning == null
          ? null
          : IconButton.filledTonal(
              tooltip: 'Novo orçamento',
              onPressed: () => _edit(),
              icon: const Icon(CupertinoIcons.add),
            ),
      body: _loading && planning == null
          ? const LoadingSkeleton()
          : _error != null && planning == null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : planning!.overview.isEmpty
          ? _EmptyBudgets(planning: planning, onCreate: _edit)
          : RefreshIndicator(
              onRefresh: _load,
              child: _BudgetList(planning: planning, onEdit: _edit),
            ),
    );
  }
}

typedef _EditCallback = Future<void> Function({
  BudgetStatus? status,
  Category? preset,
});

class _EditorResult {
  const _EditorResult.save(this.categoryId, this.limit) : delete = false;
  const _EditorResult.delete()
    : categoryId = '',
      limit = Money.zero,
      delete = true;

  final String categoryId;
  final Money limit;
  final bool delete;
}

Color _stateColor(BudgetState state, Brightness brightness) => switch (state) {
  BudgetState.ok => AppColors.incomeOf(brightness),
  BudgetState.warning => AppColors.warningOf(brightness),
  BudgetState.over => AppColors.expenseOf(brightness),
};

/// Categorias sem orçamento com histórico de gasto, mais caras primeiro.
List<(Category, Money)> _openSuggestions(BudgetPlanning planning) {
  final budgeted = {
    for (final item in planning.overview.items) item.category.id,
  };
  return [
    for (final category in planning.categories)
      if (!budgeted.contains(category.id) &&
          planning.suggestions[category.id] != null)
        (category, planning.suggestions[category.id]!),
  ]..sort((a, b) => b.$2.cents.compareTo(a.$2.cents));
}

// ───────────────────────────── Vazio ─────────────────────────────

class _EmptyBudgets extends StatelessWidget {
  const _EmptyBudgets({required this.planning, required this.onCreate});

  final BudgetPlanning planning;
  final _EditCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final suggestions = _openSuggestions(planning).take(4).toList();
    if (suggestions.isEmpty) {
      return EmptyView(
        icon: CupertinoIcons.chart_pie,
        message: 'Nenhum orçamento ainda.',
        detail:
            'Defina quanto quer gastar por mês em cada categoria e acompanhe '
            'o consumo ao longo do mês.',
        actionLabel: 'Criar orçamento',
        onAction: () => onCreate(),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        FadeSlideIn(
          child: FinanCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                  icon: CupertinoIcons.chart_pie_fill,
                  color: Theme.of(context).colorScheme.primary,
                  size: 44,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Comece pelos seus maiores gastos',
                  style: AppTypography.headline(
                    Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Sugerimos limites com base na média dos últimos '
                  '${GetBudgetPlanning.historyMonths} meses. Toque para ajustar '
                  'e salvar.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SuggestionList(suggestions: suggestions, onCreate: onCreate),
        const SizedBox(height: AppSpacing.md),
        FadeSlideIn(
          index: suggestions.length + 1,
          child: OutlinedButton.icon(
            onPressed: () => onCreate(),
            icon: const Icon(CupertinoIcons.add, size: 18),
            label: const Text('Escolher outra categoria'),
          ),
        ),
      ],
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onCreate});

  final List<(Category, Money)> suggestions;
  final _EditCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < suggestions.length; i++) ...[
          FadeSlideIn(
            index: i + 1,
            child: FinanCard(
              onTap: () => onCreate(preset: suggestions[i].$1),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              radius: AppSpacing.radius,
              child: Row(
                children: [
                  _CategoryBadge(category: suggestions[i].$1),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestions[i].$1.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          'Média ${formatMoney(suggestions[i].$2)}/mês',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                        ),
                      ],
                    ),
                  ),
                  DeltaChip(
                    label: 'Criar',
                    color: scheme.primary,
                    icon: CupertinoIcons.add,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

// ───────────────────────────── Lista ─────────────────────────────

class _BudgetList extends StatelessWidget {
  const _BudgetList({required this.planning, required this.onEdit});

  final BudgetPlanning planning;
  final _EditCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final overview = planning.overview;
    final suggestions = _openSuggestions(planning).take(3).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final cards = [
          for (final item in overview.items)
            _BudgetCard(
              status: item,
              elapsed: overview.elapsed,
              onTap: () => onEdit(status: item),
            ),
        ];
        var order = 1;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            FadeSlideIn(child: _SummaryCard(overview: overview)),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Por categoria',
              subtitle: 'A marca na barra indica o ritmo ideal até hoje',
            ),
            for (var i = 0; i < cards.length; i += columns) ...[
              FadeSlideIn(
                index: order++,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: i + c < cards.length
                              ? cards[i + c]
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const SectionHeader(
                title: 'Sugestões',
                subtitle: 'Categorias com gasto recente e sem limite',
              ),
              _SuggestionList(suggestions: suggestions, onCreate: onEdit),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.overview});

  final BudgetOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final limit = overview.totalLimit;
    final spent = overview.totalSpent;
    final ratio = limit.cents <= 0 ? 0.0 : spent.cents / limit.cents;
    final remaining = Money(limit.cents - spent.cents);
    final state = spent.cents > limit.cents
        ? BudgetState.over
        : ratio > overview.elapsed + 0.05
        ? BudgetState.warning
        : BudgetState.ok;
    final color = _stateColor(state, brightness);
    return Semantics(
      label:
          'Orçado ${formatMoney(limit)}, gasto ${formatMoney(spent)}, '
          '${(ratio * 100).round()}% usado.',
      child: FinanCard(
        child: ExcludeSemantics(
          child: Row(
            children: [
              ProgressRing(
                value: ratio,
                color: color,
                size: 108,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(ratio * 100).round()}%',
                      style: AppTypography.title(scheme.onSurface)
                          .copyWith(fontSize: 24),
                    ),
                    Text(
                      'usado',
                      style: AppTypography.label(
                        scheme.onSurface.withValues(alpha: 0.5),
                      ).copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      remaining.cents >= 0
                          ? 'Disponível no mês'
                          : 'Acima do total',
                      style: AppTypography.label(
                        scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoney(
                        value: Money(remaining.cents.abs()),
                        style: AppTypography.title(
                          remaining.cents >= 0 ? scheme.onSurface : color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatMoney(spent)} de ${formatMoney(limit)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        DeltaChip(
                          label: '${(overview.elapsed * 100).round()}% do mês',
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          icon: CupertinoIcons.clock,
                        ),
                        if (overview.overCount > 0)
                          DeltaChip(
                            label: '${overview.overCount} estourado(s)',
                            color: AppColors.expenseOf(brightness),
                          ),
                        if (overview.warningCount > 0)
                          DeltaChip(
                            label: '${overview.warningCount} em alerta',
                            color: AppColors.warningOf(brightness),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.status,
    required this.elapsed,
    required this.onTap,
  });

  final BudgetStatus status;
  final double elapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final color = _stateColor(status.state, brightness);
    final over = status.state == BudgetState.over;
    final footer = over
        ? 'Estourou ${formatMoney(Money(-status.remaining.cents))}'
        : 'Restam ${formatMoney(status.remaining)} · '
              '${formatMoney(status.dailyAllowance)}/dia';
    final projectionWarning =
        !over &&
        elapsed >= BudgetService.projectionFrom &&
        status.projected.cents > status.limit.cents;
    return Semantics(
      button: true,
      label:
          '${status.category.name}: ${formatMoney(status.spent)} de '
          '${formatMoney(status.limit)}. $footer',
      child: FinanCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        radius: AppSpacing.radius,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CategoryBadge(category: status.category),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          '${formatMoney(status.spent)} de '
                          '${formatMoney(status.limit)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(status.ratio * 100).round()}%',
                    style: AppTypography.headline(color).copyWith(fontSize: 17),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              BudgetBar(ratio: status.ratio, elapsed: elapsed, color: color),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      footer,
                      style: AppTypography.label(
                        over ? color : scheme.onSurface.withValues(alpha: 0.6),
                      ).copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (projectionWarning)
                    Tooltip(
                      message:
                          'Mantendo o ritmo atual, o mês fecha em '
                          '${formatMoney(status.projected)}',
                      child: DeltaChip(
                        label: 'Projeção ${formatMoney(status.projected)}',
                        color: color,
                        icon: CupertinoIcons.arrow_up_right,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de consumo com marcador do ritmo ideal (fração do mês decorrida).
class BudgetBar extends StatelessWidget {
  const BudgetBar({
    required this.ratio,
    required this.elapsed,
    required this.color,
    this.height = 8,
    super.key,
  });

  final double ratio;
  final double elapsed;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height + 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final x = constraints.maxWidth * elapsed.clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedProgressBar(value: ratio, color: color, height: height),
              Positioned(
                left: (x - 1).clamp(0.0, constraints.maxWidth - 2),
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final raw = colorFromHex(
      category.color,
      Theme.of(context).colorScheme.primary,
    );
    final tint = brightness == Brightness.dark
        ? Color.lerp(raw, Colors.white, 0.4)!
        : raw;
    return IconBadge(icon: iconFromName(category.icon), color: tint, size: 38);
  }
}

// ───────────────────────────── Editor ─────────────────────────────

class _BudgetEditor extends StatefulWidget {
  const _BudgetEditor({
    required this.categories,
    required this.suggestions,
    required this.editing,
    this.initialCategory,
    this.initialLimit,
  });

  final List<Category> categories;
  final Map<String, Money> suggestions;
  final bool editing;
  final Category? initialCategory;
  final Money? initialLimit;

  @override
  State<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<_BudgetEditor> {
  late String _categoryId =
      widget.initialCategory?.id ?? widget.categories.first.id;
  late final TextEditingController _amount = TextEditingController(
    text: _plain(widget.initialLimit ?? widget.suggestions[_categoryId]),
  );
  String? _error;

  static String _plain(Money? value) =>
      value == null ? '' : formatMoney(value).replaceFirst('R\$ ', '');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _pickCategory(String id) {
    setState(() {
      _categoryId = id;
      final suggestion = widget.suggestions[id];
      if (!widget.editing && suggestion != null) {
        _amount.text = _plain(suggestion);
      }
    });
  }

  void _submit() {
    final value = tryParseMoney(_amount.text);
    if (value == null || value.cents <= 0) {
      setState(() => _error = 'Informe um valor maior que zero.');
      return;
    }
    Navigator.pop(context, _EditorResult.save(_categoryId, value));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suggestion = widget.suggestions[_categoryId];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.editing ? 'Editar orçamento' : 'Novo orçamento',
            style: AppTypography.headline(scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              for (final category in widget.categories)
                DropdownMenuItem(
                  value: category.id,
                  child: Row(
                    children: [
                      Icon(iconFromName(category.icon), size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: widget.editing
                ? null
                : (value) {
                    if (value != null) _pickCategory(value);
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _amount,
            autofocus: widget.editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Limite mensal',
              prefixText: 'R\$ ',
              errorText: _error,
            ),
          ),
          if (suggestion != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Média de ${GetBudgetPlanning.historyMonths} meses:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                ActionChip(
                  label: Text(formatMoney(suggestion)),
                  onPressed: () => _amount.text = _plain(suggestion),
                ),
                ActionChip(
                  label: const Text('−10%'),
                  onPressed: () => _amount.text = _plain(
                    Money((suggestion.cents * 0.9 / 1000).round() * 1000),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: _submit, child: const Text('Salvar')),
          if (widget.editing) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () =>
                  Navigator.pop(context, const _EditorResult.delete()),
              child: const Text('Excluir orçamento'),
            ),
          ],
        ],
      ),
    );
  }
}
