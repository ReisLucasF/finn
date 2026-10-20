import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/domain/repositories/backup_store.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/sqlite_guard.dart';

const backupTables = <String>[
  'users',
  'categories',
  'accounts',
  'credit_cards',
  'investments',
  'investment_yields',
  'financial_goals',
  'emergency_fund_settings',
  'emergency_fund_categories',
  'budgets',
  'recurrences',
  'transactions',
  'transaction_entries',
  'transfers',
  'provisions',
  'investment_transactions',
  'credit_card_statements',
  'ofx_imports',
  'ofx_import_transactions',
];

class SqliteBackupStore implements BackupStore {
  SqliteBackupStore(this._database);

  final AppDatabase _database;

  @override
  Future<Uint8List> exportZip() {
    return guardSqlite(() async {
      final database = await _database.open();
      final archive = Archive();
      archive.addFile(
        ArchiveFile.string(
          'metadata.json',
          jsonEncode({
            'app': 'finan',
            'format': 'financebackup',
            'version': 1,
          }),
        ),
      );
      for (final table in backupTables) {
        final rows = await database.query(table);
        archive.addFile(
          ArchiveFile.string('$table.json', jsonEncode(rows)),
        );
      }
      return ZipEncoder().encodeBytes(archive);
    });
  }

  @override
  Future<void> importZip(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = {for (final file in archive.files) file.name: file};
    final metadata = files['metadata.json'];
    if (metadata == null) {
      throw const ValidationException('Arquivo de backup inválido.');
    }
    final decoded = jsonDecode(utf8.decode(metadata.readBytes()!));
    if (decoded is! Map || decoded['format'] != 'financebackup') {
      throw const ValidationException('Arquivo de backup inválido.');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in backupTables) {
      final file = files['$table.json'];
      if (file == null) continue;
      final rows = jsonDecode(utf8.decode(file.readBytes()!));
      if (rows is! List) {
        throw const ValidationException('Arquivo de backup inválido.');
      }
      tables[table] = [
        for (final row in rows)
          if (row is Map) Map<String, Object?>.from(row),
      ];
    }
    return guardSqlite(() async {
      final database = await _database.open();
      await database.transaction((txn) async {
        for (final table in backupTables.reversed) {
          await txn.delete(table);
        }
        for (final table in backupTables) {
          for (final row in tables[table] ?? const <Map<String, Object?>>[]) {
            await txn.insert(table, row);
          }
        }
      });
    });
  }
}
