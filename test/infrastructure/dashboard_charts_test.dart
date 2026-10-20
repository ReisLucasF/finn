import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';

import '../support/test_graph.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gráficos do mês seguem patrimônio, receita e despesa', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final checking = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final savings = await graph.createAccount(
      userId: user.id,
      name: 'Poupança',
      type: AccountType.savings,
    );
    final categories = await graph.listCategories(user.id);
    final salary = categories.firstWhere((category) => category.name == 'Salário');
    final housing = categories.firstWhere((category) => category.name == 'Moradia');

    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(5000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: checking.id,
      categoryId: salary.id,
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(2000),
      transactionDate: const LocalDate(2026, 10, 4),
      accountId: checking.id,
      categoryId: housing.id,
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(800),
      transactionDate: const LocalDate(2026, 10, 3),
      accountId: checking.id,
    );
    await graph.createTransfer(
      userId: user.id,
      sourceAccountId: checking.id,
      destinationAccountId: savings.id,
      amount: const Money(1000),
      date: const LocalDate(2026, 10, 5),
    );

    final summary = await graph.getDashboardSummary(user.id);
    final charts = summary.charts;
    expect(charts.netWorth.last.amount, summary.netWorth);
    expect(charts.months.last.income, summary.monthlyIncome);
    expect(charts.months.last.expense, summary.monthlyExpenses);
    expect(charts.incomeByCategory.single.amount, const Money(5000));
    final expenses = charts.expenseByCategory;
    expect(
      expenses.map((slice) => slice.label),
      containsAll(['Moradia', 'Sem categoria']),
    );
    expect(
      expenses.fold<int>(0, (sum, slice) => sum + slice.amount.cents),
      2800,
    );
  });
}
