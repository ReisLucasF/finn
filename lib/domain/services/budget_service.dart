import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/budget.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';

enum BudgetState { ok, warning, over }

class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.category,
    required this.spent,
    required this.projected,
    required this.dailyAllowance,
    required this.state,
  });

  final Budget budget;
  final Category category;
  final Money spent;

  /// Gasto estimado no fim do período, mantendo o ritmo atual.
  final Money projected;

  /// Quanto ainda dá para gastar por dia até o fim do período.
  final Money dailyAllowance;
  final BudgetState state;

  Money get limit => budget.monthlyLimit;

  Money get remaining => Money(limit.cents - spent.cents);

  double get ratio => limit.cents <= 0 ? 0 : spent.cents / limit.cents;
}

class BudgetOverview {
  const BudgetOverview({
    required this.period,
    required this.today,
    required this.items,
    required this.elapsed,
    required this.daysLeft,
  });

  final FinancialPeriod period;
  final LocalDate today;

  /// Ordenados do mais crítico (maior consumo) para o menos.
  final List<BudgetStatus> items;

  /// Fração do período já decorrida (0–1).
  final double elapsed;

  /// Dias restantes, contando hoje.
  final int daysLeft;

  bool get isEmpty => items.isEmpty;

  Money get totalLimit =>
      items.fold(Money.zero, (sum, item) => sum + item.limit);

  Money get totalSpent =>
      items.fold(Money.zero, (sum, item) => sum + item.spent);

  int get overCount =>
      items.where((item) => item.state == BudgetState.over).length;

  int get warningCount =>
      items.where((item) => item.state == BudgetState.warning).length;
}

/// Regras de orçamento mensal por categoria. Valores sempre em centavos.
class BudgetService {
  const BudgetService();

  /// Consumo a partir do qual o orçamento entra em alerta.
  static const warningRatio = 0.8;

  /// Antes desta fração do período a projeção é ruidosa demais para alertar.
  static const projectionFrom = 0.25;

  static bool isBudgetable(Category category) =>
      category.deletedAt == null &&
      category.isActive &&
      (category.type == CategoryType.expense ||
          category.type == CategoryType.both);

  BudgetOverview evaluate({
    required List<Budget> budgets,
    required List<Category> categories,
    required Map<String, Money> spentByCategory,
    required FinancialPeriod period,
    required LocalDate today,
  }) {
    final byId = {for (final category in categories) category.id: category};
    final totalDays = _days(period.startInclusive, period.endExclusive);
    final passed = _days(period.startInclusive, today).clamp(0, totalDays) + 1;
    final elapsed = (passed / totalDays).clamp(0.0, 1.0);
    final daysLeft = (totalDays - passed + 1).clamp(1, totalDays);

    final items = <BudgetStatus>[];
    for (final budget in budgets) {
      final category = byId[budget.categoryId];
      if (!budget.isActive || category == null) continue;
      final spent = rollUp(category.id, categories, spentByCategory);
      final projected = elapsed <= 0
          ? spent
          : Money((spent.cents / elapsed).round());
      final remaining = budget.monthlyLimit.cents - spent.cents;
      final state = spent.cents > budget.monthlyLimit.cents
          ? BudgetState.over
          : spent.cents >= budget.monthlyLimit.cents * warningRatio ||
                (elapsed >= projectionFrom &&
                    projected.cents > budget.monthlyLimit.cents)
          ? BudgetState.warning
          : BudgetState.ok;
      items.add(
        BudgetStatus(
          budget: budget,
          category: category,
          spent: spent,
          projected: projected,
          dailyAllowance: Money(remaining <= 0 ? 0 : remaining ~/ daysLeft),
          state: state,
        ),
      );
    }
    items.sort((a, b) => b.ratio.compareTo(a.ratio));
    return BudgetOverview(
      period: period,
      today: today,
      items: items,
      elapsed: elapsed,
      daysLeft: daysLeft,
    );
  }

  /// Gasto da categoria somado ao das subcategorias diretas.
  Money rollUp(
    String categoryId,
    List<Category> categories,
    Map<String, Money> spentByCategory,
  ) {
    var cents = spentByCategory[categoryId]?.cents ?? 0;
    for (final child in categories) {
      if (child.parentId == categoryId && child.id != categoryId) {
        cents += spentByCategory[child.id]?.cents ?? 0;
      }
    }
    return Money(cents);
  }

  /// Sugestão de limite: média mensal do histórico arredondada para cima
  /// em múltiplos de R$ 10. Nula sem histórico.
  Money? suggestLimit(Money historyTotal, int months) {
    if (months <= 0 || historyTotal.cents <= 0) return null;
    final average = historyTotal.cents / months;
    const step = 1000;
    return Money((average / step).ceil() * step);
  }

  int _days(LocalDate from, LocalDate to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
