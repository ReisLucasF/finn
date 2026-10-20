import 'package:sqflite/sqflite.dart';

class Migration014 {
  const Migration014._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE budgets (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    category_id TEXT NOT NULL,
    monthly_limit INTEGER NOT NULL CHECK (monthly_limit > 0),
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_state TEXT NOT NULL DEFAULT 'local',
    UNIQUE (user_id, category_id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (category_id) REFERENCES categories(id)
)
''');
  }
}
