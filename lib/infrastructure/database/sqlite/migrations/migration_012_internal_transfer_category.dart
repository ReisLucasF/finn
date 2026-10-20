import 'package:sqflite/sqflite.dart';

class Migration012 {
  const Migration012._();

  static Future<void> up(DatabaseExecutor database) async {
    // Limpa sobra de upgrade interrompido (FK impediu o DROP anterior).
    await database.execute('DROP TABLE IF EXISTS categories_new');
    await database.execute('''
CREATE TABLE categories_new (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (
        type IN (
            'income',
            'expense',
            'both',
            'investment_application',
            'investment_redemption',
            'internal_transfer'
        )
    ),
    parent_id TEXT,
    icon TEXT,
    color TEXT,
    is_system INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (parent_id) REFERENCES categories(id)
)
''');
    await database.execute('''
INSERT INTO categories_new (
    id, user_id, name, type, parent_id, icon, color,
    is_system, is_active, created_at, updated_at, deleted_at
)
SELECT
    id, user_id, name, type, parent_id, icon, color,
    is_system, is_active, created_at, updated_at, deleted_at
FROM categories
''');
    await database.execute('DROP TABLE categories');
    await database.execute('ALTER TABLE categories_new RENAME TO categories');
    await database.execute(
      'CREATE INDEX idx_categories_user_id ON categories(user_id)',
    );
  }
}
