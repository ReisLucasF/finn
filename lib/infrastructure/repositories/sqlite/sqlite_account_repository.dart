import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';
import 'package:sqflite/sqflite.dart';

class SqliteAccountRepository implements AccountRepository {
  SqliteAccountRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> save(Account account) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert(
        'accounts',
        _toRow(account),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<Account?> findById(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _map(rows.first);
    });
  }

  @override
  Future<List<Account>> listByUser(
    String userId, {
    bool includeInactive = true,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'accounts',
        where: includeInactive
            ? 'user_id = ? AND deleted_at IS NULL'
            : 'user_id = ? AND deleted_at IS NULL AND is_active = 1',
        whereArgs: [userId],
        orderBy: 'is_active DESC, name COLLATE NOCASE ASC',
      );
      return rows.map(_map).toList();
    });
  }
}

Map<String, Object?> _toRow(Account account) {
  return {
    'id': account.id,
    'user_id': account.userId,
    'name': account.name,
    'institution_name': account.institutionName,
    'institution_code': account.institutionCode,
    'account_type': account.type.value,
    'currency': account.currency,
    'initial_balance': account.initialBalance.cents,
    'is_active': boolToSql(account.isActive),
    'created_at': formatTimestamp(account.createdAt),
    'updated_at': formatTimestamp(account.updatedAt),
    'deleted_at': account.deletedAt == null
        ? null
        : formatTimestamp(account.deletedAt!),
  };
}

Account _map(Map<String, Object?> row) {
  final deletedAt = row['deleted_at'] as String?;
  return Account(
    id: row['id']! as String,
    userId: row['user_id']! as String,
    name: row['name']! as String,
    institutionName: row['institution_name'] as String?,
    institutionCode: row['institution_code'] as String?,
    type: AccountType.fromValue(row['account_type']! as String),
    currency: row['currency']! as String,
    initialBalance: Money(asInt(row['initial_balance'])),
    isActive: boolFromSql(row['is_active']),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
    deletedAt: deletedAt == null ? null : parseTimestamp(deletedAt),
  );
}
