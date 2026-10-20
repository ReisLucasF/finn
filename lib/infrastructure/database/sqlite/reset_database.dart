import 'package:finan/infrastructure/database/sqlite/app_database.dart';

Future<void> wipeDatabase(AppDatabase database) async {
  final db = await database.open();
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
  );
  await db.execute('PRAGMA foreign_keys = OFF');
  try {
    await db.transaction((txn) async {
      for (final row in tables) {
        final name = row['name'] as String?;
        if (name == null || name.isEmpty) continue;
        await txn.delete(name);
      }
    });
  } finally {
    await db.execute('PRAGMA foreign_keys = ON');
  }
}
