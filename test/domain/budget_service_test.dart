import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/budget.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/services/budget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = BudgetService();
  final created = DateTime.utc(2026, 10, 1);
  // Outubro: 31 dias.
  const period = FinancialPeriod(
    startInclusive: LocalDate(2026, 10, 1),
    endExclusive: LocalDate(2026, 11, 1),
  );

  Category category(String id, {String? parentId, CategoryType? type}) =>
      Category(
        id: id,
        name: id,
        type: type ?? CategoryType.expense,
        isSystem: false,
        isActive: true,
        createdAt: created,
        updatedAt: created,
        parentId: parentId,
      );

  Budget budget(String categoryId, int limit) => Budget(
    id: 'b-$categoryId',
    userId: 'u',
    categoryId: categoryId,
    monthlyLimit: Money(limit),
    isActive: true,
    createdAt: created,
    updatedAt: created,
  );

  BudgetOverview evaluate(
    List<Budget> budgets,
    Map<String, Money> spent, {
    LocalDate today = const LocalDate(2026, 10, 10),
    List<Category>? categories,
  }) => service.evaluate(
    budgets: budgets,
    categories: categories ?? [category('mercado'), category('lazer')],
    spentByCategory: spent,
    period: period,
    today: today,
  );

  test('classifica ok, alerta (80%) e estourado', () {
    final overview = evaluate(
      [budget('mercado', 100000), budget('lazer', 10000)],
      {'mercado': const Money(30000), 'lazer': const Money(12000)},
      today: const LocalDate(2026, 10, 5),
    );
    final lazer = overview.items.first;
    expect(lazer.category.id, 'lazer');
    expect(lazer.state, BudgetState.over);
    expect(lazer.remaining, const Money(-2000));
    expect(overview.items.last.state, BudgetState.ok);
    expect(overview.overCount, 1);

    final warning = evaluate(
      [budget('mercado', 100000)],
      {'mercado': const Money(80000)},
      today: const LocalDate(2026, 10, 2),
    );
    expect(warning.items.single.state, BudgetState.warning);
  });

  test('projeção acima do limite gera alerta só após 25% do período', () {
    // Dia 10 de 31: gasto de 40% projeta ~124% do limite.
    final mid = evaluate(
      [budget('mercado', 100000)],
      {'mercado': const Money(40000)},
    );
    expect(mid.items.single.projected.cents, greaterThan(100000));
    expect(mid.items.single.state, BudgetState.warning);

    // Dia 2: projeção alta, mas cedo demais para alertar.
    final early = evaluate(
      [budget('mercado', 100000)],
      {'mercado': const Money(10000)},
      today: const LocalDate(2026, 10, 2),
    );
    expect(early.items.single.state, BudgetState.ok);
  });

  test('saldo diário divide o restante pelos dias que faltam', () {
    // Dia 10 de 31: faltam 22 dias contando hoje.
    final overview = evaluate(
      [budget('mercado', 100000)],
      {'mercado': const Money(34000)},
    );
    expect(overview.daysLeft, 22);
    expect(overview.items.single.dailyAllowance, const Money(3000));
  });

  test('soma o gasto das subcategorias no orçamento da categoria pai', () {
    final overview = evaluate(
      [budget('casa', 200000)],
      {
        'casa': const Money(10000),
        'luz': const Money(15000),
        'outra': const Money(99999),
      },
      categories: [
        category('casa'),
        category('luz', parentId: 'casa'),
        category('outra'),
      ],
    );
    expect(overview.items.single.spent, const Money(25000));
  });

  test('ignora orçamentos inativos ou de categoria inexistente', () {
    final inactive = budget('mercado', 1000).copyWith(isActive: false);
    final overview = evaluate([inactive, budget('sumiu', 1000)], const {});
    expect(overview.isEmpty, isTrue);
  });

  test('sugestão arredonda a média para cima em múltiplos de 10 reais', () {
    expect(service.suggestLimit(const Money(100000), 3), const Money(34000));
    expect(service.suggestLimit(Money.zero, 3), isNull);
  });

  test('só categorias de despesa ativas aceitam orçamento', () {
    expect(BudgetService.isBudgetable(category('a')), isTrue);
    expect(
      BudgetService.isBudgetable(category('b', type: CategoryType.income)),
      isFalse,
    );
  });
}
