import 'package:finan/domain/pluggy/pluggy_item_id.dart';
import 'package:finan/domain/pluggy/pluggy_models.dart';
import 'package:finan/domain/repositories/pluggy_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';
import 'package:sqflite/sqflite.dart';

class SqlitePluggyRepository implements PluggyRepository {
  SqlitePluggyRepository(this._database);

  final AppDatabase _database;

  @override
  Future<PluggyConnection?> find(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'pluggy_connections',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;
      final itemId = row['item_id']! as String;
      return PluggyConnection(
        userId: userId,
        clientId: row['client_id']! as String,
        clientSecret: row['client_secret']! as String,
        itemId: isPluggyItemId(itemId) ? itemId : '',
      );
    });
  }

  @override
  Future<void> save(PluggyConnection connection, DateTime updatedAt) {
    return guardSqlite(() async {
      final database = await _database.open();
      final itemId = isPluggyItemId(connection.itemId) ? connection.itemId.trim() : '';
      await database.insert('pluggy_connections', {
        'user_id': connection.userId,
        'client_id': connection.clientId,
        'client_secret': connection.clientSecret,
        'item_id': itemId,
        'updated_at': formatTimestamp(updatedAt),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> saveLink(PluggyAccountLink link) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert('pluggy_account_links', {
        'pluggy_account_id': link.pluggyAccountId,
        'user_id': link.userId,
        'name': link.name,
        'kind': link.kind,
        'item_id': isPluggyItemId(link.itemId) ? link.itemId!.trim() : null,
        'account_id': link.accountId,
        'credit_card_id': link.creditCardId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<List<PluggyAccountLink>> links(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'pluggy_account_links',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      return [
        for (final row in rows)
          PluggyAccountLink(
            pluggyAccountId: row['pluggy_account_id']! as String,
            userId: userId,
            name: row['name']! as String,
            kind: row['kind']! as String,
            itemId: row['item_id'] as String?,
            accountId: row['account_id'] as String?,
            creditCardId: row['credit_card_id'] as String?,
          ),
      ];
    });
  }

  @override
  Future<Map<String, String?>> categoryLinks(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'pluggy_category_links',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      return {
        for (final row in rows)
          row['pluggy_category']! as String: row['category_id'] as String?,
      };
    });
  }

  @override
  Future<void> saveCategoryLink({
    required String userId,
    required String pluggyCategory,
    required String? categoryId,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert('pluggy_category_links', {
        'user_id': userId,
        'pluggy_category': pluggyCategory,
        'category_id': categoryId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> rememberItem(PluggyItem item, String userId, DateTime updatedAt) {
    if (!isPluggyItemId(item.id)) return Future.value();
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert('pluggy_items', {
        'item_id': item.id.trim(),
        'user_id': userId,
        'connector_name': item.connectorName,
        'status': item.status,
        'updated_at': formatTimestamp(updatedAt),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<List<PluggyItem>> items(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      await _purgeInvalid(database, userId);
      final rows = await database.query(
        'pluggy_items',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'updated_at DESC',
      );
      return [
        for (final row in rows)
          if (isPluggyItemId(row['item_id'] as String?))
            PluggyItem(
              id: row['item_id']! as String,
              connectorName: row['connector_name']! as String,
              status: row['status'] as String?,
            ),
      ];
    });
  }

  @override
  Future<void> forgetItem(String itemId, String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.delete(
        'pluggy_items',
        where: 'item_id = ? AND user_id = ?',
        whereArgs: [itemId, userId],
      );
      final connection = await database.query(
        'pluggy_connections',
        where: 'user_id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      if (connection.isNotEmpty && connection.first['item_id'] == itemId) {
        await database.update(
          'pluggy_connections',
          {'item_id': ''},
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }
    });
  }

  @override
  Future<void> deleteLink(String pluggyAccountId, String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.delete(
        'pluggy_account_links',
        where: 'pluggy_account_id = ? AND user_id = ?',
        whereArgs: [pluggyAccountId, userId],
      );
    });
  }

  @override
  Future<void> deleteLinksForItem(String itemId, String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.delete(
        'pluggy_account_links',
        where: 'item_id = ? AND user_id = ?',
        whereArgs: [itemId, userId],
      );
    });
  }

  @override
  Future<void> purgeInvalidItems(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      await _purgeInvalid(database, userId);
    });
  }

  Future<void> _purgeInvalid(DatabaseExecutor database, String userId) async {
    final rows = await database.query(
      'pluggy_items',
      columns: const ['item_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    for (final row in rows) {
      final id = row['item_id'] as String?;
      if (isPluggyItemId(id)) continue;
      await database.delete(
        'pluggy_items',
        where: 'item_id = ? AND user_id = ?',
        whereArgs: [id, userId],
      );
    }
    final connection = await database.query(
      'pluggy_connections',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (connection.isEmpty) return;
    final itemId = connection.first['item_id'] as String?;
    if (isPluggyItemId(itemId)) return;
    await database.update(
      'pluggy_connections',
      {'item_id': ''},
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}
