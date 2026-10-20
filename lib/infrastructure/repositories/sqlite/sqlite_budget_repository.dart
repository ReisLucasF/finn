import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/budget.dart';
import 'package:finan/domain/repositories/budget_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';

class SqliteBudgetRepository implements BudgetRepository {
  SqliteBudgetRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> save(Budget budget) {
    return guardSqlite(() async {
      final database = await _database.open();
      // Um orçamento por categoria: atualiza o existente mantendo o id.
      // (Sem UPSERT, que exige SQLite 3.24+ e falha em Androids antigos.)
      await database.transaction((txn) async {
        final existing = await txn.query(
          'budgets',
          columns: ['id'],
          where: 'user_id = ? AND category_id = ?',
          whereArgs: [budget.userId, budget.categoryId],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('budgets', {
            'id': budget.id,
            'user_id': budget.userId,
            'category_id': budget.categoryId,
            'monthly_limit': budget.monthlyLimit.cents,
            'is_active': boolToSql(budget.isActive),
            'created_at': formatTimestamp(budget.createdAt),
            'updated_at': formatTimestamp(budget.updatedAt),
          });
          return;
        }
        await txn.rawUpdate(
          '''
UPDATE budgets
SET monthly_limit = ?, is_active = ?, updated_at = ?,
    sync_version = sync_version + 1
WHERE id = ?
''',
          [
            budget.monthlyLimit.cents,
            boolToSql(budget.isActive),
            formatTimestamp(budget.updatedAt),
            existing.first['id'],
          ],
        );
      });
    });
  }

  @override
  Future<void> delete(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.delete('budgets', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<List<Budget>> listByUser(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'budgets',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'created_at',
      );
      return [
        for (final row in rows)
          Budget(
            id: row['id']! as String,
            userId: row['user_id']! as String,
            categoryId: row['category_id']! as String,
            monthlyLimit: Money(asInt(row['monthly_limit'])),
            isActive: boolFromSql(row['is_active']),
            createdAt: parseTimestamp(row['created_at']! as String),
            updatedAt: parseTimestamp(row['updated_at']! as String),
          ),
      ];
    });
  }
}
