import 'package:sqflite/sqflite.dart';

class Migration002 {
  const Migration002._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE ofx_imports (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    file_name TEXT,
    imported_at TEXT NOT NULL,
    total_records INTEGER NOT NULL DEFAULT 0,
    imported_records INTEGER NOT NULL DEFAULT 0,
    duplicate_records INTEGER NOT NULL DEFAULT 0,
    ignored_records INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (account_id) REFERENCES accounts(id)
)
''');
    await database.execute('''
CREATE TABLE ofx_import_transactions (
    id TEXT PRIMARY KEY,
    import_id TEXT NOT NULL,
    fit_id TEXT,
    transaction_type TEXT,
    posted_at TEXT,
    amount INTEGER NOT NULL,
    name TEXT,
    memo TEXT,
    check_number TEXT,
    reference_number TEXT,
    raw_hash TEXT,
    duplicate_score REAL,
    duplicate_status TEXT NOT NULL DEFAULT 'unknown' CHECK (
        duplicate_status IN ('unknown', 'none', 'possible', 'probable', 'very_likely')
    ),
    matched_transaction_id TEXT,
    reconciliation_status TEXT NOT NULL DEFAULT 'pending' CHECK (
        reconciliation_status IN ('pending', 'reconciled', 'ignored')
    ),
    created_at TEXT NOT NULL,
    FOREIGN KEY (import_id) REFERENCES ofx_imports(id)
)
''');
    await database.execute(
      'CREATE INDEX idx_ofx_import_transactions_fit_id ON ofx_import_transactions(fit_id)',
    );
    await database.execute(
      'CREATE INDEX idx_ofx_import_transactions_import ON ofx_import_transactions(import_id)',
    );
  }
}
