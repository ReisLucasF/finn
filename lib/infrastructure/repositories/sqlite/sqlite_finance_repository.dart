import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/goal_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/provision_status.dart';
import 'package:finan/domain/enums/recurrence_frequency.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';

class SqliteFinanceRepository implements FinanceRepository {
  SqliteFinanceRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> saveTransfer({
    required String id,
    required String userId,
    required String sourceAccountId,
    required String destinationAccountId,
    required Money amount,
    required LocalDate date,
    required String? description,
    required String status,
    required DateTime createdAt,
    required Transaction transaction,
    required List<TransactionEntry> entries,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.insert('transfers', {
          'id': id,
          'user_id': userId,
          'source_account_id': sourceAccountId,
          'destination_account_id': destinationAccountId,
          'amount': amount.cents,
          'transaction_date': date.toIso(),
          'description': description,
          'status': status,
          'created_at': formatTimestamp(createdAt),
          'updated_at': formatTimestamp(createdAt),
        });
        await txn.insert('transactions', _transactionRow(transaction));
        for (final entry in entries) {
          await txn.insert('transaction_entries', _entryRow(entry));
        }
      });
    });
  }

  @override
  Future<void> saveCreditCard(CreditCard card) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert('credit_cards', {
        'id': card.id,
        'user_id': card.userId,
        'name': card.name,
        'issuer': card.issuer,
        'brand': card.brand,
        'last_four_digits': card.lastFourDigits,
        'credit_limit': card.creditLimit.cents,
        'initial_used_limit': card.initialUsedLimit.cents,
        'closing_day': card.closingDay,
        'due_day': card.dueDay,
        'is_active': boolToSql(card.isActive),
        'created_at': formatTimestamp(card.createdAt),
        'updated_at': formatTimestamp(card.updatedAt),
        'deleted_at': card.deletedAt == null
            ? null
            : formatTimestamp(card.deletedAt!),
      });
    });
  }

  @override
  Future<CreditCard?> findCreditCard(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'credit_cards',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _card(rows.first);
    });
  }

  @override
  Future<void> applyCreditCardProfile({
    required String userId,
    required String cardId,
    required Money creditLimit,
    required DateTime updatedAt,
    String? brand,
    String? lastFourDigits,
    int? closingDay,
    int? dueDay,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.rawUpdate(
        '''
UPDATE credit_cards
SET credit_limit = ?,
    brand = CASE
      WHEN brand IS NULL OR brand = '' THEN COALESCE(?, brand)
      ELSE brand
    END,
    last_four_digits = CASE
      WHEN last_four_digits IS NULL OR last_four_digits = '' THEN COALESCE(?, last_four_digits)
      ELSE last_four_digits
    END,
    closing_day = COALESCE(closing_day, ?),
    due_day = COALESCE(due_day, ?),
    updated_at = ?
WHERE id = ?
  AND user_id = ?
  AND deleted_at IS NULL
  AND ? >= initial_used_limit
''',
        [
          creditLimit.cents,
          brand,
          lastFourDigits,
          closingDay,
          dueDay,
          formatTimestamp(updatedAt),
          cardId,
          userId,
          creditLimit.cents,
        ],
      );
    });
  }

  @override
  Future<List<CreditCard>> listCreditCards(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'credit_cards',
        where: 'user_id = ? AND deleted_at IS NULL',
        whereArgs: [userId],
        orderBy: 'name COLLATE NOCASE',
      );
      return [for (final row in rows) _card(row)];
    });
  }

  @override
  Future<List<CardUsage>> cardUsage(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT
  c.id AS card_id,
  c.initial_used_limit AS initial_used,
  COALESCE(SUM(
    CASE
      WHEN t.id IS NOT NULL
       AND t.status = 'confirmed'
       AND t.deleted_at IS NULL
      THEN e.amount
      ELSE 0
    END
  ), 0) AS entries_sum
FROM credit_cards c
LEFT JOIN transaction_entries e ON e.credit_card_id = c.id
LEFT JOIN transactions t ON t.id = e.transaction_id
WHERE c.user_id = ? AND c.deleted_at IS NULL
GROUP BY c.id, c.initial_used_limit
''',
        [userId],
      );
      return [
        for (final row in rows)
          CardUsage(
            cardId: row['card_id']! as String,
            initialUsed: Money(asInt(row['initial_used'])),
            confirmedEntries: Money(asInt(row['entries_sum'])),
          ),
      ];
    });
  }

  @override
  Future<void> saveCardPurchase({
    required Transaction transaction,
    required TransactionEntry entry,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.insert('transactions', _transactionRow(transaction));
        await txn.insert('transaction_entries', _entryRow(entry));
      });
    });
  }

  @override
  Future<void> saveCardPayment({
    required Transaction transaction,
    required List<TransactionEntry> entries,
    required String statementId,
    required String referenceMonth,
    required LocalDate closingDate,
    required LocalDate dueDate,
    required Money total,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.insert('transactions', _transactionRow(transaction));
        for (final entry in entries) {
          await txn.insert('transaction_entries', _entryRow(entry));
        }
        await txn.insert('credit_card_statements', {
          'id': statementId,
          'credit_card_id': transaction.creditCardId,
          'reference_month': referenceMonth,
          'closing_date': closingDate.toIso(),
          'due_date': dueDate.toIso(),
          'total_amount': total.cents,
          'status': 'paid',
        });
      });
    });
  }

  @override
  Future<void> saveRecurrence(Recurrence recurrence) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert('recurrences', _recurrenceRow(recurrence));
    });
  }

  @override
  Future<Recurrence?> findRecurrence(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'recurrences',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _recurrence(rows.first);
    });
  }

  @override
  Future<List<Recurrence>> listRecurrences(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'recurrences',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'name COLLATE NOCASE',
      );
      return [for (final row in rows) _recurrence(row)];
    });
  }

  @override
  Future<void> saveProvisions({
    required String recurrenceId,
    required LocalDate nextOccurrence,
    required DateTime updatedAt,
    required List<Provision> provisions,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        for (final provision in provisions) {
          await txn.rawInsert(
            '''
INSERT OR IGNORE INTO provisions (
  id, user_id, recurrence_id, description, amount, type, due_date, status,
  transaction_id, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
            [
              provision.id,
              provision.userId,
              provision.recurrenceId,
              provision.description,
              provision.amount.cents,
              provision.type.value,
              provision.dueDate.toIso(),
              provision.status.value,
              provision.transactionId,
              formatTimestamp(provision.createdAt),
              formatTimestamp(provision.updatedAt),
            ],
          );
        }
        await txn.update(
          'recurrences',
          {
            'next_occurrence': nextOccurrence.toIso(),
            'updated_at': formatTimestamp(updatedAt),
          },
          where: 'id = ?',
          whereArgs: [recurrenceId],
        );
      });
    });
  }

  @override
  Future<Provision?> findProvision(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'provisions',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _provision(rows.first);
    });
  }

  @override
  Future<List<Provision>> listProvisions(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'provisions',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'due_date',
      );
      return [for (final row in rows) _provision(row)];
    });
  }

  @override
  Future<void> settleProvision({
    required String provisionId,
    required DateTime updatedAt,
    required Transaction transaction,
    required List<TransactionEntry> entries,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.insert('transactions', _transactionRow(transaction));
        for (final entry in entries) {
          await txn.insert('transaction_entries', _entryRow(entry));
        }
        final updated = await txn.update(
          'provisions',
          {
            'status': ProvisionStatus.settled.value,
            'transaction_id': transaction.id,
            'updated_at': formatTimestamp(updatedAt),
          },
          where: 'id = ? AND status IN (?, ?, ?)',
          whereArgs: [
            provisionId,
            ProvisionStatus.pending.value,
            ProvisionStatus.due.value,
            ProvisionStatus.overdue.value,
          ],
        );
        if (updated == 0) {
          throw StateError('provision-closed');
        }
      });
    });
  }

  @override
  Future<Money> openProvisionSum({
    required String userId,
    required TransactionType type,
    required LocalDate through,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT COALESCE(SUM(amount), 0) AS total
FROM provisions
WHERE user_id = ?
  AND type = ?
  AND status IN ('pending', 'due', 'overdue')
  AND due_date <= ?
''',
        [userId, type.value, through.toIso()],
      );
      return Money(asInt(rows.first['total']));
    });
  }

  @override
  Future<void> saveInvestment(Investment investment) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert('investments', {
        'id': investment.id,
        'user_id': investment.userId,
        'name': investment.name,
        'institution': investment.institution,
        'account_id': investment.accountId,
        'type': investment.kind.value,
        'currency': investment.currency,
        'current_value': investment.currentValue.cents,
        'is_active': boolToSql(investment.isActive),
        'created_at': formatTimestamp(investment.createdAt),
        'updated_at': formatTimestamp(investment.updatedAt),
        'deleted_at': investment.deletedAt == null
            ? null
            : formatTimestamp(investment.deletedAt!),
      });
    });
  }

  @override
  Future<Investment?> findInvestment(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'investments',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _investment(rows.first);
    });
  }

  @override
  Future<void> updateInvestment(Investment investment) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.rawUpdate(
        '''
UPDATE investments
SET name = ?, institution = ?, account_id = ?, type = ?, is_active = ?,
    updated_at = ?,
    deleted_at = ?, sync_version = sync_version + 1
WHERE id = ?
''',
        [
          investment.name,
          investment.institution,
          investment.accountId,
          investment.kind.value,
          boolToSql(investment.isActive),
          formatTimestamp(investment.updatedAt),
          investment.deletedAt == null
              ? null
              : formatTimestamp(investment.deletedAt!),
          investment.id,
        ],
      );
    });
  }

  @override
  Future<List<OrphanInvestmentMovement>> orphanMovements(String investmentId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT it.id AS id, it.type AS type, it.amount AS amount,
       it.transaction_date AS transaction_date, it.description AS description
FROM investment_transactions it
LEFT JOIN transactions t ON t.id = it.linked_transaction_id
WHERE it.investment_id = ?
  AND (it.linked_transaction_id IS NULL OR t.id IS NULL
       OR t.deleted_at IS NOT NULL)
ORDER BY it.transaction_date
''',
        [investmentId],
      );
      return [
        for (final row in rows)
          OrphanInvestmentMovement(
            id: row['id']! as String,
            type: InvestmentMovementType.fromValue(row['type']! as String),
            amount: Money(asInt(row['amount'])),
            date: LocalDate.parse(row['transaction_date']! as String),
            description: row['description'] as String?,
          ),
      ];
    });
  }

  @override
  Future<void> removeInvestmentMovements({
    required String investmentId,
    required List<String> movementIds,
    required Money currentValue,
    required DateTime updatedAt,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        for (final id in movementIds) {
          await txn.delete(
            'investment_transactions',
            where: 'id = ? AND investment_id = ?',
            whereArgs: [id, investmentId],
          );
        }
        await txn.update(
          'investments',
          {
            'current_value': currentValue.cents,
            'updated_at': formatTimestamp(updatedAt),
          },
          where: 'id = ?',
          whereArgs: [investmentId],
        );
      });
    });
  }

  @override
  Future<List<Investment>> listInvestments(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'investments',
        where: 'user_id = ? AND deleted_at IS NULL',
        whereArgs: [userId],
        orderBy: 'name COLLATE NOCASE',
      );
      return [for (final row in rows) _investment(row)];
    });
  }

  @override
  Future<List<({InvestmentMovementType type, Money amount})>> movementsFor(
    String investmentId,
  ) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'investment_transactions',
        columns: const ['type', 'amount'],
        where: 'investment_id = ?',
        whereArgs: [investmentId],
      );
      return [
        for (final row in rows)
          (
            type: InvestmentMovementType.fromValue(row['type']! as String),
            amount: Money(asInt(row['amount'])),
          ),
      ];
    });
  }

  @override
  Future<void> saveInvestmentMovement({
    required InvestmentMovementDraft movement,
    required Money currentValue,
    required DateTime updatedAt,
    required Transaction transaction,
    required List<TransactionEntry> entries,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.insert('transactions', _transactionRow(transaction));
        for (final entry in entries) {
          await txn.insert('transaction_entries', _entryRow(entry));
        }
        await txn.insert('investment_transactions', {
          'id': movement.id,
          'investment_id': movement.investmentId,
          'type': movement.type.value,
          'amount': movement.amount.cents,
          'transaction_date': movement.date.toIso(),
          'description': movement.description,
          'linked_transaction_id': movement.linkedTransactionId,
          'created_at': formatTimestamp(movement.createdAt),
        });
        await txn.update(
          'investments',
          {
            'current_value': currentValue.cents,
            'updated_at': formatTimestamp(updatedAt),
          },
          where: 'id = ?',
          whereArgs: [movement.investmentId],
        );
      });
    });
  }

  @override
  Future<void> linkInvestmentCash({
    required String transactionId,
    required InvestmentMovementDraft movement,
    required Money currentValue,
    required DateTime updatedAt,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        final changed = await txn.update(
          'transactions',
          {
            'investment_id': movement.investmentId,
            'updated_at': formatTimestamp(updatedAt),
          },
          where: 'id = ? AND investment_id IS NULL AND deleted_at IS NULL',
          whereArgs: [transactionId],
        );
        if (changed != 1) {
          throw const ValidationException(
            'Lançamento inválido ou já vinculado.',
          );
        }
        await txn.insert('investment_transactions', {
          'id': movement.id,
          'investment_id': movement.investmentId,
          'type': movement.type.value,
          'amount': movement.amount.cents,
          'transaction_date': movement.date.toIso(),
          'description': movement.description,
          'linked_transaction_id': movement.linkedTransactionId,
          'created_at': formatTimestamp(movement.createdAt),
        });
        await txn.update(
          'investments',
          {
            'current_value': currentValue.cents,
            'updated_at': formatTimestamp(updatedAt),
          },
          where: 'id = ?',
          whereArgs: [movement.investmentId],
        );
      });
    });
  }

  @override
  Future<void> unlinkInvestmentCash({
    required String transactionId,
    required String investmentId,
    required Money currentValue,
    required DateTime updatedAt,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        final changed = await txn.update(
          'transactions',
          {
            'investment_id': null,
            'updated_at': formatTimestamp(updatedAt),
          },
          where:
              'id = ? AND investment_id = ? AND deleted_at IS NULL',
          whereArgs: [transactionId, investmentId],
        );
        if (changed != 1) {
          throw const ValidationException(
            'Lançamento inválido ou já desvinculado.',
          );
        }
        await txn.delete(
          'investment_transactions',
          where: 'linked_transaction_id = ? AND investment_id = ?',
          whereArgs: [transactionId, investmentId],
        );
        await txn.update(
          'investments',
          {
            'current_value': currentValue.cents,
            'updated_at': formatTimestamp(updatedAt),
          },
          where: 'id = ?',
          whereArgs: [investmentId],
        );
      });
    });
  }

  @override
  Future<Money> movementSum({
    required String userId,
    required InvestmentMovementType type,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT COALESCE(SUM(it.amount), 0) AS total
FROM investment_transactions it
JOIN investments i ON i.id = it.investment_id
WHERE i.user_id = ?
  AND i.deleted_at IS NULL
  AND it.type = ?
  AND it.transaction_date >= ?
  AND it.transaction_date < ?
''',
        [userId, type.value, fromInclusive.toIso(), toExclusive.toIso()],
      );
      return Money(asInt(rows.first['total']));
    });
  }

  @override
  Future<Map<String, List<DatedInvestmentMovement>>> movementsByInvestment(
    String userId,
  ) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT it.investment_id AS investment_id, it.type AS type,
       it.amount AS amount, it.transaction_date AS transaction_date
FROM investment_transactions it
JOIN investments i ON i.id = it.investment_id
WHERE i.user_id = ? AND i.deleted_at IS NULL
ORDER BY it.transaction_date
''',
        [userId],
      );
      final result = <String, List<DatedInvestmentMovement>>{};
      for (final row in rows) {
        result
            .putIfAbsent(row['investment_id']! as String, () => [])
            .add(
              DatedInvestmentMovement(
                date: LocalDate.parse(row['transaction_date']! as String),
                type: InvestmentMovementType.fromValue(row['type']! as String),
                amount: Money(asInt(row['amount'])),
              ),
            );
      }
      return result;
    });
  }

  @override
  Future<List<DatedInvestmentMovement>> investmentMovements(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT it.type AS type, it.amount AS amount, it.transaction_date AS transaction_date
FROM investment_transactions it
JOIN investments i ON i.id = it.investment_id
WHERE i.user_id = ? AND i.deleted_at IS NULL
ORDER BY it.transaction_date
''',
        [userId],
      );
      return [
        for (final row in rows)
          DatedInvestmentMovement(
            date: LocalDate.parse(row['transaction_date']! as String),
            type: InvestmentMovementType.fromValue(row['type']! as String),
            amount: Money(asInt(row['amount'])),
          ),
      ];
    });
  }

  @override
  Future<List<DailyAccountTotal>> cardDailyTotals(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT e.credit_card_id AS card_id, t.transaction_date AS transaction_date,
       SUM(e.amount) AS total
FROM transaction_entries e
INNER JOIN transactions t ON t.id = e.transaction_id
INNER JOIN credit_cards c ON c.id = e.credit_card_id
WHERE c.user_id = ?
  AND c.deleted_at IS NULL
  AND t.deleted_at IS NULL
  AND t.status = 'confirmed'
GROUP BY e.credit_card_id, t.transaction_date
''',
        [userId],
      );
      return [
        for (final row in rows)
          DailyAccountTotal(
            accountId: row['card_id']! as String,
            date: LocalDate.parse(row['transaction_date']! as String),
            amount: Money(asInt(row['total'])),
          ),
      ];
    });
  }

  @override
  Future<void> saveGoal(FinancialGoal goal) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert('financial_goals', {
        'id': goal.id,
        'user_id': goal.userId,
        'name': goal.name,
        'target_amount': goal.targetAmount.cents,
        'current_amount': goal.currentAmount.cents,
        'target_date': goal.targetDate?.toIso(),
        'expected_monthly_return_rate': goal.expectedMonthlyReturnRate,
        'expected_monthly_savings': goal.expectedMonthlySavings.cents,
        'goal_type': goal.goalType.value,
        'is_active': boolToSql(goal.isActive),
        'created_at': formatTimestamp(goal.createdAt),
        'updated_at': formatTimestamp(goal.updatedAt),
      });
    });
  }

  @override
  Future<List<FinancialGoal>> listGoals(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'financial_goals',
        where: 'user_id = ? AND is_active = 1',
        whereArgs: [userId],
        orderBy: 'name COLLATE NOCASE',
      );
      return [for (final row in rows) _goal(row)];
    });
  }

  @override
  Future<void> saveEmergency(EmergencySettings settings) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.delete(
          'emergency_fund_settings',
          where: 'user_id = ?',
          whereArgs: [settings.userId],
        );
        await txn.delete(
          'emergency_fund_categories',
          where: 'user_id = ?',
          whereArgs: [settings.userId],
        );
        await txn.insert('emergency_fund_settings', {
          'id': settings.id,
          'user_id': settings.userId,
          'target_months': settings.targetMonths,
          'manual_target_amount': settings.manualTargetAmount?.cents,
          'use_automatic_calculation': boolToSql(
            settings.useAutomaticCalculation,
          ),
          'created_at': formatTimestamp(settings.createdAt),
          'updated_at': formatTimestamp(settings.updatedAt),
        });
        for (final categoryId in settings.essentialCategoryIds) {
          final id = categoryId.trim();
          if (id.isEmpty) continue;
          await txn.insert('emergency_fund_categories', {
            'user_id': settings.userId,
            'category_id': id,
          });
        }
      });
    });
  }

  @override
  Future<EmergencySettings?> findEmergency(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'emergency_fund_settings',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      final manual = row['manual_target_amount'];
      final categoryRows = await database.query(
        'emergency_fund_categories',
        columns: const ['category_id'],
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      return EmergencySettings(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        targetMonths: asInt(row['target_months']),
        manualTargetAmount: manual == null ? null : Money(asInt(manual)),
        useAutomaticCalculation: boolFromSql(row['use_automatic_calculation']),
        essentialCategoryIds: [
          for (final category in categoryRows)
            category['category_id']! as String,
        ],
        createdAt: parseTimestamp(row['created_at']! as String),
        updatedAt: parseTimestamp(row['updated_at']! as String),
      );
    });
  }

  @override
  Future<List<RecordedTransferMatch>> findCoveringTransfers({
    required String userId,
    required String accountId,
    required Money amount,
    required LocalDate date,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT
  t.id AS transaction_id,
  tr.source_account_id AS source_account_id,
  tr.destination_account_id AS destination_account_id
FROM transfers tr
JOIN transactions t ON t.transfer_id = tr.id
WHERE tr.user_id = ?
  AND t.deleted_at IS NULL
  AND t.status = 'confirmed'
  AND tr.amount = ?
  AND tr.transaction_date >= ?
  AND tr.transaction_date <= ?
  AND (tr.source_account_id = ? OR tr.destination_account_id = ?)
''',
        [
          userId,
          amount.cents,
          date.addDays(-2).toIso(),
          date.addDays(2).toIso(),
          accountId,
          accountId,
        ],
      );
      return [
        for (final row in rows)
          RecordedTransferMatch(
            transactionId: row['transaction_id']! as String,
            sourceAccountId: row['source_account_id']! as String,
            destinationAccountId: row['destination_account_id']! as String,
          ),
      ];
    });
  }

  @override
  Future<TransferPairSuggestion?> findTransferPair(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT
  e.id AS expense_id,
  e.account_id AS expense_account_id,
  e.description AS expense_description,
  e.amount AS amount,
  e.transaction_date AS transaction_date,
  i.id AS income_id,
  i.account_id AS income_account_id,
  i.description AS income_description
FROM transactions e
JOIN transactions i
  ON i.user_id = e.user_id
 AND i.amount = e.amount
 AND i.transaction_date = e.transaction_date
 AND i.account_id != e.account_id
 AND i.deleted_at IS NULL
 AND i.status = 'confirmed'
 AND i.type = 'income'
WHERE e.user_id = ?
  AND e.deleted_at IS NULL
  AND e.status = 'confirmed'
  AND e.type = 'expense'
  AND e.account_id IS NOT NULL
  AND i.account_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM dismissed_transfer_pairs d
    WHERE d.user_id = e.user_id
      AND d.transaction_a_id = CASE WHEN e.id < i.id THEN e.id ELSE i.id END
      AND d.transaction_b_id = CASE WHEN e.id < i.id THEN i.id ELSE e.id END
  )
LIMIT 1
''',
        [userId],
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      return TransferPairSuggestion(
        expenseTransactionId: row['expense_id']! as String,
        incomeTransactionId: row['income_id']! as String,
        expenseAccountId: row['expense_account_id']! as String,
        incomeAccountId: row['income_account_id']! as String,
        amount: Money(asInt(row['amount'])),
        date: LocalDate.parse(row['transaction_date']! as String),
        expenseDescription: (row['expense_description'] as String?) ?? 'Despesa',
        incomeDescription: (row['income_description'] as String?) ?? 'Receita',
      );
    });
  }

  @override
  Future<void> dismissTransferPair({
    required String id,
    required String userId,
    required String firstTransactionId,
    required String secondTransactionId,
    required DateTime createdAt,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final ordered = [firstTransactionId, secondTransactionId]..sort();
      await database.rawInsert(
        '''
INSERT OR IGNORE INTO dismissed_transfer_pairs (
  id, user_id, transaction_a_id, transaction_b_id, created_at
) VALUES (?, ?, ?, ?, ?)
''',
        [
          id,
          userId,
          ordered[0],
          ordered[1],
          formatTimestamp(createdAt),
        ],
      );
    });
  }

  @override
  Future<void> convertPairToTransfer({
    required String userId,
    required String expenseTransactionId,
    required String incomeTransactionId,
    required String sourceAccountId,
    required String destinationAccountId,
    required Money amount,
    required LocalDate date,
    required String description,
    required DateTime now,
    required String transferId,
    required String transactionId,
    required String sourceEntryId,
    required String destinationEntryId,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        final stamp = formatTimestamp(now);
        for (final id in [expenseTransactionId, incomeTransactionId]) {
          final updated = await txn.update(
            'transactions',
            {'deleted_at': stamp, 'updated_at': stamp},
            where: 'id = ? AND user_id = ? AND deleted_at IS NULL',
            whereArgs: [id, userId],
          );
          if (updated != 1) {
            throw StateError('pair-missing');
          }
        }
        await txn.insert('transfers', {
          'id': transferId,
          'user_id': userId,
          'source_account_id': sourceAccountId,
          'destination_account_id': destinationAccountId,
          'amount': amount.cents,
          'transaction_date': date.toIso(),
          'description': description,
          'status': 'confirmed',
          'created_at': stamp,
          'updated_at': stamp,
        });
        await txn.insert('transactions', {
          'id': transactionId,
          'user_id': userId,
          'type': 'transfer',
          'amount': amount.cents,
          'description': description,
          'transaction_date': date.toIso(),
          'status': 'confirmed',
          'account_id': sourceAccountId,
          'transfer_id': transferId,
          'source': 'manual',
          'created_at': stamp,
          'updated_at': stamp,
        });
        await txn.insert('transaction_entries', {
          'id': sourceEntryId,
          'transaction_id': transactionId,
          'account_id': sourceAccountId,
          'amount': -amount.cents,
          'created_at': stamp,
        });
        await txn.insert('transaction_entries', {
          'id': destinationEntryId,
          'transaction_id': transactionId,
          'account_id': destinationAccountId,
          'amount': amount.cents,
          'created_at': stamp,
        });
      });
    });
  }
}

Map<String, Object?> _transactionRow(Transaction transaction) {
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
    'credit_card_id': transaction.creditCardId,
    'transfer_id': transaction.transferId,
    'investment_id': transaction.investmentId,
    'recurrence_id': transaction.recurrenceId,
    'provision_id': transaction.provisionId,
    'paired_transaction_id': transaction.pairedTransactionId,
  };
}

Map<String, Object?> _entryRow(TransactionEntry entry) {
  return {
    'id': entry.id,
    'transaction_id': entry.transactionId,
    'account_id': entry.accountId,
    'amount': entry.amount.cents,
    'created_at': formatTimestamp(entry.createdAt),
    'credit_card_id': entry.creditCardId,
    'investment_id': entry.investmentId,
  };
}

Map<String, Object?> _recurrenceRow(Recurrence recurrence) {
  return {
    'id': recurrence.id,
    'user_id': recurrence.userId,
    'name': recurrence.name,
    'type': recurrence.type.value,
    'amount': recurrence.amount.cents,
    'category_id': recurrence.categoryId,
    'account_id': recurrence.accountId,
    'credit_card_id': recurrence.creditCardId,
    'frequency': recurrence.frequency.value,
    'interval_value': recurrence.intervalValue,
    'start_date': recurrence.startDate.toIso(),
    'end_date': recurrence.endDate?.toIso(),
    'next_occurrence': recurrence.nextOccurrence.toIso(),
    'is_active': boolToSql(recurrence.isActive),
    'created_at': formatTimestamp(recurrence.createdAt),
    'updated_at': formatTimestamp(recurrence.updatedAt),
  };
}

CreditCard _card(Map<String, Object?> row) {
  final deletedAt = row['deleted_at'] as String?;
  return CreditCard(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    name: row['name']! as String,
    issuer: row['issuer'] as String?,
    brand: row['brand'] as String?,
    lastFourDigits: row['last_four_digits'] as String?,
    creditLimit: Money(asInt(row['credit_limit'])),
    initialUsedLimit: Money(asInt(row['initial_used_limit'])),
    closingDay: row['closing_day'] == null ? null : asInt(row['closing_day']),
    dueDay: row['due_day'] == null ? null : asInt(row['due_day']),
    isActive: boolFromSql(row['is_active']),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
    deletedAt: deletedAt == null ? null : parseTimestamp(deletedAt),
  );
}

Recurrence _recurrence(Map<String, Object?> row) {
  final end = row['end_date'] as String?;
  return Recurrence(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    name: row['name']! as String,
    type: TransactionType.fromValue(row['type']! as String),
    amount: Money(asInt(row['amount'])),
    categoryId: row['category_id'] as String?,
    accountId: row['account_id'] as String?,
    creditCardId: row['credit_card_id'] as String?,
    frequency: RecurrenceFrequency.fromValue(row['frequency']! as String),
    intervalValue: asInt(row['interval_value']),
    startDate: LocalDate.parse(row['start_date']! as String),
    endDate: end == null ? null : LocalDate.parse(end),
    nextOccurrence: LocalDate.parse(row['next_occurrence']! as String),
    isActive: boolFromSql(row['is_active']),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
  );
}

Provision _provision(Map<String, Object?> row) {
  return Provision(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    recurrenceId: row['recurrence_id'] as String?,
    description: row['description']! as String,
    amount: Money(asInt(row['amount'])),
    type: TransactionType.fromValue(row['type']! as String),
    dueDate: LocalDate.parse(row['due_date']! as String),
    status: ProvisionStatus.fromValue(row['status']! as String),
    transactionId: row['transaction_id'] as String?,
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
  );
}

Investment _investment(Map<String, Object?> row) {
  final deletedAt = row['deleted_at'] as String?;
  return Investment(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    name: row['name']! as String,
    institution: row['institution'] as String?,
    accountId: row['account_id'] as String?,
    kind: InvestmentKind.fromValue(row['type']! as String),
    currency: row['currency']! as String,
    currentValue: Money(asInt(row['current_value'])),
    isActive: boolFromSql(row['is_active']),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
    deletedAt: deletedAt == null ? null : parseTimestamp(deletedAt),
  );
}

FinancialGoal _goal(Map<String, Object?> row) {
  final targetDate = row['target_date'] as String?;
  final rate = row['expected_monthly_return_rate'];
  return FinancialGoal(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    name: row['name']! as String,
    targetAmount: Money(asInt(row['target_amount'])),
    currentAmount: Money(asInt(row['current_amount'])),
    targetDate: targetDate == null ? null : LocalDate.parse(targetDate),
    expectedMonthlyReturnRate: rate == null ? 0 : (rate as num).toDouble(),
    expectedMonthlySavings: Money(asInt(row['expected_monthly_savings'] ?? 0)),
    goalType: GoalType.fromValue(row['goal_type']! as String),
    isActive: boolFromSql(row['is_active']),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
  );
}
