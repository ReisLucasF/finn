import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';
import 'package:sqflite/sqflite.dart';

class SqliteCategoryRepository implements CategoryRepository {
  SqliteCategoryRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> save(Category category) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.insert(
        'categories',
        _toRow(category),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  @override
  Future<Category?> findById(String id) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _map(rows.first);
    });
  }

  @override
  Future<List<Category>> listByUser(
    String userId, {
    CategoryType? type,
    bool includeInactive = true,
  }) {
    return guardSqlite(() async {
      final database = await _database.open();
      final where = StringBuffer(
        'deleted_at IS NULL AND (user_id IS NULL OR user_id = ?)',
      );
      final args = <Object?>[userId];
      if (!includeInactive) {
        where.write(' AND is_active = 1');
      }
      if (type != null) {
        where.write(' AND type = ?');
        args.add(type.value);
      }
      final rows = await database.query(
        'categories',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'type ASC, name COLLATE NOCASE ASC',
      );
      return rows.map(_map).toList();
    });
  }
}

Map<String, Object?> _toRow(Category category) {
  return {
    'id': category.id,
    'user_id': category.userId,
    'name': category.name,
    'type': category.type.value,
    'parent_id': category.parentId,
    'icon': category.icon,
    'color': category.color,
    'is_system': boolToSql(category.isSystem),
    'is_active': boolToSql(category.isActive),
    'created_at': formatTimestamp(category.createdAt),
    'updated_at': formatTimestamp(category.updatedAt),
    'deleted_at': category.deletedAt == null
        ? null
        : formatTimestamp(category.deletedAt!),
  };
}

Category _map(Map<String, Object?> row) {
  final deletedAt = row['deleted_at'] as String?;
  return Category(
    id: row['id']! as String,
    name: row['name']! as String,
    type: CategoryType.fromValue(row['type']! as String),
    userId: row['user_id'] as String?,
    parentId: row['parent_id'] as String?,
    icon: row['icon'] as String?,
    color: row['color'] as String?,
    isSystem: boolFromSql(row['is_system']),
    isActive: boolFromSql(row['is_active']),
    createdAt: parseTimestamp(row['created_at']! as String),
    updatedAt: parseTimestamp(row['updated_at']! as String),
    deletedAt: deletedAt == null ? null : parseTimestamp(deletedAt),
  );
}
