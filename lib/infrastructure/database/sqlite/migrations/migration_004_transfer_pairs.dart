import 'package:sqflite/sqflite.dart';

class Migration004 {
  const Migration004._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE dismissed_transfer_pairs (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    transaction_a_id TEXT NOT NULL,
    transaction_b_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id),
    UNIQUE (transaction_a_id, transaction_b_id)
)
''');
  }
}
