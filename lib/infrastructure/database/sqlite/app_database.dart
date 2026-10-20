import 'package:finan/app/app_config.dart';
import 'package:finan/infrastructure/database/sqlite/database_factory.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/apply_migrations.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_001_initial.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({Database? database}) : _database = database;

  Database? _database;
  Future<Database>? _opening;

  Future<Database> open() {
    final existing = _database;
    if (existing != null) return Future.value(existing);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    ensureDesktopDatabaseFactory();
    final directory = await getDatabasesPath();
    final filePath = path.join(directory, AppConfig.databaseFileName);
    final database = await openDatabase(
      filePath,
      version: AppConfig.databaseVersion,
      onConfigure: configureDatabase,
      onOpen: openDatabaseConnection,
      onCreate: (db, version) => applyMigrations(db, 0, version),
      onUpgrade: (db, oldVersion, newVersion) =>
          applyMigrations(db, oldVersion, newVersion),
    );
    _database = database;
    return database;
  }
}
