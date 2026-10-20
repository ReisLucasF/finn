import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/budget_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_graph.dart';

void main() {
  test('orçamento soma despesas do mês, sugere limite e atualiza', () async {
    final graph = await openTestGraph(today: const LocalDate(2026, 10, 15));
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(1000000),
    );
    final categories = await graph.listCategories(user.id);
    final housing = categories.firstWhere((c) => c.name == 'Moradia');
    final salary = categories.firstWhere((c) => c.name == 'Salário');

    Future<void> spend(int cents, LocalDate date) => graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: Money(cents),
      transactionDate: date,
      accountId: account.id,
      categoryId: housing.id,
    );

    // Histórico: 3 meses anteriores somam R$ 3.000,00 => sugestão R$ 1.000,00.
    await spend(100000, const LocalDate(2026, 7, 10));
    await spend(120000, const LocalDate(2026, 8, 10));
    await spend(80000, const LocalDate(2026, 9, 10));
    // Mês atual.
    await spend(45000, const LocalDate(2026, 10, 3));
    await spend(5000, const LocalDate(2026, 10, 12));

    var planning = await graph.getBudgetPlanning(user.id);
    expect(planning.overview.isEmpty, isTrue);
    expect(planning.suggestions[housing.id], const Money(100000));
    expect(planning.categories.any((c) => c.id == salary.id), isFalse);

    await graph.saveBudget(
      userId: user.id,
      categoryId: housing.id,
      monthlyLimit: const Money(60000),
    );
    planning = await graph.getBudgetPlanning(user.id);
    final status = planning.overview.items.single;
    expect(status.spent, const Money(50000));
    expect(status.state, BudgetState.warning);

    // Salvar de novo na mesma categoria atualiza em vez de duplicar.
    await graph.saveBudget(
      userId: user.id,
      categoryId: housing.id,
      monthlyLimit: const Money(40000),
    );
    planning = await graph.getBudgetPlanning(user.id);
    expect(planning.overview.items, hasLength(1));
    expect(planning.overview.items.single.state, BudgetState.over);
    expect(planning.overview.items.single.budget.id, status.budget.id);

    await graph.deleteBudget(status.budget.id);
    planning = await graph.getBudgetPlanning(user.id);
    expect(planning.overview.isEmpty, isTrue);
  });

  test('rejeita limite zero e categoria de receita', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final categories = await graph.listCategories(user.id);
    final salary = categories.firstWhere((c) => c.name == 'Salário');
    final housing = categories.firstWhere((c) => c.name == 'Moradia');

    await expectLater(
      graph.saveBudget(
        userId: user.id,
        categoryId: housing.id,
        monthlyLimit: Money.zero,
      ),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      graph.saveBudget(
        userId: user.id,
        categoryId: salary.id,
        monthlyLimit: const Money(1000),
      ),
      throwsA(isA<ValidationException>()),
    );
  });
}
