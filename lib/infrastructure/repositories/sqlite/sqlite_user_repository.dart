import 'package:finan/domain/entities/user.dart';
import 'package:finan/domain/repositories/user_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';
import 'package:sqflite/sqflite.dart';

class SqliteUserRepository implements UserRepository {
  SqliteUserRepository(this._database);

  final AppDatabase _database;

  @override
  Future<AppUser?> findCurrent() {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'users',
        orderBy: 'created_at ASC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _map(rows.first);
    });
  }

  @override
  Future<void> save(AppUser user) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert(
        'users',
        _toRow(user),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}

Map<String, Object?> _toRow(AppUser user) {
  return {
    'id': user.id,
    'name': user.name,
    'email': user.email,
    'currency': user.currency,
    'locale': user.locale,
    'timezone': user.timezone,
    'financial_month_start': user.financialMonthStart,
    'created_at': formatTimestamp(user.createdAt),
    'updated_at': formatTimestamp(user.updatedAt),
  };
}

AppUser _map(Map<String, Object?> row) {
  return AppUser(
    id: row['id']! as String,
    name: row['name']! as String,
    email: row['email'] as String?,
    currency: row['currency']! as String,
    locale: row['locale']! as String,
    timezone: row['timezone']! as String,
    financialMonthStart: asInt(row['financial_month_start']),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
  );
}
