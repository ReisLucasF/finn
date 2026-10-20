import 'dart:io';
import 'dart:math';

import 'package:finan/app/app_config.dart';
import 'package:finan/app/dependency_injection.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/apply_migrations.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_001_initial.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var _factoryReady = false;

Future<AppGraph> openTestGraph({
  LocalDate? today,
  MarketDataGateway? marketGateway,
}) async {
  if (!_factoryReady) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _factoryReady = true;
  }
  final date = today ?? const LocalDate(2026, 10, 6);
  final filePath = path.join(
    Directory.systemTemp.path,
    'finan_test_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}.db',
  );
  final file = File(filePath);
  if (file.existsSync()) {
    file.deleteSync();
  }
  final database = await databaseFactory.openDatabase(
    filePath,
    options: OpenDatabaseOptions(
      version: AppConfig.databaseVersion,
      onConfigure: configureDatabase,
      onOpen: openDatabaseConnection,
      onCreate: (db, version) => applyMigrations(db, 0, version),
    ),
  );
  return AppGraph.assemble(
    database: AppDatabase(database: database),
    clock: Clock(
      nowUtc: () => DateTime.utc(2026, 10, 6, 15),
      today: () => date,
    ),
    marketGateway: marketGateway,
  );
}
