import 'package:sqflite/sqflite.dart';

class Migration006 {
  const Migration006._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE pluggy_connections (
    user_id TEXT PRIMARY KEY,
    client_id TEXT NOT NULL,
    client_secret TEXT NOT NULL,
    item_id TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
    await database.execute('''
CREATE TABLE pluggy_account_links (
    pluggy_account_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('BANK', 'CREDIT')),
    account_id TEXT,
    credit_card_id TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (account_id) REFERENCES accounts(id),
    FOREIGN KEY (credit_card_id) REFERENCES credit_cards(id)
)
''');
  }
}
