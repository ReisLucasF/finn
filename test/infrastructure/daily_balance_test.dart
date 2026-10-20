import 'package:finan/application/transactions/closing_balances.dart';
import 'package:finan/application/transactions/list_transactions.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';

import '../support/test_graph.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dia incompleto na página não fecha o saldo', () {
    final day = const LocalDate(2026, 10, 6);
    final older = const LocalDate(2026, 10, 5);
    final items = [
      _item('1', day, 'conta'),
      _item('2', day, 'conta'),
    ];

    expect(
      closingPoints(items: items, nextDate: day, accountId: 'conta'),
      isEmpty,
    );
    expect(
      closingPoints(items: items, nextDate: older, accountId: 'conta'),
      {('conta', day)},
    );
    expect(
      closingPoints(items: items, nextDate: null, accountId: null),
      {('conta', day)},
    );
  });

  test('saldo do dia usa a conta inteira e a página guarda a data seguinte', () async {
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
    final salary = (await graph.listCategories(user.id)).firstWhere(
      (category) => category.name == 'Salário',
    );
    final housing = (await graph.listCategories(user.id)).firstWhere(
      (category) => category.name == 'Moradia',
    );

    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(5000),
      transactionDate: const LocalDate(2026, 10, 5),
      accountId: checking.id,
      categoryId: salary.id,
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(2000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: checking.id,
      categoryId: housing.id,
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(9000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: checking.id,
      categoryId: housing.id,
      status: TransactionStatus.pending,
    );
    await graph.createTransfer(
      userId: user.id,
      sourceAccountId: checking.id,
      destinationAccountId: savings.id,
      amount: const Money(1000),
      date: const LocalDate(2026, 10, 6),
    );

    final accounts = await graph.accounts.listByUser(user.id);
    final totals = await graph.transactions.confirmedDailyTotals(user.id);
    final balances = closingBalances(
      accounts: accounts,
      totals: totals,
      points: {
        (checking.id, const LocalDate(2026, 10, 5)),
        (checking.id, const LocalDate(2026, 10, 6)),
        (savings.id, const LocalDate(2026, 10, 6)),
      },
    );

    expect(balances[(checking.id, const LocalDate(2026, 10, 5))], const Money(15000));
    expect(balances[(checking.id, const LocalDate(2026, 10, 6))], const Money(12000));
    expect(balances[(savings.id, const LocalDate(2026, 10, 6))], const Money(1000));

    final page = await graph.listTransactions(
      userId: user.id,
      period: TransactionPeriod.all,
      limit: 1,
    );
    expect(page.items, hasLength(1));
    expect(page.total, 4);
    expect(page.nextDate, isNotNull);
  });
}

Transaction _item(String id, LocalDate date, String accountId) {
  final now = DateTime.utc(2026, 10, 6);
  return Transaction(
    id: id,
    userId: 'user',
    type: TransactionType.expense,
    amount: const Money(100),
    transactionDate: date,
    status: TransactionStatus.confirmed,
    source: TransactionSource.manual,
    accountId: accountId,
    createdAt: now,
    updatedAt: now,
  );
}
