import 'dart:io';

import 'package:finan/application/transactions/list_transactions.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/apply_migrations.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_001_initial.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import '../support/test_graph.dart';

void main() {
  test('troca a categoria só do filtro e ignora transferência', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final checking = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final savings = await graph.createAccount(
      userId: user.id,
      name: 'Poupança',
      type: AccountType.savings,
    );
    final transport = await _category(graph, 'Transporte', CategoryType.expense);
    final food = await _category(graph, 'Alimentação', CategoryType.expense);
    final salary = await _category(graph, 'Salário', CategoryType.income);
    const day = LocalDate(2026, 10, 6);

    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(1000),
      transactionDate: day,
      accountId: checking.id,
      categoryId: transport.id,
      description: 'Uber',
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(1000),
      transactionDate: day,
      accountId: savings.id,
      categoryId: transport.id,
      description: 'Uber',
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(1000),
      transactionDate: day,
      accountId: checking.id,
      categoryId: salary.id,
      description: 'Uber',
    );
    await graph.createTransfer(
      userId: user.id,
      sourceAccountId: checking.id,
      destinationAccountId: savings.id,
      amount: const Money(1000),
      date: day,
      description: 'Uber',
    );
    final looseId = graph.ids.next();
    final now = DateTime.utc(2026, 10, 6);
    await graph.transactions.insert(
      Transaction(
        id: looseId,
        userId: user.id,
        type: TransactionType.expense,
        amount: const Money(500),
        description: 'Avulso',
        transactionDate: day,
        status: TransactionStatus.confirmed,
        accountId: checking.id,
        source: TransactionSource.manual,
        createdAt: now,
        updatedAt: now,
      ),
      [
        TransactionEntry(
          id: graph.ids.next(),
          transactionId: looseId,
          accountId: checking.id,
          amount: const Money(-500),
          createdAt: now,
        ),
      ],
    );

    final updated = await graph.recategorizeTransactions(
      userId: user.id,
      categoryId: food.id,
      accountId: checking.id,
      currentCategoryId: transport.id,
      period: TransactionPeriod.all,
      search: 'Uber',
    );
    expect(updated, 1);

    final loose = await graph.recategorizeTransactions(
      userId: user.id,
      categoryId: food.id,
      accountId: checking.id,
      uncategorizedOnly: true,
      period: TransactionPeriod.all,
      search: 'Avulso',
    );
    expect(loose, 1);

    final page = await graph.listTransactions(
      userId: user.id,
      period: TransactionPeriod.all,
      limit: 20,
    );
    String? categoryOf(String description, TransactionType type) {
      return page.items
          .firstWhere(
            (item) => item.description == description && item.type == type,
          )
          .categoryId;
    }

    expect(
      page.items
          .where(
            (item) =>
                item.description == 'Uber' &&
                item.type == TransactionType.expense &&
                item.accountId == checking.id,
          )
          .single
          .categoryId,
      food.id,
    );
    expect(
      page.items
          .where(
            (item) =>
                item.description == 'Uber' &&
                item.type == TransactionType.expense &&
                item.accountId == savings.id,
          )
          .single
          .categoryId,
      transport.id,
    );
    expect(categoryOf('Uber', TransactionType.income), salary.id);
    expect(categoryOf('Uber', TransactionType.transfer), isNull);
    expect(categoryOf('Avulso', TransactionType.expense), food.id);
  });

  test('aplicação e resgate ficam fora de despesa e receita', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(100000),
    );
    final transport = await _category(graph, 'Transporte', CategoryType.expense);
    final salary = await _category(graph, 'Salário', CategoryType.income);
    final application = await _category(
      graph,
      'Aplicação em investimento',
      CategoryType.investmentApplication,
    );
    final redemption = await _category(
      graph,
      'Resgate de investimento',
      CategoryType.investmentRedemption,
    );
    const day = LocalDate(2026, 10, 6);
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(30000),
      transactionDate: day,
      accountId: account.id,
      categoryId: transport.id,
      description: 'CDB Credito',
    );
    final applied = await graph.recategorizeTransactions(
      userId: user.id,
      categoryId: application.id,
      period: TransactionPeriod.all,
      search: 'CDB',
    );
    expect(applied, 1);
    expect(await graph.calculateAccountBalance(account.id), const Money(70000));
    expect(
      await graph.transactions.sumConfirmedAmount(
        userId: user.id,
        type: TransactionType.expense,
        fromInclusive: const LocalDate(2026, 10, 1),
        toExclusive: const LocalDate(2026, 11, 1),
      ),
      Money.zero,
    );
    var summary = await graph.getDashboardSummary(user.id);
    expect(summary.monthlyExpenses, Money.zero);
    expect(summary.totalInvestments, const Money(30000));
    expect(summary.netWorth, const Money(100000));

    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(35000),
      transactionDate: day,
      accountId: account.id,
      categoryId: salary.id,
      description: 'CDB Credito',
    );
    final redeemed = await graph.recategorizeTransactions(
      userId: user.id,
      categoryId: redemption.id,
      period: TransactionPeriod.all,
      search: 'CDB',
    );
    expect(redeemed, 1);
    expect(await graph.calculateAccountBalance(account.id), const Money(105000));
    expect(
      await graph.transactions.sumConfirmedAmount(
        userId: user.id,
        type: TransactionType.income,
        fromInclusive: const LocalDate(2026, 10, 1),
        toExclusive: const LocalDate(2026, 11, 1),
      ),
      Money.zero,
    );
    summary = await graph.getDashboardSummary(user.id);
    expect(summary.monthlyIncome, Money.zero);
    expect(summary.monthlyExpenses, Money.zero);
    expect(summary.totalInvestments, Money.zero);
    expect(summary.investmentGain, const Money(5000));
    expect(summary.netWorth, const Money(105000));
  });

  test('transferência interna sai de receita e despesa', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Inter',
      type: AccountType.checking,
      initialBalance: const Money(100000),
    );
    final salary = await _category(graph, 'Salário', CategoryType.income);
    final internal = await _category(
      graph,
      'Transferências internas',
      CategoryType.internalTransfer,
    );
    const day = LocalDate(2026, 10, 6);
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(150000),
      transactionDate: day,
      accountId: account.id,
      categoryId: salary.id,
      description: 'Lucas Filipe',
    );
    final moved = await graph.recategorizeTransactions(
      userId: user.id,
      categoryId: internal.id,
      period: TransactionPeriod.all,
      search: 'Lucas',
    );
    expect(moved, 1);
    expect(await graph.calculateAccountBalance(account.id), const Money(250000));
    expect(
      await graph.transactions.sumConfirmedAmount(
        userId: user.id,
        type: TransactionType.income,
        fromInclusive: const LocalDate(2026, 10, 1),
        toExclusive: const LocalDate(2026, 11, 1),
      ),
      Money.zero,
    );
    final summary = await graph.getDashboardSummary(user.id);
    expect(summary.monthlyIncome, Money.zero);
    final page = await graph.listTransactions(
      userId: user.id,
      period: TransactionPeriod.all,
      search: 'Lucas',
    );
    expect(page.items.single.type, TransactionType.transfer);
    expect(page.items.single.categoryId, internal.id);
  });

  test('rendimento marcado como resgate volta a ser receita', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Mercado pago',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final interest = await _category(graph, 'Juros', CategoryType.income);
    final redemption = await _category(
      graph,
      'Resgate de investimento',
      CategoryType.investmentRedemption,
    );
    const day = LocalDate(2026, 9, 22);
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(33),
      transactionDate: day,
      accountId: account.id,
      categoryId: interest.id,
      description: 'Rendimentos',
    );
    final asRedemption = await graph.recategorizeTransactions(
      userId: user.id,
      categoryId: redemption.id,
      period: TransactionPeriod.all,
      search: 'Rendimentos',
    );
    expect(asRedemption, 1);
    expect(
      await graph.transactions.sumConfirmedAmount(
        userId: user.id,
        type: TransactionType.income,
        fromInclusive: const LocalDate(2026, 9, 1),
        toExclusive: const LocalDate(2026, 10, 1),
      ),
      Money.zero,
    );

    final back = await graph.recategorizeTransactions(
      userId: user.id,
      categoryId: interest.id,
      period: TransactionPeriod.all,
      search: 'Rendimentos',
    );
    expect(back, 1);
    expect(
      await graph.transactions.sumConfirmedAmount(
        userId: user.id,
        type: TransactionType.income,
        fromInclusive: const LocalDate(2026, 9, 1),
        toExclusive: const LocalDate(2026, 10, 1),
      ),
      const Money(33),
    );
    expect(await graph.calculateAccountBalance(account.id), const Money(10033));
  });

  test('atualização para categorias de investimento preserva as atuais', () async {
    await openTestGraph();
    final filePath = path.join(
      Directory.systemTemp.path,
      'finan_cat_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final created = await databaseFactory.openDatabase(
      filePath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: configureDatabase,
        onCreate: (db, version) => applyMigrations(db, 0, version),
      ),
    );
    await created.insert('users', {
      'id': 'user-1',
      'name': 'Lucas',
      'created_at': '2026-10-06T00:00:00.000Z',
      'updated_at': '2026-10-06T00:00:00.000Z',
    });
    await created.insert('categories', {
      'id': 'cat-1',
      'user_id': 'user-1',
      'name': 'Transporte',
      'type': 'expense',
      'is_system': 0,
      'is_active': 1,
      'created_at': '2026-10-06T00:00:00.000Z',
      'updated_at': '2026-10-06T00:00:00.000Z',
    });
    await created.insert('transactions', {
      'id': 'tx-1',
      'user_id': 'user-1',
      'type': 'expense',
      'amount': 1000,
      'transaction_date': '2026-10-06',
      'status': 'confirmed',
      'category_id': 'cat-1',
      'source': 'manual',
      'created_at': '2026-10-06T00:00:00.000Z',
      'updated_at': '2026-10-06T00:00:00.000Z',
    });
    await created.close();

    final upgraded = await databaseFactory.openDatabase(
      filePath,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: configureDatabase,
        onOpen: openDatabaseConnection,
        onUpgrade: (db, from, to) => applyMigrations(db, from, to),
      ),
    );
    final kept = await upgraded.query(
      'categories',
      where: 'id = ?',
      whereArgs: ['cat-1'],
    );
    expect(kept.single['name'], 'Transporte');
    final transaction = await upgraded.query(
      'transactions',
      where: 'id = ?',
      whereArgs: ['tx-1'],
    );
    expect(transaction.single['category_id'], 'cat-1');
    final violations = await upgraded.rawQuery('PRAGMA foreign_key_check');
    expect(violations, isEmpty);
    await upgraded.insert('categories', {
      'id': 'cat-2',
      'name': 'Aplicação em investimento',
      'type': 'investment_application',
      'is_system': 1,
      'is_active': 1,
      'created_at': '2026-10-06T00:00:00.000Z',
      'updated_at': '2026-10-06T00:00:00.000Z',
    });
    await upgraded.close();
    File(filePath).deleteSync();
  });
}

Future<dynamic> _category(dynamic graph, String name, CategoryType type) async {
  final user = await graph.bootstrap();
  final categories = await graph.listCategories(user.id);
  return categories.firstWhere(
    (category) => category.name == name && category.type == type,
  );
}
