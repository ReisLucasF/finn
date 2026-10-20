import 'package:sqflite/sqflite.dart';

class Migration008 {
  const Migration008._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE pluggy_items (
    item_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    connector_name TEXT NOT NULL,
    status TEXT,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
  }
}
