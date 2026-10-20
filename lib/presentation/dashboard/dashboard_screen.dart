import 'package:finan/app/app_scope.dart';
import 'package:finan/application/budgets/budget_actions.dart';
import 'package:finan/application/dashboard/dashboard_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/budget_service.dart';
import 'package:finan/domain/services/dashboard_insight_service.dart';
import 'package:finan/domain/services/financial_health_service.dart';
import 'package:finan/presentation/dashboard/dashboard_charts_view.dart';
import 'package:finan/presentation/budgets/budgets_screen.dart';
import 'package:finan/presentation/emergency/emergency_screen.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/goals/goal_progress.dart';
import 'package:finan/presentation/goals/goals_screen.dart';
import 'package:finan/presentation/provisions/provisions_screen.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _periodPresets = <DashboardPeriodFilter>[
  DashboardPeriodFilter.currentMonth,
  DashboardPeriodFilter.previousMonth,
  DashboardPeriodFilter.last3Months,
  DashboardPeriodFilter.last6Months,
  DashboardPeriodFilter.yearToDate,
];

const _twoColumnWidth = 980.0;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.refreshTick,
    required this.onShowTransactions,
    required this.onShowBudgets,
    super.key,
  });

  final int refreshTick;
  final VoidCallback onShowTransactions;
  final VoidCallback onShowBudgets;

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  static const _insights = DashboardInsightService();
  static const _health = FinancialHealthService();

  DashboardSummary? _summary;
  List<DashboardInsight> _insightItems = const [];
  List<GoalProgress> _goalStats = const [];
  List<Transaction> _recent = const [];
  List<Provision> _upcoming = const [];
  BudgetPlanning? _budgets;
  Map<String, Category> _categories = const {};
  DashboardPeriodFilter _period = DashboardPeriodFilter.currentMonth;
  Object? _error;
  bool _loading = true;
  bool _masked = false;
  bool _marketSynced = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _load(silent: _summary != null);
    }
  }

  Future<void> _load({bool silent = false}) async {
    final request = ++_request;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final summary = await scope.graph.getDashboardSummary(
        userId,
        periodFilter: _period,
      );
      final goals = await scope.graph.finance.listGoals(userId);
      final recent = await scope.graph.transactions.list(
        TransactionQuery(
          userId: userId,
          fromInclusive: summary.periodStart,
          toInclusive: summary.periodEndInclusive,
          limit: 6,
        ),
      );
      final provisions = await scope.graph.finance.listProvisions(userId);
      final categories = await scope.graph.categories.listByUser(userId);
      final budgets = await scope.graph.getBudgetPlanning(userId);
      if (!mounted || request != _request) return;
      final activeGoals = [
        for (final goal in goals)
          if (goal.isActive) goal,
      ];
      final goalStats = [
        for (final goal in activeGoals)
          GoalProgress.evaluate(
            summary: summary,
            goal: goal,
            calculate: scope.graph.calculateGoalProjection,
          ),
      ];
      final onTrack = goalStats.where((item) => item.onTrack).length;
      final horizon = LocalDate.fromDateTime(DateTime.now()).addDays(30);
      setState(() {
        _summary = summary;
        _goalStats = goalStats;
        _insightItems = _insights.build(
          summary: summary,
          activeGoals: activeGoals.length,
          goalsOnTrack: onTrack,
        );
        _recent = recent.items;
        _budgets = budgets;
        _upcoming = [
          for (final provision in provisions)
            if (provision.status.isOpen && provision.dueDate <= horizon)
              provision,
        ]..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        _categories = {
          for (final category in categories) category.id: category,
        };
        _loading = false;
        _error = null;
      });
      if (!_marketSynced) {
        _marketSynced = true;
        _syncMarket();
      }
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Atualiza o CDI em segundo plano; sem rede, vai de cache.
  Future<void> _syncMarket() async {
    try {
      final scope = AppScope.of(context);
      final changed = await scope.graph.syncMarketData(scope.session.user.id);
      final indexed =
          _summary?.investmentYield != null ||
          (await scope.graph.investmentYields.listByUser(scope.session.user.id))
              .isNotEmpty;
      if ((changed || indexed) && mounted) await _load(silent: true);
    } catch (_) {}
  }

  Future<void> _selectPeriod(DashboardPeriodFilter period) async {
    if (period.kind == DashboardPeriodKind.custom) {
      await _pickCustomPeriod();
      return;
    }
    if (period.kind == _period.kind &&
        _period.kind != DashboardPeriodKind.custom) {
      return;
    }
    setState(() => _period = period);
    await _load(silent: _summary != null);
  }

  Future<void> _pickCustomPeriod() async {
    final summary = _summary;
    final initialStart = summary?.periodStart ?? _period.customStart;
    final initialEnd =
        summary?.periodEndInclusive ?? _period.customEndInclusive;
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initialStart != null && initialEnd != null
          ? DateTimeRange(
              start: DateTime(
                initialStart.year,
                initialStart.month,
                initialStart.day,
              ),
              end: DateTime(initialEnd.year, initialEnd.month, initialEnd.day),
            )
          : null,
      helpText: 'Período personalizado',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _period = DashboardPeriodFilter.custom(
        start: LocalDate.fromDateTime(picked.start),
        endInclusive: LocalDate.fromDateTime(picked.end),
      );
    });
    await _load(silent: _summary != null);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    final salute = hour < 12
        ? 'Bom dia'
        : hour < 18
        ? 'Boa tarde'
        : 'Boa noite';
    final name = AppScope.of(context).session.user.name.trim();
    final first = name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
    return first.isEmpty ? salute : '$salute, $first';
  }

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen))
        .then((_) {
          if (mounted) _load(silent: true);
        });
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return FinanPage(
      title: _greeting(),
      subtitle: summary == null
          ? null
          : 'Resumo de ${formatPeriod(summary.periodStart, summary.periodEndExclusive)}',
      trailing: summary == null
          ? null
          : IconButton(
              tooltip: _masked ? 'Mostrar valores' : 'Ocultar valores',
              onPressed: () => setState(() => _masked = !_masked),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  _masked ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                  key: ValueKey(_masked),
                ),
              ),
            ),
      body: _loading && summary == null
          ? const LoadingSkeleton()
          : _error != null && summary == null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: LayoutBuilder(
                builder: (context, constraints) => _content(
                  context,
                  summary,
                  wide: constraints.maxWidth >= _twoColumnWidth,
                ),
              ),
            ),
    );
  }

  Widget _content(
    BuildContext context,
    DashboardSummary? summary, {
    required bool wide,
  }) {
    final bottom = AppSpacing.xl + MediaQuery.paddingOf(context).bottom;
    final filters = _PeriodFilters(
      selected: _period,
      onSelected: _selectPeriod,
    );
    if (summary == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [filters],
      );
    }
    final masked = _masked;
    final hero = _HeroCard(summary: summary, masked: masked);
    final kpis = _KpiGrid(
      summary: summary,
      period: _period,
      masked: masked,
      columns: wide ? 4 : 2,
    );
    final health = _HealthCard(health: _health.evaluate(summary));
    final yieldSummary = summary.investmentYield;
    final yieldCard = yieldSummary == null
        ? null
        : _YieldCard(summary: yieldSummary, masked: masked);
    final emergency = _EmergencyCard(
      emergency: summary.emergency,
      masked: masked,
      onAdjust: () => _push(const EmergencyScreen()),
    );
    final upcoming = _UpcomingSection(
      items: _upcoming,
      masked: masked,
      onShowAll: () => _push(const ProvisionsScreen()),
    );
    final insights = _InsightsSection(
      insights: _insightItems,
      horizontal: !wide,
    );
    final goals = _GoalsSection(
      stats: _goalStats,
      masked: masked,
      onOpen: () => _push(const GoalsScreen()),
    );
    final charts = DashboardChartsView(charts: summary.charts);
    final recent = _RecentSection(
      items: _recent,
      categories: _categories,
      masked: masked,
      onShowAll: widget.onShowTransactions,
    );

    final budgetPlanning = _budgets;
    final budgets = budgetPlanning == null
        ? null
        : _BudgetsSection(
            planning: budgetPlanning,
            masked: masked,
            onOpen: widget.onShowBudgets,
          );

    const gap = SizedBox(height: AppSpacing.lg);
    var order = 0;
    Widget step(Widget child) => FadeSlideIn(index: order++, child: child);

    if (!wide) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          bottom,
        ),
        children: [
          step(filters),
          const SizedBox(height: AppSpacing.md),
          step(hero),
          const SizedBox(height: AppSpacing.md),
          step(kpis),
          if (budgets != null) ...[gap, step(budgets)],
          gap,
          step(health),
          const SizedBox(height: AppSpacing.md),
          step(emergency),
          if (yieldCard != null) ...[
            const SizedBox(height: AppSpacing.md),
            step(yieldCard),
          ],
          if (_upcoming.isNotEmpty) ...[gap, step(upcoming)],
          if (_insightItems.isNotEmpty) ...[gap, step(insights)],
          gap,
          step(goals),
          gap,
          step(recent),
          gap,
          step(charts),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        bottom,
      ),
      children: [
        step(filters),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  step(hero),
                  const SizedBox(height: AppSpacing.md),
                  step(kpis),
                  if (budgets != null) ...[gap, step(budgets)],
                  gap,
                  step(recent),
                  gap,
                  step(charts),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  step(health),
                  const SizedBox(height: AppSpacing.md),
                  step(emergency),
                  if (yieldCard != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    step(yieldCard),
                  ],
                  if (_upcoming.isNotEmpty) ...[gap, step(upcoming)],
                  gap,
                  step(goals),
                  if (_insightItems.isNotEmpty) ...[gap, step(insights)],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _maskedMoney(Money value, bool masked) =>
    masked ? 'R\$ ••••' : formatMoney(value);

/// Variação percentual entre dois valores; nulo quando não há base.
double? _change(int previous, int current) {
  if (previous == 0) return null;
  return (current - previous) / previous.abs();
}

String _percent(double value) {
  final pct = (value * 100).abs();
  final text = pct >= 100 ? pct.round().toString() : pct.toStringAsFixed(1);
  return '${value >= 0 ? '+' : '−'}${text.replaceAll('.', ',')}%';
}

// ───────────────────────────── Filtros ─────────────────────────────

class _PeriodFilters extends StatelessWidget {
  const _PeriodFilters({required this.selected, required this.onSelected});

  final DashboardPeriodFilter selected;
  final ValueChanged<DashboardPeriodFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = [
      ..._periodPresets,
      const DashboardPeriodFilter(kind: DashboardPeriodKind.custom),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in options) ...[
            _PeriodPill(
              label: period.kind == DashboardPeriodKind.custom
                  ? 'Personalizado'
                  : period.label,
              icon: period.kind == DashboardPeriodKind.custom
                  ? CupertinoIcons.calendar
                  : null,
              selected: selected.kind == period.kind,
              onTap: () => onSelected(period),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

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
              Text(label, style: AppTypography.label(fg)),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Destaque ─────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.summary, required this.masked});

  final DashboardSummary summary;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    const onHero = Colors.white;
    final soft = onHero.withValues(alpha: 0.72);
    final worth = summary.charts.netWorth;
    final change = worth.length >= 2
        ? _change(worth[worth.length - 2].amount.cents, worth.last.amount.cents)
        : null;
    final positive = (change ?? 0) >= 0;
    return Semantics(
      label: 'Patrimônio líquido ${_maskedMoney(summary.netWorth, masked)}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg + 4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isLight ? AppColors.heroLight : AppColors.heroDark,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: isLight ? 0.32 : 0.4),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Brilhos decorativos.
            Positioned(
              right: -60,
              top: -80,
              child: _Glow(size: 220, alpha: 0.12),
            ),
            Positioned(
              left: -40,
              bottom: -90,
              child: _Glow(size: 180, alpha: 0.07),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 92,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: 0.55,
                  child: Sparkline(
                    values: [for (final point in worth) point.amount.cents],
                    color: onHero,
                    height: 64,
                  ),
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
                      Icon(
                        CupertinoIcons.chart_bar_alt_fill,
                        size: 16,
                        color: soft,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Patrimônio líquido',
                        style: AppTypography.label(soft),
                      ),
                      const Spacer(),
                      if (change != null)
                        DeltaChip(
                          label: '${_percent(change)} no mês',
                          color: onHero,
                          icon: positive
                              ? CupertinoIcons.arrow_up_right
                              : CupertinoIcons.arrow_down_right,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoney(
                        value: summary.netWorth,
                        masked: masked,
                        style: AppTypography.display(onHero)
                            .copyWith(fontSize: 40),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Estimado no fim do período: '
                    '${_maskedMoney(summary.projectedBalance, masked)}',
                    style: AppTypography.label(soft)
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 76),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStat(
                          icon: CupertinoIcons.creditcard,
                          label: 'Contas',
                          value: summary.totalAccounts,
                          masked: masked,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _HeroStat(
                          icon: CupertinoIcons.chart_pie,
                          label: summary.investmentYield == null
                              ? 'Investimentos'
                              : 'Investimentos (líq.)',
                          value: summary.totalInvestments,
                          masked: masked,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _HeroStat(
                          icon: CupertinoIcons.rectangle_stack,
                          label: 'Cartões',
                          value: summary.creditCardDebt,
                          masked: masked,
                        ),
                      ),
                    ],
                  ),
                  if (summary.investmentGain.cents > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Rendimento de resgates '
                      '${_maskedMoney(summary.investmentGain, masked)} '
                      '(não entra em receitas).',
                      style: AppTypography.label(soft)
                          .copyWith(fontWeight: FontWeight.w500, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.alpha});

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

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.masked,
  });

  final IconData icon;
  final String label;
  final Money value;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final soft = Colors.white.withValues(alpha: 0.7);
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
            child: AnimatedMoney(
              value: value,
              masked: masked,
              style: AppTypography.label(Colors.white)
                  .copyWith(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── KPIs ─────────────────────────────

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.summary,
    required this.period,
    required this.masked,
    required this.columns,
  });

  final DashboardSummary summary;
  final DashboardPeriodFilter period;
  final bool masked;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final income = AppColors.incomeOf(brightness);
    final expense = AppColors.expenseOf(brightness);
    final info = AppColors.infoOf(brightness);
    // Comparação mês a mês só faz sentido no recorte do mês atual.
    final months = summary.charts.months;
    final compare =
        period.kind == DashboardPeriodKind.currentMonth && months.length >= 2;
    final prev = compare ? months[months.length - 2] : null;
    final savingsPositive = summary.monthlySavings.cents >= 0;
    final tiles = [
      _KpiTile(
        icon: CupertinoIcons.arrow_down_left,
        color: income,
        label: 'Receitas',
        value: _KpiValue.money(summary.monthlyIncome),
        change: prev == null
            ? null
            : _change(prev.income.cents, summary.monthlyIncome.cents),
        masked: masked,
      ),
      _KpiTile(
        icon: CupertinoIcons.arrow_up_right,
        color: expense,
        label: 'Despesas',
        value: _KpiValue.money(summary.monthlyExpenses),
        change: prev == null
            ? null
            : _change(prev.expense.cents, summary.monthlyExpenses.cents),
        higherIsBetter: false,
        masked: masked,
      ),
      _KpiTile(
        icon: CupertinoIcons.money_dollar_circle,
        color: savingsPositive ? income : expense,
        label: 'Economia',
        value: _KpiValue.money(summary.monthlySavings),
        caption: '${formatRate(summary.savingsRate)} da receita',
        masked: masked,
      ),
      _KpiTile(
        icon: CupertinoIcons.chart_bar_alt_fill,
        color: info,
        label: 'Taxa de aporte',
        value: _KpiValue.rate(summary.investmentRate),
        caption: 'da receita investida',
        masked: masked,
      ),
    ];
    final rows = <Widget>[];
    for (var index = 0; index < tiles.length; index += columns) {
      if (index > 0) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var col = 0; col < columns; col++) ...[
                if (col > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: index + col < tiles.length
                      ? tiles[index + col]
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _KpiValue {
  const _KpiValue.money(Money this.money) : rate = null;
  const _KpiValue.rate(double this.rate) : money = null;

  final Money? money;
  final double? rate;
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.masked,
    this.change,
    this.caption,
    this.higherIsBetter = true,
  });

  final IconData icon;
  final Color color;
  final String label;
  final _KpiValue value;
  final bool masked;
  final double? change;
  final String? caption;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final style = AppTypography.headline(scheme.onSurface);
    final money = value.money;
    final change = this.change;
    final good = change == null || (change >= 0) == higherIsBetter;
    final spoken = money != null
        ? _maskedMoney(money, masked)
        : formatRate(value.rate ?? 0);
    return Semantics(
      label: '$label $spoken',
      child: FinanCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        radius: AppSpacing.radius,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(icon: icon, color: color, size: 32),
                  const Spacer(),
                  if (change != null && change.abs() >= 0.001)
                    DeltaChip(
                      label: _percent(change),
                      color: good
                          ? AppColors.incomeOf(brightness)
                          : AppColors.expenseOf(brightness),
                    ),
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
                    ? AnimatedMoney(value: money, masked: masked, style: style)
                    : TweenAnimationBuilder<double>(
                        tween: Tween(end: value.rate ?? 0),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (context, rate, _) =>
                            Text(formatRate(rate), style: style),
                      ),
              ),
              if (caption != null || change != null) ...[
                const SizedBox(height: 2),
                Text(
                  caption ?? 'vs mês anterior',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Saúde ─────────────────────────────

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.health});

  final FinancialHealth health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final color = switch (health.level) {
      FinancialHealthLevel.excellent ||
      FinancialHealthLevel.good => AppColors.incomeOf(brightness),
      FinancialHealthLevel.attention => AppColors.warningOf(brightness),
      FinancialHealthLevel.critical => AppColors.expenseOf(brightness),
    };
    return Semantics(
      label: 'Saúde financeira ${health.score} de 100, ${health.label}',
      child: FinanCard(
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Saúde financeira',
                    style: AppTypography.headline(scheme.onSurface)
                        .copyWith(fontSize: 17),
                  ),
                  const Spacer(),
                  DeltaChip(label: health.label, color: color),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  ProgressRing(
                    value: health.score / 100,
                    color: color,
                    size: 104,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: health.score.toDouble()),
                      duration: const Duration(milliseconds: 1300),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            value.round().toString(),
                            style: AppTypography.title(scheme.onSurface),
                          ),
                          Text(
                            'de 100',
                            style: AppTypography.label(
                              scheme.onSurface.withValues(alpha: 0.5),
                            ).copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      children: [
                        for (final pillar in health.pillars) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  pillar.label,
                                  style: AppTypography.label(
                                    scheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                              Text(
                                '${pillar.points.round()}/${pillar.maxPoints.round()}',
                                style: AppTypography.label(
                                  scheme.onSurface.withValues(alpha: 0.5),
                                ).copyWith(fontSize: 11.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          AnimatedProgressBar(
                            value: pillar.ratio,
                            color: color,
                            height: 5,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                      ],
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

// ───────────────────────────── Reserva ─────────────────────────────

class _EmergencyCard extends StatelessWidget {
  const _EmergencyCard({
    required this.emergency,
    required this.masked,
    required this.onAdjust,
  });

  final EmergencyOverview emergency;
  final bool masked;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final coverage = emergency.coverage.clamp(0.0, 1.0);
    final noReference = emergency.averageEssential.cents <= 0;
    final color = emergency.onTarget
        ? AppColors.incomeOf(brightness)
        : AppColors.warningOf(brightness);
    final status = noReference
        ? 'Sem despesa essencial de referência ainda.'
        : emergency.onTarget
        ? 'Reserva dentro da meta.'
        : 'Faltam ${_maskedMoney(emergency.gap, masked)} para a meta.';
    return FinanCard(
      onTap: onAdjust,
      child: Row(
        children: [
          ProgressRing(
            value: coverage,
            color: color,
            size: 76,
            stroke: 8,
            child: Icon(CupertinoIcons.shield_fill, color: color, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Reserva de emergência',
                        style: AppTypography.label(
                          scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Text(
                      '${(coverage * 100).round()}%',
                      style: AppTypography.label(color),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${emergency.runwayMonths.toStringAsFixed(1).replaceAll('.', ',')} '
                  'de ${emergency.targetMonths} meses',
                  style: AppTypography.headline(scheme.onSurface)
                      .copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_maskedMoney(emergency.reserve, masked)} de '
                  '${_maskedMoney(emergency.targetAmount, masked)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: scheme.onSurface.withValues(alpha: 0.35),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Vencimentos ─────────────────────────────

class _UpcomingSection extends StatelessWidget {
  const _UpcomingSection({
    required this.items,
    required this.masked,
    required this.onShowAll,
  });

  final List<Provision> items;
  final bool masked;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final today = LocalDate.fromDateTime(DateTime.now());
    var due = 0;
    for (final item in items) {
      if (item.type == TransactionType.expense) due += item.amount.cents;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Próximos vencimentos',
          subtitle: due > 0
              ? '${_maskedMoney(Money(due), masked)} a pagar em 30 dias'
              : 'Próximos 30 dias',
          action: 'Ver todos',
          onAction: onShowAll,
        ),
        FinanCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final item in items.take(5))
                _UpcomingTile(
                  provision: item,
                  today: today,
                  masked: masked,
                  brightness: brightness,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({
    required this.provision,
    required this.today,
    required this.masked,
    required this.brightness,
  });

  final Provision provision;
  final LocalDate today;
  final bool masked;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final income = provision.type == TransactionType.income;
    final days = DateTime.utc(
      provision.dueDate.year,
      provision.dueDate.month,
      provision.dueDate.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final late = days < 0;
    final when = switch (days) {
      0 => 'Vence hoje',
      1 => 'Amanhã',
      < 0 => 'Atrasado há ${-days} ${-days == 1 ? 'dia' : 'dias'}',
      _ => 'Em $days dias · ${formatLocalDate(provision.dueDate)}',
    };
    final tone = late
        ? AppColors.expenseOf(brightness)
        : days <= 3
        ? AppColors.warningOf(brightness)
        : scheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconBadge(
            icon: income
                ? CupertinoIcons.arrow_down_left
                : CupertinoIcons.calendar_badge_minus,
            color: income
                ? AppColors.incomeOf(brightness)
                : (late ? AppColors.expenseOf(brightness) : scheme.primary),
            size: 34,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provision.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  when,
                  style: AppTypography.label(tone)
                      .copyWith(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Text(
            masked
                ? 'R\$ ••••'
                : '${income ? '+' : '−'}${formatMoney(provision.amount)}',
            style: AppTypography.label(
              income ? AppColors.incomeOf(brightness) : scheme.onSurface,
            ).copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Insights ─────────────────────────────

class _InsightsSection extends StatelessWidget {
  const _InsightsSection({required this.insights, required this.horizontal});

  final List<DashboardInsight> insights;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Insights',
          subtitle: 'O que chama atenção no período',
        ),
        if (horizontal)
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: insights.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) => SizedBox(
                width: 260,
                child: _InsightTile(insight: insights[index]),
              ),
            ),
          )
        else
          for (final insight in insights) ...[
            _InsightTile(insight: insight),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight});

  final DashboardInsight insight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final accent = switch (insight.tone) {
      DashboardInsightTone.positive => AppColors.incomeOf(brightness),
      DashboardInsightTone.warning => AppColors.expenseOf(brightness),
      DashboardInsightTone.neutral => AppColors.infoOf(brightness),
    };
    final icon = switch (insight.tone) {
      DashboardInsightTone.positive => CupertinoIcons.checkmark_seal_fill,
      DashboardInsightTone.warning =>
        CupertinoIcons.exclamationmark_triangle_fill,
      DashboardInsightTone.neutral => CupertinoIcons.lightbulb_fill,
    };
    final base = FinanCard.decoration(context, radius: AppSpacing.radius);
    return DecoratedBox(
      decoration: base.copyWith(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accent.withValues(alpha: 0.10), base.color!),
            base.color!,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: accent, size: 32),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    style: AppTypography.label(scheme.onSurface)
                        .copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    insight.detail,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Metas ─────────────────────────────

class _GoalsSection extends StatelessWidget {
  const _GoalsSection({
    required this.stats,
    required this.masked,
    required this.onOpen,
  });

  final List<GoalProgress> stats;
  final bool masked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final reached = stats.where((item) => item.progress >= 1).length;
    final onTrack = stats.where((item) => item.onTrack).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Metas',
          subtitle: stats.isEmpty
              ? null
              : '$reached alcançada(s) · $onTrack no ritmo',
          action: stats.isEmpty ? 'Criar meta' : 'Ver metas',
          onAction: onOpen,
        ),
        if (stats.isEmpty)
          FinanCard(
            onTap: onOpen,
            child: Row(
              children: [
                IconBadge(
                  icon: CupertinoIcons.flag_fill,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Defina um alvo para acompanhar progresso e estimativa.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        else
          for (final stat in stats) ...[
            _GoalStatCard(stat: stat, masked: masked, onTap: onOpen),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _GoalStatCard extends StatelessWidget {
  const _GoalStatCard({
    required this.stat,
    required this.masked,
    required this.onTap,
  });

  final GoalProgress stat;
  final bool masked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final months = stat.projection.monthsToTarget;
    final estimate = switch (months) {
      0 => 'Meta alcançada',
      null when stat.monthlyPace.cents <= 0 =>
        'Sem economia recente para projetar',
      null => 'Nesse ritmo, não fecha em 100 anos',
      1 => 'Nesse ritmo: 1 mês',
      _ => 'Nesse ritmo: $months meses',
    };
    final planned = stat.plannedProjection;
    final plannedMonths = planned?.monthsToTarget;
    final plannedLine = planned == null
        ? null
        : switch (plannedMonths) {
            0 => 'Com aporte planejado: já alcançada',
            null => 'Com aporte planejado: não fecha',
            1 => 'Com aporte planejado: 1 mês',
            _ => 'Com aporte planejado: $plannedMonths meses',
          };
    final color = stat.progress >= 1 || stat.onTrack
        ? AppColors.incomeOf(brightness)
        : AppColors.warningOf(brightness);
    return Semantics(
      label:
          '${stat.goal.name}. ${(stat.progress * 100).round()}%. '
          'Alvo ${_maskedMoney(stat.goal.targetAmount, masked)}. $estimate.',
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
                  IconBadge(
                    icon: CupertinoIcons.flag_fill,
                    color: color,
                    size: 30,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      stat.goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${(stat.progress * 100).round()}%',
                    style: AppTypography.headline(color).copyWith(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AnimatedProgressBar(value: stat.progress, color: color),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_maskedMoney(stat.present, masked)} de '
                      '${_maskedMoney(stat.goal.targetAmount, masked)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    estimate,
                    style: AppTypography.label(
                      scheme.onSurface.withValues(alpha: 0.6),
                    ).copyWith(fontSize: 11.5),
                  ),
                ],
              ),
              if (plannedLine != null) ...[
                const SizedBox(height: 2),
                Text(
                  plannedLine,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Lançamentos ─────────────────────────────

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.items,
    required this.categories,
    required this.masked,
    required this.onShowAll,
  });

  final List<Transaction> items;
  final Map<String, Category> categories;
  final bool masked;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Últimos lançamentos',
          action: 'Ver extrato',
          onAction: onShowAll,
        ),
        FinanCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      IconBadge(
                        icon: CupertinoIcons.tray,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Text('Nenhum lançamento neste período.'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        Divider(
                          indent: 64,
                          endIndent: AppSpacing.md,
                          color: Theme.of(context).colorScheme.outline
                              .withValues(alpha: 0.6),
                        ),
                      _RecentTile(
                        transaction: items[i],
                        category: categories[items[i].categoryId],
                        masked: masked,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.transaction,
    required this.category,
    required this.masked,
  });

  final Transaction transaction;
  final Category? category;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final title = transaction.description ?? transaction.type.label;
    final amount = signedAmount(transaction.type, transaction.amount);
    final incoming = amount.startsWith('+');
    final fallback = switch (transaction.type) {
      TransactionType.transfer => CupertinoIcons.arrow_right_arrow_left,
      TransactionType.creditCardPayment => CupertinoIcons.creditcard,
      TransactionType.investmentContribution ||
      TransactionType.investmentWithdrawal ||
      TransactionType.investmentIncome ||
      TransactionType.investmentLoss => CupertinoIcons.chart_pie,
      TransactionType.income => CupertinoIcons.arrow_down_left,
      TransactionType.expense => CupertinoIcons.bag,
    };
    final raw = colorFromHex(
      category?.color,
      incoming ? AppColors.incomeOf(brightness) : scheme.primary,
    );
    // Cores de categoria são escuras; clareia no tema escuro para contraste.
    final tint = brightness == Brightness.dark
        ? Color.lerp(raw, Colors.white, 0.4)!
        : raw;
    final icon = category?.icon == null
        ? fallback
        : iconFromName(category!.icon);
    final meta = [
      ?category?.name,
      formatLocalDate(transaction.transactionDate),
      if (transaction.status != TransactionStatus.confirmed)
        transaction.status.label,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      child: Row(
        children: [
          IconBadge(icon: icon, color: tint, size: 38),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            masked ? 'R\$ ••••' : amount,
            style: AppTypography.label(
              incoming ? AppColors.incomeOf(brightness) : scheme.onSurface,
            ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Orçamentos ─────────────────────────────

class _BudgetsSection extends StatelessWidget {
  const _BudgetsSection({
    required this.planning,
    required this.masked,
    required this.onOpen,
  });

  final BudgetPlanning planning;
  final bool masked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overview = planning.overview;
    if (overview.isEmpty) {
      final hints = planning.suggestions.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Orçamentos do mês'),
          FinanCard(
            onTap: onOpen,
            child: Row(
              children: [
                IconBadge(
                  icon: CupertinoIcons.chart_pie_fill,
                  color: scheme.primary,
                  size: 40,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Defina limites por categoria',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hints > 0
                            ? 'Temos $hints sugestões com base no seu histórico.'
                            : 'Acompanhe quanto ainda pode gastar no mês.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: scheme.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final alerts = overview.overCount + overview.warningCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Orçamentos do mês',
          subtitle:
              '${_maskedMoney(overview.totalSpent, masked)} de '
              '${_maskedMoney(overview.totalLimit, masked)}'
              '${alerts > 0 ? ' · $alerts em alerta' : ''}',
          action: 'Ver todos',
          onAction: onOpen,
        ),
        FinanCard(
          onTap: onOpen,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            children: [
              for (final item in overview.items.take(4))
                _BudgetRow(
                  status: item,
                  elapsed: overview.elapsed,
                  masked: masked,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.status,
    required this.elapsed,
    required this.masked,
  });

  final BudgetStatus status;
  final double elapsed;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final color = switch (status.state) {
      BudgetState.ok => AppColors.incomeOf(brightness),
      BudgetState.warning => AppColors.warningOf(brightness),
      BudgetState.over => AppColors.expenseOf(brightness),
    };
    final raw = colorFromHex(status.category.color, scheme.primary);
    final tint = brightness == Brightness.dark
        ? Color.lerp(raw, Colors.white, 0.4)!
        : raw;
    final remaining = status.remaining;
    final detail = remaining.cents < 0
        ? 'Estourou ${_maskedMoney(Money(-remaining.cents), masked)}'
        : 'Restam ${_maskedMoney(remaining, masked)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          IconBadge(
            icon: iconFromName(status.category.icon),
            color: tint,
            size: 34,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        status.category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      detail,
                      style: AppTypography.label(
                        remaining.cents < 0
                            ? color
                            : scheme.onSurface.withValues(alpha: 0.55),
                      ).copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                BudgetBar(
                  ratio: status.ratio,
                  elapsed: elapsed,
                  color: color,
                  height: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 40,
            child: Text(
              '${(status.ratio * 100).round()}%',
              textAlign: TextAlign.right,
              style: AppTypography.label(color).copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Rendimento ─────────────────────────────

class _YieldCard extends StatelessWidget {
  const _YieldCard({required this.summary, required this.masked});

  final YieldSummary summary;
  final bool masked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final income = AppColors.incomeOf(brightness);
    final open = summary.count > 0;
    final realized = summary.realizedGain;
    // Sem indexado em aberto
    final gain = open ? summary.grossGain : realized;
    final ratio = !open || summary.principal.cents <= 0
        ? 0.0
        : gain.cents / summary.principal.cents;
    final cdi = summary.cdiAnnualPercent;
    return Semantics(
      label:
          'Rendimento estimado ${_maskedMoney(gain, masked)}, '
          'impostos ${_maskedMoney(summary.taxes, masked)}',
      child: FinanCard(
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: CupertinoIcons.graph_square_fill,
                    color: income,
                    size: 34,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      open ? 'Rendimento estimado' : 'Rendimento real',
                      style: AppTypography.label(
                        scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  if (cdi != null)
                    DeltaChip(
                      label:
                          'CDI ${cdi.toStringAsFixed(2).replaceAll('.', ',')}% a.a.',
                      color: scheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoney(
                        value: gain,
                        masked: masked,
                        style: AppTypography.headline(income),
                      ),
                    ),
                  ),
                  if (open)
                    Text(
                      '${(ratio * 100).toStringAsFixed(2).replaceAll('.', ',')}% bruto',
                      style: AppTypography.label(income).copyWith(fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (open)
                Text(
                  'IR + IOF ${_maskedMoney(summary.taxes, masked)} · '
                  'líquido ${_maskedMoney(summary.netGain, masked)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (!realized.isZero)
                Text(
                  open
                      ? 'Real em resgates totais: '
                            '${realized.cents >= 0 ? '+' : ''}${_maskedMoney(realized, masked)}'
                      : 'De investimentos resgatados por completo',
                  style: AppTypography.label(
                    realized.cents >= 0
                        ? income
                        : AppColors.expenseOf(brightness),
                  ).copyWith(fontSize: 12),
                ),
              if (open)
                Text(
                  '${summary.count} '
                  '${summary.count == 1 ? 'investimento indexado' : 'investimentos indexados'}'
                  ' · valores aproximados',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
