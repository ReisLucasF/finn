import 'package:finan/app/dependency_injection.dart';
import 'package:finan/application/categories/category_seeds.dart';
import 'package:finan/application/transactions/list_transactions.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';

import '../support/test_graph.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap cria um usuário e as categorias padrão uma vez', () async {
    final graph = await openTestGraph();
    final first = await graph.bootstrap();
    final second = await graph.bootstrap();
    final categories = await graph.listCategories(first.id);

    expect(second.id, first.id);
    expect(first.needsOnboarding, isTrue);
    expect(categories, hasLength(CategorySeeds.all.length));
    expect(categories.every((category) => category.isSystem), isTrue);
  });

  test('saldo inicial, receita e despesa reconstruem o saldo', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final salary = await _category(graph, user.id, 'Salário');
    final housing = await _category(graph, user.id, 'Moradia');

    expect(await graph.calculateAccountBalance(account.id), const Money(10000));

    final income = await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(5000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: account.id,
      categoryId: salary.id,
      description: 'Salário de outubro',
    );
    final expense = await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(2000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: account.id,
      categoryId: housing.id,
      description: 'Aluguel',
    );

    expect(await graph.calculateAccountBalance(account.id), const Money(13000));
    final incomeEntries = await graph.transactions.entriesFor(income.id);
    final expenseEntries = await graph.transactions.entriesFor(expense.id);
    expect(incomeEntries.single.amount.cents, 5000);
    expect(expenseEntries.single.amount.cents, -2000);

    final summary = await graph.getDashboardSummary(user.id);
    expect(summary.netWorth, const Money(13000));
    expect(summary.totalAccounts, const Money(13000));
    expect(summary.monthlyIncome, const Money(5000));
    expect(summary.monthlyExpenses, const Money(2000));
    expect(summary.monthlySavings, const Money(3000));
    expect(summary.savingsRate, closeTo(0.6, 0.0000001));
    expect(summary.totalInvestments.cents, 0);
    expect(summary.creditCardDebt.cents, 0);
  });

  test('pendente, cancelado e excluído ficam fora do saldo', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final salary = await _category(graph, user.id, 'Salário');
    final housing = await _category(graph, user.id, 'Moradia');

    final pending = await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(4000),
      transactionDate: const LocalDate(2026, 10, 2),
      accountId: account.id,
      categoryId: salary.id,
      status: TransactionStatus.pending,
    );
    expect(await graph.calculateAccountBalance(account.id), const Money(0));

    await graph.confirmTransaction(pending.id);
    expect(await graph.calculateAccountBalance(account.id), const Money(4000));

    final expense = await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(1500),
      transactionDate: const LocalDate(2026, 10, 3),
      accountId: account.id,
      categoryId: housing.id,
    );
    expect(await graph.calculateAccountBalance(account.id), const Money(2500));

    await graph.updateTransaction(
      id: expense.id,
      type: TransactionType.expense,
      amount: const Money(1500),
      transactionDate: const LocalDate(2026, 10, 3),
      accountId: account.id,
      categoryId: housing.id,
      status: TransactionStatus.cancelled,
    );
    expect(await graph.calculateAccountBalance(account.id), const Money(4000));

    await graph.deleteTransaction(pending.id);
    expect(await graph.calculateAccountBalance(account.id), const Money(0));

    final stored = await graph.transactions.findById(pending.id);
    expect(stored?.deletedAt, isNotNull);
  });

  test('lançamento de setembro não entra no mês corrente', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final salary = await _category(graph, user.id, 'Salário');

    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(9000),
      transactionDate: const LocalDate(2026, 9, 15),
      accountId: account.id,
      categoryId: salary.id,
      description: 'Setembro',
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(1000),
      transactionDate: const LocalDate(2026, 10, 1),
      accountId: account.id,
      categoryId: salary.id,
      description: 'Outubro',
    );

    final summary = await graph.getDashboardSummary(user.id);
    expect(summary.monthlyIncome, const Money(1000));
    expect(await graph.calculateAccountBalance(account.id), const Money(10000));

    final october = await graph.listTransactions(
      userId: user.id,
      period: TransactionPeriod.currentMonth,
    );
    expect(october.total, 1);
    expect(october.items.single.description, 'Outubro');
  });

  test(
    'contas não misturam saldo e a conta excluída sai do patrimônio',
    () async {
      final graph = await openTestGraph();
      final user = await graph.bootstrap();
      final first = await graph.createAccount(
        userId: user.id,
        name: 'Corrente',
        type: AccountType.checking,
        initialBalance: const Money(10000),
      );
      final second = await graph.createAccount(
        userId: user.id,
        name: 'Dinheiro',
        type: AccountType.cash,
        initialBalance: const Money(5000),
      );
      final salary = await _category(graph, user.id, 'Salário');
      await graph.createTransaction(
        userId: user.id,
        type: TransactionType.income,
        amount: const Money(2000),
        transactionDate: const LocalDate(2026, 10, 6),
        accountId: first.id,
        categoryId: salary.id,
      );

      expect(await graph.calculateAccountBalance(first.id), const Money(12000));
      expect(await graph.calculateAccountBalance(second.id), const Money(5000));
      expect(
        (await graph.getDashboardSummary(user.id)).netWorth,
        const Money(17000),
      );

      await graph.deleteAccount(second.id);
      final database = await graph.database.open();
      final row = await database.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [second.id],
      );
      expect(row.single['deleted_at'], isNotNull);
      expect(
        (await graph.getDashboardSummary(user.id)).netWorth,
        const Money(12000),
      );
      expect(await graph.listAccounts(user.id), hasLength(1));
    },
  );

  test('alterar o valor do lançamento reconstrói o saldo', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final salary = await _category(graph, user.id, 'Salário');
    final income = await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(1000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: account.id,
      categoryId: salary.id,
    );

    await graph.updateTransaction(
      id: income.id,
      type: TransactionType.income,
      amount: const Money(2500),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: account.id,
      categoryId: salary.id,
      status: TransactionStatus.confirmed,
    );

    expect(await graph.calculateAccountBalance(account.id), const Money(2500));
  });

  test('categoria incompatível e conta desativada são recusadas', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final housing = await _category(graph, user.id, 'Moradia');

    await expectLater(
      graph.createTransaction(
        userId: user.id,
        type: TransactionType.income,
        amount: const Money(1000),
        transactionDate: const LocalDate(2026, 10, 6),
        accountId: account.id,
        categoryId: housing.id,
      ),
      throwsA(isA<ValidationException>()),
    );

    await graph.deactivateAccount(account.id);
    final salary = await _category(graph, user.id, 'Salário');
    await expectLater(
      graph.createTransaction(
        userId: user.id,
        type: TransactionType.income,
        amount: const Money(1000),
        transactionDate: const LocalDate(2026, 10, 6),
        accountId: account.id,
        categoryId: salary.id,
      ),
      throwsA(isA<ValidationException>()),
    );
    expect((await graph.getDashboardSummary(user.id)).netWorth, const Money(0));
  });

  test('tipo da categoria não muda se já houver lançamento', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final salary = await _category(graph, user.id, 'Salário');
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(1000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: account.id,
      categoryId: salary.id,
    );

    await graph.updateCategory(
      id: salary.id,
      name: 'Salário mensal',
      type: salary.type,
      isActive: true,
      icon: salary.icon,
      color: salary.color,
    );

    await expectLater(
      graph.updateCategory(
        id: salary.id,
        name: salary.name,
        type: CategoryType.expense,
        isActive: true,
        icon: salary.icon,
        color: salary.color,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('lista filtra por descrição e pagina', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final housing = await _category(graph, user.id, 'Moradia');
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(1000),
      transactionDate: const LocalDate(2026, 10, 2),
      accountId: account.id,
      categoryId: housing.id,
      description: 'Aluguel do mês',
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(500),
      transactionDate: const LocalDate(2026, 10, 4),
      accountId: account.id,
      categoryId: housing.id,
      description: 'Mercado',
    );

    final search = await graph.listTransactions(
      userId: user.id,
      search: 'aluguel',
      period: TransactionPeriod.all,
    );
    expect(search.total, 1);
    expect(search.items.single.description, 'Aluguel do mês');

    final page = await graph.listTransactions(
      userId: user.id,
      period: TransactionPeriod.all,
      limit: 1,
    );
    expect(page.total, 2);
    expect(page.items, hasLength(1));
    expect(page.items.single.description, 'Mercado');
  });

  test('falha no meio do lançamento não deixa registro parcial', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final database = await graph.database.open();
    const id = 'tx-parcial';

    await expectLater(
      database.transaction((txn) async {
        await txn.insert('transactions', {
          'id': id,
          'user_id': user.id,
          'type': 'income',
          'amount': 1000,
          'transaction_date': '2026-10-06',
          'status': 'confirmed',
          'source': 'manual',
          'created_at': '2026-10-06T15:00:00.000Z',
          'updated_at': '2026-10-06T15:00:00.000Z',
        });
        await txn.insert('transaction_entries', {
          'id': 'entry-parcial',
          'transaction_id': id,
          'account_id': 'conta-inexistente',
          'amount': 1000,
          'created_at': '2026-10-06T15:00:00.000Z',
        });
      }),
      throwsA(anything),
    );

    final rows = await database.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    expect(rows, isEmpty);
  });
}

Future<Category> _category(AppGraph graph, String userId, String name) async {
  final categories = await graph.listCategories(userId);
  return categories.firstWhere((category) => category.name == name);
}
