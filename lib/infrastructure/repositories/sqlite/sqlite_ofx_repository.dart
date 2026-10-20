import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/repositories/ofx_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';

class SqliteOfxRepository implements OfxRepository {
  SqliteOfxRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> save(OfxImportBundle bundle) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        await txn.insert('ofx_imports', {
          'id': bundle.header.id,
          'user_id': bundle.header.userId,
          'account_id': bundle.header.accountId,
          'file_name': bundle.header.fileName,
          'imported_at': formatTimestamp(bundle.header.importedAt),
          'total_records': bundle.header.totalRecords,
          'imported_records': bundle.header.importedRecords,
          'duplicate_records': bundle.header.duplicateRecords,
          'ignored_records': bundle.header.ignoredRecords,
        });
        for (final line in bundle.lines) {
          await txn.insert('ofx_import_transactions', {
            'id': line.id,
            'import_id': line.importId,
            'fit_id': line.fitId,
            'transaction_type': line.transactionType,
            'posted_at': line.postedAt,
            'amount': line.amountCents,
            'name': line.name,
            'memo': line.memo,
            'check_number': line.checkNumber,
            'reference_number': line.referenceNumber,
            'raw_hash': line.rawHash,
            'duplicate_score': line.duplicateScore,
            'duplicate_status': line.duplicateStatus,
            'matched_transaction_id': line.matchedTransactionId,
            'reconciliation_status': line.reconciliationStatus,
            'created_at': formatTimestamp(line.createdAt),
          });
        }
        for (final id in bundle.retireTransactionIds) {
          await txn.update(
            'transactions',
            {
              'deleted_at': formatTimestamp(bundle.header.importedAt),
              'updated_at': formatTimestamp(bundle.header.importedAt),
            },
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [id],
          );
        }
        for (final transfer in bundle.transfers) {
          final stamp = formatTimestamp(transfer.createdAt);
          await txn.insert('transfers', {
            'id': transfer.id,
            'user_id': transfer.userId,
            'source_account_id': transfer.sourceAccountId,
            'destination_account_id': transfer.destinationAccountId,
            'amount': transfer.amount.cents,
            'transaction_date': transfer.date.toIso(),
            'description': transfer.description,
            'status': 'confirmed',
            'created_at': stamp,
            'updated_at': stamp,
          });
        }
        for (final transaction in bundle.transactions) {
          await txn.insert('transactions', _transactionRow(transaction));
        }
        for (final entry in bundle.entries) {
          await txn.insert('transaction_entries', _entryRow(entry));
        }
      });
    });
  }

  @override
  Future<bool> wasReconciledFitId({
    required String userId,
    required String accountId,
    required String fitId,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT lit.id
FROM ofx_import_transactions lit
JOIN ofx_imports i ON i.id = lit.import_id
WHERE i.user_id = ?
  AND i.account_id = ?
  AND lit.fit_id = ?
  AND lit.reconciliation_status = 'reconciled'
LIMIT 1
''',
        [userId, accountId, fitId],
      );
      return rows.isNotEmpty;
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
    'transfer_id': transaction.transferId,
  };
}

Map<String, Object?> _entryRow(TransactionEntry entry) {
  return {
    'id': entry.id,
    'transaction_id': entry.transactionId,
    'account_id': entry.accountId,
    'amount': entry.amount.cents,
    'created_at': formatTimestamp(entry.createdAt),
  };
}
