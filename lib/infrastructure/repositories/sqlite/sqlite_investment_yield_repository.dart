import 'package:finan/core/date/local_date.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sql_codec.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';
import 'package:sqflite/sqflite.dart';

class SqliteInvestmentYieldRepository implements InvestmentYieldRepository {
  SqliteInvestmentYieldRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> save(InvestmentYield config) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        final row = {
          'indexer': config.indexer.value,
          'rate': config.rate,
          'tax_regime': config.taxRegime.value,
          'updated_at': formatTimestamp(config.updatedAt),
        };
        final updated = await txn.rawUpdate(
          '''
UPDATE investment_yields
SET indexer = ?, rate = ?, tax_regime = ?, updated_at = ?,
    sync_version = sync_version + 1
WHERE investment_id = ?
''',
          [...row.values, config.investmentId],
        );
        if (updated == 0) {
          await txn.insert('investment_yields', {
            'investment_id': config.investmentId,
            ...row,
          });
        }
      });
    });
  }

  @override
  Future<void> delete(String investmentId) {
    return guardSqlite(() async {
      final database = await _database.open();
      await database.delete(
        'investment_yields',
        where: 'investment_id = ?',
        whereArgs: [investmentId],
      );
    });
  }

  @override
  Future<List<InvestmentYield>> listByUser(String userId) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.rawQuery(
        '''
SELECT y.* FROM investment_yields y
JOIN investments i ON i.id = y.investment_id
WHERE i.user_id = ? AND i.deleted_at IS NULL
''',
        [userId],
      );
      return [
        for (final row in rows)
          InvestmentYield(
            investmentId: row['investment_id']! as String,
            indexer: YieldIndexer.fromValue(row['indexer']! as String),
            rate: (row['rate']! as num).toDouble(),
            taxRegime: TaxRegime.fromValue(row['tax_regime']! as String),
            updatedAt: parseTimestamp(row['updated_at']! as String),
          ),
      ];
    });
  }
}

class SqliteMarketDataRepository implements MarketDataRepository {
  SqliteMarketDataRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> saveValues(int series, List<(LocalDate, double)> values) {
    if (values.isEmpty) return Future.value();
    return guardSqlite(() async {
      final database = await _database.open();
      final batch = database.batch();
      for (final (date, value) in values) {
        batch.insert('indicator_values', {
          'series': series,
          'date': date.toIso(),
          'value': value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<Map<LocalDate, double>> values(int series, {LocalDate? from}) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'indicator_values',
        columns: const ['date', 'value'],
        where: from == null ? 'series = ?' : 'series = ? AND date >= ?',
        whereArgs: from == null ? [series] : [series, from.toIso()],
      );
      return {
        for (final row in rows)
          LocalDate.parse(row['date']! as String): (row['value']! as num)
              .toDouble(),
      };
    });
  }

  @override
  Future<(LocalDate, double)?> latest(int series) => _edge(series, 'DESC');

  @override
  Future<LocalDate?> earliest(int series) async =>
      (await _edge(series, 'ASC'))?.$1;

  Future<(LocalDate, double)?> _edge(int series, String order) {
    return guardSqlite(() async {
      final database = await _database.open();
      final rows = await database.query(
        'indicator_values',
        columns: const ['date', 'value'],
        where: 'series = ?',
        whereArgs: [series],
        orderBy: 'date $order',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return (
        LocalDate.parse(rows.first['date']! as String),
        (rows.first['value']! as num).toDouble(),
      );
    });
  }
}
