import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/recurrence_frequency.dart';
import 'package:finan/domain/enums/transaction_type.dart';

import '../support/test_graph.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transferência move saldo e não gera receita nem despesa', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final source = await graph.createAccount(
      userId: user.id,
      name: 'Origem',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final destination = await graph.createAccount(
      userId: user.id,
      name: 'Destino',
      type: AccountType.savings,
    );
    await graph.createTransfer(
      userId: user.id,
      sourceAccountId: source.id,
      destinationAccountId: destination.id,
      amount: const Money(2500),
      date: const LocalDate(2026, 10, 6),
    );

    expect(await graph.calculateAccountBalance(source.id), const Money(7500));
    expect(
      await graph.calculateAccountBalance(destination.id),
      const Money(2500),
    );
    final summary = await graph.getDashboardSummary(user.id);
    expect(summary.netWorth, const Money(10000));
    expect(summary.monthlyIncome, Money.zero);
    expect(summary.monthlyExpenses, Money.zero);
  });

  test('compra no cartão é despesa e o pagamento não é outra despesa', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final housing = await _category(graph, user.id, 'Moradia');
    final card = await graph.createCreditCard(
      userId: user.id,
      name: 'Visa',
      creditLimit: const Money(50000),
    );
    await graph.createCardPurchase(
      userId: user.id,
      cardId: card.id,
      categoryId: housing.id,
      amount: const Money(5000),
      date: const LocalDate(2026, 10, 6),
    );

    expect(await graph.calculateAccountBalance(account.id), const Money(10000));
    var summary = await graph.getDashboardSummary(user.id);
    expect(summary.monthlyExpenses, const Money(5000));
    expect(summary.creditCardDebt, const Money(5000));
    expect(summary.netWorth, const Money(5000));

    await graph.payCreditCard(
      userId: user.id,
      cardId: card.id,
      accountId: account.id,
      amount: const Money(5000),
      date: const LocalDate(2026, 10, 6),
    );
    expect(await graph.calculateAccountBalance(account.id), const Money(5000));
    summary = await graph.getDashboardSummary(user.id);
    expect(summary.monthlyExpenses, const Money(5000));
    expect(summary.creditCardDebt, Money.zero);
    expect(summary.netWorth, const Money(5000));
  });

  test('aporte não é despesa e o resgate não é receita', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(20000),
    );
    final investment = await graph.createInvestment(
      userId: user.id,
      name: 'Tesouro',
      kind: InvestmentKind.fixedIncome,
    );
    await graph.moveInvestment(
      userId: user.id,
      investmentId: investment.id,
      movement: InvestmentMovementType.contribution,
      amount: const Money(10000),
      date: const LocalDate(2026, 10, 6),
      accountId: account.id,
    );
    await graph.moveInvestment(
      userId: user.id,
      investmentId: investment.id,
      movement: InvestmentMovementType.income,
      amount: const Money(2000),
      date: const LocalDate(2026, 10, 6),
    );
    var summary = await graph.getDashboardSummary(user.id);
    expect(await graph.calculateAccountBalance(account.id), const Money(10000));
    expect(summary.totalInvestments, const Money(12000));
    expect(summary.netWorth, const Money(22000));
    expect(summary.monthlyIncome, Money.zero);
    expect(summary.monthlyExpenses, Money.zero);

    await graph.moveInvestment(
      userId: user.id,
      investmentId: investment.id,
      movement: InvestmentMovementType.withdrawal,
      amount: const Money(12000),
      date: const LocalDate(2026, 10, 6),
      accountId: account.id,
    );
    summary = await graph.getDashboardSummary(user.id);
    expect(await graph.calculateAccountBalance(account.id), const Money(22000));
    expect(summary.totalInvestments, Money.zero);
    expect(summary.monthlyIncome, Money.zero);
    expect(summary.netWorth, const Money(22000));
  });

  test('provisionamento só entra no saldo quando é liquidado', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final housing = await _category(graph, user.id, 'Moradia');
    await graph.createRecurrence(
      userId: user.id,
      name: 'Aluguel',
      type: TransactionType.expense,
      amount: const Money(3000),
      accountId: account.id,
      categoryId: housing.id,
      frequency: RecurrenceFrequency.monthly,
      startDate: const LocalDate(2026, 10, 10),
    );
    final recurrence = (await graph.finance.listRecurrences(user.id)).single;
    final created = await graph.generateProvisions(
      userId: user.id,
      recurrenceId: recurrence.id,
      until: const LocalDate(2026, 10, 31),
    );
    expect(created, 1);
    expect(await graph.calculateAccountBalance(account.id), const Money(10000));
    var summary = await graph.getDashboardSummary(user.id);
    expect(summary.projectedBalance, const Money(7000));
    expect(summary.monthlyExpenses, Money.zero);

    final provision = (await graph.finance.listProvisions(user.id)).single;
    await graph.settleProvision(userId: user.id, provisionId: provision.id);
    expect(await graph.calculateAccountBalance(account.id), const Money(7000));
    summary = await graph.getDashboardSummary(user.id);
    expect(summary.monthlyExpenses, const Money(3000));
    expect(summary.projectedBalance, const Money(7000));
  });

  test('reserva de emergência ignora lazer e usa só categorias essenciais', () async {
    final graph = await openTestGraph(today: const LocalDate(2026, 10, 6));
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(600000),
    );
    final housing = await _category(graph, user.id, 'Moradia');
    final leisure = await _category(graph, user.id, 'Lazer');
    for (final day in [
      const LocalDate(2026, 7, 10),
      const LocalDate(2026, 8, 10),
      const LocalDate(2026, 9, 10),
    ]) {
      await graph.createTransaction(
        userId: user.id,
        type: TransactionType.expense,
        amount: const Money(100000),
        transactionDate: day,
        accountId: account.id,
        categoryId: housing.id,
        description: 'Aluguel',
      );
    }
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(50000),
      transactionDate: const LocalDate(2026, 9, 12),
      accountId: account.id,
      categoryId: leisure.id,
      description: 'Cinema',
    );
    await graph.configureEmergencyFund(
      userId: user.id,
      targetMonths: 6,
      essentialCategoryIds: [housing.id],
    );
    final summary = await graph.getDashboardSummary(user.id);
    // Saldo 250000 / média essencial 100000 = 2,5 meses (lazer fora).
    expect(summary.emergencyRunway, closeTo(2.5, 0.0001));
    final all = await graph.transactions.sumConfirmedAmount(
      userId: user.id,
      type: TransactionType.expense,
      fromInclusive: const LocalDate(2026, 9, 1),
      toExclusive: const LocalDate(2026, 10, 1),
    );
    expect(all, const Money(150000));
    final essential = await graph.transactions.sumConfirmedAmount(
      userId: user.id,
      type: TransactionType.expense,
      fromInclusive: const LocalDate(2026, 9, 1),
      toExclusive: const LocalDate(2026, 10, 1),
      categoryIds: [housing.id],
    );
    expect(essential, const Money(100000));
  });

  test('backup restaura saldo e lançamento', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(8000),
    );
    final bytes = await graph.createBackup();
    await graph.restoreBackup(bytes);
    expect(await graph.calculateAccountBalance(account.id), const Money(8000));
    final restored = await graph.accounts.listByUser(user.id);
    expect(restored.single.name, 'Corrente');
  });
}

Future<dynamic> _category(dynamic graph, String userId, String name) async {
  final categories = await graph.listCategories(userId);
  return categories.firstWhere((category) => category.name == name);
}
