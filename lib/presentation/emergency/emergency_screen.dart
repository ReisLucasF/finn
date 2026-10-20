import 'package:finan/app/app_scope.dart';
import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/emergency_fund_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/finan_widgets.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final TextEditingController _months = TextEditingController(text: '6');
  final EmergencyFundService _service = const EmergencyFundService();
  final InvestmentCategoryService _investmentsService =
      const InvestmentCategoryService();
  List<Category> _categories = const [];
  Set<String> _selected = {};
  Money _average = Money.zero;
  Money _accounts = Money.zero;
  Money _investments = Money.zero;
  bool _loading = true;
  String? _error;

  Money get _reserve => Money(_accounts.cents + _investments.cents);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _months.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final settings = await scope.graph.finance.findEmergency(userId);
      final categories = [
        for (final category in await scope.graph.categories.listByUser(
          userId,
          includeInactive: false,
        ))
          if (category.deletedAt == null &&
              (category.type == CategoryType.expense ||
                  category.type == CategoryType.both))
            category,
      ]..sort((a, b) => a.name.compareTo(b.name));
      final selected = _service
          .resolveEssentialCategoryIds(
            saved: settings?.essentialCategoryIds,
            expenseCategories: categories,
          )
          .toSet();
      final user = scope.session.user;
      final today = scope.graph.clock.today();
      final current = FinancialPeriod.containing(
        today,
        user.financialMonthStart,
      );
      final expenses = <Money>[];
      var cursor = current.startInclusive.addDays(-1);
      for (var index = 0; index < 3; index++) {
        final period = FinancialPeriod.containing(
          cursor,
          user.financialMonthStart,
        );
        expenses.add(
          await scope.graph.transactions.sumConfirmedAmount(
            userId: userId,
            type: TransactionType.expense,
            fromInclusive: period.startInclusive,
            toExclusive: period.endExclusive,
            categoryIds: selected,
          ),
        );
        cursor = period.startInclusive.addDays(-1);
      }
      final parts = await scope.graph.transactions.balancePartsForUser(userId);
      var accountsCents = 0;
      for (final part in parts) {
        accountsCents +=
            part.initialBalance.cents + part.confirmedEntries.cents;
      }
      final investments = await scope.graph.finance.listInvestments(userId);
      final cashEvents = await scope.graph.transactions.listInvestmentCash(
        userId,
      );
      final investedCents = _investmentsService
          .totalInvested(
            registeredValues: [
              for (final investment in investments) investment.currentValue,
            ],
            allCashEvents: cashEvents,
          )
          .cents;
      if (!mounted) return;
      setState(() {
        _months.text = '${settings?.targetMonths ?? 6}';
        _categories = categories;
        _selected = selected;
        _average = _service.averageMonthly(expenses);
        _accounts = Money(accountsCents);
        _investments = Money(investedCents);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _recalculate() async {
    final scope = AppScope.of(context);
    final userId = scope.session.user.id;
    final user = scope.session.user;
    final today = scope.graph.clock.today();
    final current = FinancialPeriod.containing(today, user.financialMonthStart);
    final expenses = <Money>[];
    var cursor = current.startInclusive.addDays(-1);
    for (var index = 0; index < 3; index++) {
      final period = FinancialPeriod.containing(
        cursor,
        user.financialMonthStart,
      );
      expenses.add(
        await scope.graph.transactions.sumConfirmedAmount(
          userId: userId,
          type: TransactionType.expense,
          fromInclusive: period.startInclusive,
          toExclusive: period.endExclusive,
          categoryIds: _selected,
        ),
      );
      cursor = period.startInclusive.addDays(-1);
    }
    if (!mounted) return;
    setState(() => _average = _service.averageMonthly(expenses));
  }

  Future<void> _save() async {
    final months = int.tryParse(_months.text.trim());
    if (months == null) return;
    try {
      final scope = AppScope.of(context);
      await scope.graph.configureEmergencyFund(
        userId: scope.session.user.id,
        targetMonths: months,
        essentialCategoryIds: _selected.toList(),
      );
      if (!mounted) return;
      showSuccess(context, 'Reserva atualizada');
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final months = int.tryParse(_months.text.trim()) ?? 6;
    final target = _service.target(
      averageEssentialExpenses: _average,
      months: months,
    );
    final runway = _service.runway(
      reserve: _reserve,
      averageEssentialExpenses: _average,
    );
    return FinanPage(
      title: 'Reserva de emergência',
      subtitle: 'Autonomia para imprevistos',
      body: _loading
          ? const LoadingSkeleton()
          : LayoutBuilder(
              builder: (context, constraints) => _content(
                context,
                wide: constraints.maxWidth >= 900,
                months: months,
                target: target,
                runway: runway,
              ),
            ),
    );
  }

  Widget _content(
    BuildContext context, {
    required bool wide,
    required int months,
    required Money target,
    required double runway,
  }) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final coverage = target.cents <= 0
        ? 0.0
        : (_reserve.cents / target.cents).clamp(0.0, 1.0);
    final gap = Money(
      (target.cents - _reserve.cents).clamp(
        0,
        target.cents < 0 ? 0 : target.cents,
      ),
    );
    final noReference = _average.cents <= 0;
    final onTarget = !noReference && gap.cents == 0;
    var order = 0;
    Widget step(Widget child) => FadeSlideIn(index: order++, child: child);

    final hero = FinanHero(
      icon: CupertinoIcons.shield_fill,
      label: 'Reserva atual',
      value: _reserve,
      caption: 'Meta ${formatMoney(target)} · $months meses',
      side: ProgressRing(
        value: coverage,
        color: onTarget ? AppColors.accentDark : AppColors.warningDark,
        size: 96,
        stroke: 9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              runway.toStringAsFixed(1).replaceAll('.', ','),
              style: AppTypography.headline(Colors.white),
            ),
            Text(
              'meses',
              style: AppTypography.label(Colors.white.withValues(alpha: 0.7))
                  .copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
      stats: [
        HeroStat(
          icon: CupertinoIcons.creditcard,
          label: 'Em contas',
          money: _accounts,
        ),
        HeroStat(
          icon: CupertinoIcons.chart_pie,
          label: 'Investimentos',
          money: _investments,
        ),
        HeroStat(
          icon: CupertinoIcons.cart,
          label: 'Essencial/mês',
          money: _average,
        ),
      ],
    );

    final status = FinanCard(
      child: Row(
        children: [
          IconBadge(
            icon: noReference
                ? CupertinoIcons.info
                : onTarget
                ? CupertinoIcons.checkmark_seal_fill
                : CupertinoIcons.flag_fill,
            color: noReference
                ? AppColors.infoOf(brightness)
                : onTarget
                ? AppColors.incomeOf(brightness)
                : AppColors.warningOf(brightness),
            size: 44,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  noReference
                      ? 'Sem despesa essencial de referência'
                      : onTarget
                      ? 'Reserva dentro da meta'
                      : 'Faltam ${formatMoney(gap)}',
                  style: AppTypography.headline(scheme.onSurface)
                      .copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  noReference
                      ? 'Marque as categorias essenciais abaixo. A média usa '
                            'os 3 meses anteriores ao atual.'
                      : onTarget
                      ? 'Você cobre ${runway.toStringAsFixed(1).replaceAll('.', ',')} '
                            'meses de despesas essenciais.'
                      : 'Guardando ${formatMoney(Money((gap.cents / 12).ceil()))}'
                            '/mês, você chega lá em 1 ano.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AnimatedProgressBar(
                  value: coverage,
                  color: onTarget
                      ? AppColors.incomeOf(brightness)
                      : AppColors.warningOf(brightness),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(coverage * 100).round()}% da meta',
                  style: AppTypography.label(
                    scheme.onSurface.withValues(alpha: 0.5),
                  ).copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final settings = FinanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meses de cobertura',
            style: AppTypography.headline(scheme.onSurface)
                .copyWith(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Quanto tempo a reserva deve sustentar suas despesas essenciais.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final option in const [3, 6, 9, 12])
                FinanPill(
                  label: '$option meses',
                  selected: months == option,
                  onTap: () => setState(() => _months.text = '$option'),
                ),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _months,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Outro',
                    isDense: true,
                    suffixText: 'meses',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Categorias essenciais',
                  style: AppTypography.headline(scheme.onSurface)
                      .copyWith(fontSize: 16),
                ),
              ),
              DeltaChip(
                label: '${_selected.length} selecionadas',
                color: scheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Só essas despesas entram no cálculo. Lazer, compras e viagens '
            'ficam de fora por padrão.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final category in _categories)
                FinanPill(
                  label: category.name,
                  icon: iconFromName(category.icon),
                  selected: _selected.contains(category.id),
                  onTap: () async {
                    setState(() {
                      if (!_selected.remove(category.id)) {
                        _selected.add(category.id);
                      }
                    });
                    await _recalculate();
                  },
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(CupertinoIcons.checkmark_alt, size: 18),
            label: const Text('Salvar configuração'),
          ),
        ],
      ),
    );

    if (!wide) {
      return ListView(
        padding: screenPadding(context),
        children: [
          step(hero),
          const SizedBox(height: AppSpacing.md),
          step(status),
          const SizedBox(height: AppSpacing.lg),
          step(settings),
        ],
      );
    }
    return ListView(
      padding: screenPadding(context),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  step(hero),
                  const SizedBox(height: AppSpacing.md),
                  step(status),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(flex: 4, child: step(settings)),
          ],
        ),
      ],
    );
  }
}
