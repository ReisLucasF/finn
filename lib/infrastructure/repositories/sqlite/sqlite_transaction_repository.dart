import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/database_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';

class SqliteTransactionRepository implements TransactionRepository {
  SqliteTransactionRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> insert(Transaction transaction, List<TransactionEntry> entries) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.insert('transactions', _toRow(transaction));
        for (final entry in entries) {
          await txn.insert('transaction_entries', _entryToRow(entry));
        }
      });
    });
  }

  @override
  Future<void> insertMany(
    List<Transaction> transactions,
    List<TransactionEntry> entries,
  ) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        for (final transaction in transactions) {
          await txn.insert('transactions', _toRow(transaction));
        }
        for (final entry in entries) {
          await txn.insert('transaction_entries', _entryToRow(entry));
        }
      });
    });
  }

  @override
  Future<Set<String>> existingExternalIds(
    String userId,
    List<String> externalIds,
  ) {
    if (externalIds.isEmpty) return Future.value(<String>{});
    return guardSqlite(() async {
      final database = await _database.open();
      final found = <String>{};
      for (var offset = 0; offset < externalIds.length; offset += 80) {
        final chunk = externalIds.skip(offset).take(80).toList();
        final marks = List.filled(chunk.length, '?').join(', ');
        final rows = await database.rawQuery(
          '''
SELECT external_id FROM transactions
WHERE user_id = ? AND deleted_at IS NULL AND external_id IN ($marks)
''',
          [userId, ...chunk],
        );
        for (final row in rows) {
          final id = row['external_id'] as String?;
          if (id != null) found.add(id);
        }
      }
      return found;
    });
  }

  @override
  Future<bool> linkExternalId({
    required String userId,
    required String transactionId,
    required String externalId,
    required DateTime reconciledAt,
    String? categoryId,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final count = await database.rawUpdate(
        '''
UPDATE transactions
SET external_id = ?,
    reconciled_at = ?,
    updated_at = ?,
    category_id = CASE
      WHEN category_id IS NULL AND ? IS NOT NULL THEN ?
      ELSE category_id
    END
WHERE id = ?
  AND user_id = ?
  AND deleted_at IS NULL
  AND status = 'confirmed'
  AND (external_id IS NULL OR external_id = ?)
''',
        [
          externalId,
          formatTimestamp(reconciledAt),
          formatTimestamp(reconciledAt),
          categoryId,
          categoryId,
          transactionId,
          userId,
          externalId,
        ],
      );
      return count > 0;
    });
  }

  @override
  Future<void> update(
    Transaction transaction, {
    List<TransactionEntry>? entries,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        final count = await txn.update(
          'transactions',
          _toRow(transaction),
          where: 'id = ?',
          whereArgs: [transaction.id],
        );
        if (count == 0) {
          throw const DatabaseException('Lançamento não encontrado.');
        }
        await txn.rawUpdate(
          '''
UPDATE transactions
SET sync_version = sync_version + 1, sync_state = 'pending_sync'
WHERE id = ?
''',
          [transaction.id],
        );
        if (entries == null) return;
        await txn.delete(
          'transaction_entries',
          where: 'transaction_id = ?',
          whereArgs: [transaction.id],
        );
        for (final entry in entries) {
          await txn.insert('transaction_entries', _entryToRow(entry));
        }
      });
    });
  }

  @override
  Future<Transaction?> findById(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _map(rows.first);
    });
  }

  @override
  Future<List<TransactionEntry>> entriesFor(String transactionId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'transaction_entries',
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      );
      return rows.map(_mapEntry).toList();
    });
  }

  @override
  Future<int> recategorize({
    required TransactionQuery query,
    required String categoryId,
    required DateTime updatedAt,
    required List<TransactionType> types,
    TransactionType? postedType,
    bool accountCashOnly = false,
  }) {
    if (types.isEmpty) return Future.value(0);
    return guardSqlite(() async {
      final database = await _database.open();
      final filter = _filter(query);
      final placeholders = List.filled(types.length, '?').join(', ');
      final assignments = <String>['category_id = ?', 'updated_at = ?'];
      final args = <Object?>[categoryId, formatTimestamp(updatedAt)];
      if (postedType != null) {
        assignments.add('type = ?');
        args.add(postedType.value);
      }
      final cashOnly = accountCashOnly
          ? ' AND account_id IS NOT NULL AND credit_card_id IS NULL AND transfer_id IS NULL AND investment_id IS NULL'
          : '';
      args.addAll(filter.args);
      args.addAll([for (final type in types) type.value, categoryId]);
      return database.rawUpdate(
        '''
UPDATE transactions
SET ${assignments.join(', ')}
WHERE ${filter.where}
  AND type IN ($placeholders)
  AND (category_id IS NULL OR category_id != ?)$cashOnly
''',
        args,
      );
    });
  }

  @override
  Future<List<InvestmentCashEvent>> listUnlinkedInvestmentCash(String userId) {
    return _investmentCash(userId, unlinkedOnly: true);
  }

  @override
  Future<List<InvestmentCashEvent>> listInvestmentCash(String userId) {
    return _investmentCash(userId, unlinkedOnly: false);
  }

  Future<List<InvestmentCashEvent>> _investmentCash(
    String userId, {
    required bool unlinkedOnly,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT t.id AS id,
       IFNULL(t.description, '') AS description,
       t.type AS type,
       t.amount AS amount,
       t.transaction_date AS transaction_date,
       t.account_id AS account_id,
       a.name AS account_name,
       t.investment_id AS investment_id
FROM transactions t
LEFT JOIN accounts a ON a.id = t.account_id
WHERE t.user_id = ?
  AND t.deleted_at IS NULL
  AND t.status = 'confirmed'
  AND t.type IN ('investment_contribution', 'investment_withdrawal')
  ${unlinkedOnly ? 'AND t.investment_id IS NULL' : ''}
ORDER BY t.transaction_date ASC, t.created_at ASC
''',
        [userId],
      );
      return [
        for (final row in rows)
          InvestmentCashEvent(
            description: row['description']! as String,
            type: TransactionType.fromValue(row['type']! as String),
            amount: Money(asInt(row['amount'])),
            date: LocalDate.parse(row['transaction_date']! as String),
            transactionId: row['id']! as String,
            accountId: row['account_id'] as String?,
            accountName: row['account_name'] as String?,
            investmentId: row['investment_id'] as String?,
          ),
      ];
    });
  }

  @override
  Future<TransactionPage> list(TransactionQuery query) {
    return guardSqlite(() async {
      final database = await _database.open();
      final filter = _filter(query);
      final totalRow = await database.rawQuery(
        'SELECT COUNT(*) AS total FROM transactions WHERE ${filter.where}',
        filter.args,
      );
      final direction = query.newestFirst ? 'DESC' : 'ASC';
      final rows = await database.query(
        'transactions',
        where: filter.where,
        whereArgs: filter.args,
        orderBy: 'transaction_date $direction, created_at $direction',
        limit: query.limit + 1,
        offset: query.offset,
      );
      final hasNext = rows.length > query.limit;
      final pageRows = hasNext ? rows.sublist(0, query.limit) : rows;
      return TransactionPage(
        items: pageRows.map(_map).toList(),
        total: asInt(totalRow.first['total']),
        nextDate: hasNext
            ? LocalDate.parse(rows[query.limit]['transaction_date']! as String)
            : null,
      );
    });
  }

  @override
  Future<Money> sumConfirmedAmount({
    required String userId,
    required TransactionType type,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
    Iterable<String>? categoryIds,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final ids = [
        for (final id in categoryIds ?? const <String>[])
          if (id.trim().isNotEmpty) id.trim(),
      ];
      if (categoryIds != null && ids.isEmpty) return Money.zero;
      final filter = ids.isEmpty
          ? ''
          : ' AND category_id IN (${List.filled(ids.length, '?').join(', ')})';
      final rows = await database.rawQuery(
        '''
SELECT COALESCE(SUM(amount), 0) AS total
FROM transactions
WHERE user_id = ?
  AND type = ?
  AND status = 'confirmed'
  AND deleted_at IS NULL
  AND transaction_date >= ?
  AND transaction_date < ?$filter
''',
        [
          userId,
          type.value,
          fromInclusive.toIso(),
          toExclusive.toIso(),
          ...ids,
        ],
      );
      return Money(asInt(rows.first['total']));
    });
  }

  @override
  Future<List<DatedFlow>> confirmedFlows({
    required String userId,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT transaction_date, type, SUM(amount) AS total
FROM transactions
WHERE user_id = ?
  AND deleted_at IS NULL
  AND status = 'confirmed'
  AND type IN ('income', 'expense')
  AND transaction_date >= ?
  AND transaction_date < ?
GROUP BY transaction_date, type
''',
        [userId, fromInclusive.toIso(), toExclusive.toIso()],
      );
      return [
        for (final row in rows)
          DatedFlow(
            date: LocalDate.parse(row['transaction_date']! as String),
            type: TransactionType.fromValue(row['type']! as String),
            amount: Money(asInt(row['total'])),
          ),
      ];
    });
  }

  @override
  Future<List<CategoryAmount>> categoryTotals({
    required String userId,
    required TransactionType type,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT COALESCE(c.name, 'Sem categoria') AS label, SUM(t.amount) AS total
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
WHERE t.user_id = ?
  AND t.deleted_at IS NULL
  AND t.status = 'confirmed'
  AND t.type = ?
  AND t.transaction_date >= ?
  AND t.transaction_date < ?
GROUP BY t.category_id, COALESCE(c.name, 'Sem categoria')
ORDER BY total DESC
''',
        [userId, type.value, fromInclusive.toIso(), toExclusive.toIso()],
      );
      return [
        for (final row in rows)
          CategoryAmount(
            label: row['label']! as String,
            amount: Money(asInt(row['total'])),
          ),
      ];
    });
  }

  @override
  Future<Map<String, Money>> expenseByCategoryId({
    required String userId,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT t.category_id AS category_id, SUM(t.amount) AS total
FROM transactions t
WHERE t.user_id = ?
  AND t.deleted_at IS NULL
  AND t.status = 'confirmed'
  AND t.type = ?
  AND t.category_id IS NOT NULL
  AND t.transaction_date >= ?
  AND t.transaction_date < ?
GROUP BY t.category_id
''',
        [
          userId,
          TransactionType.expense.value,
          fromInclusive.toIso(),
          toExclusive.toIso(),
        ],
      );
      return {
        for (final row in rows)
          row['category_id']! as String: Money(asInt(row['total'])),
      };
    });
  }

  @override
  Future<List<AccountBalanceParts>> balancePartsForUser(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT
  a.id AS account_id,
  a.initial_balance AS initial_balance,
  COALESCE(SUM(
    CASE
      WHEN t.id IS NOT NULL
       AND t.status = 'confirmed'
       AND t.deleted_at IS NULL
      THEN e.amount
      ELSE 0
    END
  ), 0) AS entries_sum
FROM accounts a
LEFT JOIN transaction_entries e ON e.account_id = a.id
LEFT JOIN transactions t ON t.id = e.transaction_id
WHERE a.user_id = ? AND a.deleted_at IS NULL
GROUP BY a.id, a.initial_balance
''',
        [userId],
      );
      return [
        for (final row in rows)
          AccountBalanceParts(
            accountId: row['account_id']! as String,
            initialBalance: Money(asInt(row['initial_balance'])),
            confirmedEntries: Money(asInt(row['entries_sum'])),
          ),
      ];
    });
  }

  @override
  Future<List<DailyAccountTotal>> confirmedDailyTotals(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT e.account_id AS account_id, t.transaction_date AS transaction_date,
       SUM(e.amount) AS total
FROM transaction_entries e
INNER JOIN transactions t ON t.id = e.transaction_id
WHERE t.user_id = ?
  AND t.deleted_at IS NULL
  AND t.status = 'confirmed'
  AND e.account_id IS NOT NULL
GROUP BY e.account_id, t.transaction_date
''',
        [userId],
      );
      return [
        for (final row in rows)
          DailyAccountTotal(
            accountId: row['account_id']! as String,
            date: LocalDate.parse(row['transaction_date']! as String),
            amount: Money(asInt(row['total'])),
          ),
      ];
    });
  }

  @override
  Future<bool> existsByCategory(String categoryId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'transactions',
        columns: const ['id'],
        where: 'category_id = ? AND deleted_at IS NULL',
        whereArgs: [categoryId],
        limit: 1,
      );
      return rows.isNotEmpty;
    });
  }

  @override
  Future<List<Transaction>> findReconciliationCandidates({
    required String userId,
    required String accountId,
    required Money absoluteAmount,
    required LocalDate date,
    String? externalId,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final fitId = externalId?.trim() ?? '';
      final from = date.addDays(-2).toIso();
      final to = date.addDays(2).toIso();
      final rows = await database.rawQuery(
        '''
SELECT * FROM transactions
WHERE user_id = ?
  AND deleted_at IS NULL
  AND (
    (? != '' AND external_id = ? AND account_id = ?)
    OR (
      amount = ?
      AND transaction_date >= ?
      AND transaction_date <= ?
    )
  )
LIMIT 100
''',
        [
          userId,
          fitId,
          fitId,
          accountId,
          absoluteAmount.cents,
          from,
          to,
        ],
      );
      return rows.map(_map).toList();
    });
  }

  @override
  Future<List<ClassifiedDescription>> recentClassifications(
    String userId, {
    int limit = 200,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'transactions',
        columns: const ['description', 'category_id'],
        where:
            'user_id = ? AND deleted_at IS NULL AND description IS NOT NULL AND category_id IS NOT NULL',
        whereArgs: [userId],
        orderBy: 'transaction_date DESC, created_at DESC',
        limit: limit,
      );
      return [
        for (final row in rows)
          ClassifiedDescription(
            description: row['description']! as String,
            categoryId: row['category_id']! as String,
          ),
      ];
    });
  }
}

class _SqlFilter {
  _SqlFilter(this.where, this.args);

  final String where;
  final List<Object?> args;
}

_SqlFilter _filter(TransactionQuery query) {
  final where = <String>['user_id = ?', 'deleted_at IS NULL'];
  final args = <Object?>[query.userId];
  final type = query.type;
  if (type != null) {
    where.add('type = ?');
    args.add(type.value);
  }
  final accountId = query.accountId;
  if (accountId != null) {
    where.add('account_id = ?');
    args.add(accountId);
  }
  final investmentId = query.investmentId;
  if (investmentId != null) {
    where.add('investment_id = ?');
    args.add(investmentId);
  }
  if (query.uncategorizedOnly) {
    where.add('category_id IS NULL');
  } else {
    final ids = [
      for (final id in query.categoryIds ?? const <String>[])
        if (id.trim().isNotEmpty) id,
    ];
    if (ids.isNotEmpty && query.includeUncategorized) {
      final placeholders = List.filled(ids.length, '?').join(', ');
      where.add('(category_id IS NULL OR category_id IN ($placeholders))');
      args.addAll(ids);
    } else if (ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(', ');
      where.add('category_id IN ($placeholders)');
      args.addAll(ids);
    } else if (query.includeUncategorized) {
      where.add('category_id IS NULL');
    }
  }
  final from = query.fromInclusive;
  if (from != null) {
    where.add('transaction_date >= ?');
    args.add(from.toIso());
  }
  final to = query.toInclusive;
  if (to != null) {
    where.add('transaction_date <= ?');
    args.add(to.toIso());
  }
  final search = query.search;
  if (search != null && search.isNotEmpty) {
    final escaped = search
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final amount = parseMoneyInput(search, allowNegative: true);
    if (amount != null) {
      where.add(
        "(IFNULL(description, '') LIKE ? ESCAPE '\\' OR amount = ?)",
      );
      args
        ..add('%$escaped%')
        ..add(amount.cents.abs());
    } else {
      where.add("IFNULL(description, '') LIKE ? ESCAPE '\\'");
      args.add('%$escaped%');
    }
  }
  return _SqlFilter(where.join(' AND '), args);
}

Map<String, Object?> _toRow(Transaction transaction) {
  return {
    'id': transaction.id,
    'user_id': transaction.userId,
    'type': transaction.type.value,
    'amount': transaction.amount.cents,
    'description': transaction.description,
    'transaction_date': transaction.transactionDate.toIso(),
    'competence_date': transaction.competenceDate?.toIso(),
    'due_date': transaction.dueDate?.toIso(),
    'status': transaction.status.value,
    'account_id': transaction.accountId,
    'category_id': transaction.categoryId,
    'credit_card_id': transaction.creditCardId,
    'transfer_id': transaction.transferId,
    'investment_id': transaction.investmentId,
    'recurrence_id': transaction.recurrenceId,
    'provision_id': transaction.provisionId,
    'paired_transaction_id': transaction.pairedTransactionId,
    'source': transaction.source.value,
    'external_id': transaction.externalId,
    'notes': transaction.notes,
    'reconciled_at': transaction.reconciledAt == null
        ? null
        : formatTimestamp(transaction.reconciledAt!),
    'created_at': formatTimestamp(transaction.createdAt),
    'updated_at': formatTimestamp(transaction.updatedAt),
    'deleted_at': transaction.deletedAt == null
        ? null
        : formatTimestamp(transaction.deletedAt!),
    'sync_state': 'pending_sync',
  };
}

Transaction _map(Map<String, Object?> row) {
  final reconciledAt = row['reconciled_at'] as String?;
  final deletedAt = row['deleted_at'] as String?;
  final competence = row['competence_date'] as String?;
  final due = row['due_date'] as String?;
  return Transaction(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    type: TransactionType.fromValue(row['type']! as String),
    amount: Money(asInt(row['amount'])),
    description: row['description'] as String?,
    transactionDate: LocalDate.parse(row['transaction_date']! as String),
    competenceDate: competence == null ? null : LocalDate.parse(competence),
    dueDate: due == null ? null : LocalDate.parse(due),
    status: TransactionStatus.fromValue(row['status']! as String),
    accountId: row['account_id'] as String?,
    categoryId: row['category_id'] as String?,
    creditCardId: row['credit_card_id'] as String?,
    transferId: row['transfer_id'] as String?,
    investmentId: row['investment_id'] as String?,
    recurrenceId: row['recurrence_id'] as String?,
    provisionId: row['provision_id'] as String?,
    pairedTransactionId: row['paired_transaction_id'] as String?,
    source: TransactionSource.fromValue(row['source']! as String),
    externalId: row['external_id'] as String?,
    notes: row['notes'] as String?,
    reconciledAt: reconciledAt == null ? null : parseTimestamp(reconciledAt),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
    deletedAt: deletedAt == null ? null : parseTimestamp(deletedAt),
  );
}

Map<String, Object?> _entryToRow(TransactionEntry entry) {
  return {
    'id': entry.id,
    'transaction_id': entry.transactionId,
    'account_id': entry.accountId,
    'credit_card_id': entry.creditCardId,
    'amount': entry.amount.cents,
    'created_at': formatTimestamp(entry.createdAt),
  };
}

TransactionEntry _mapEntry(Map<String, Object?> row) {
  return TransactionEntry(
    id: row['id']! as String,
    transactionId: row['transaction_id']! as String,
    accountId: row['account_id'] as String?,
    creditCardId: row['credit_card_id'] as String?,
    investmentId: row['investment_id'] as String?,
    amount: Money(asInt(row['amount'])),
    createdAt: parseTimestamp(row['created_at']! as String),
  );
}
