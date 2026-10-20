import 'package:sqflite/sqflite.dart';

Future<void> configureDatabase(Database database) async {
  final version = await database.getVersion();
  // Migrações 5 e 12 recriam categories. PRAGMA foreign_keys não muda
  // dentro da transação que o sqflite abre no upgrade.
  if (version > 0 && version < 12) {
    await database.execute('PRAGMA foreign_keys = OFF');
    return;
  }
  await database.execute('PRAGMA foreign_keys = ON');
}

Future<void> openDatabaseConnection(Database database) async {
  await database.execute('PRAGMA foreign_keys = ON');
}

class Migration001 {
  const Migration001._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT,
    currency TEXT NOT NULL DEFAULT 'BRL',
    locale TEXT NOT NULL DEFAULT 'pt_BR',
    timezone TEXT NOT NULL DEFAULT 'America/Sao_Paulo',
    financial_month_start INTEGER NOT NULL DEFAULT 1 CHECK (financial_month_start BETWEEN 1 AND 31),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
)
''');
    await database.execute('''
CREATE TABLE accounts (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    institution_name TEXT,
    institution_code TEXT,
    account_type TEXT NOT NULL CHECK (
        account_type IN ('checking', 'savings', 'cash', 'digital_wallet', 'other')
    ),
    currency TEXT NOT NULL DEFAULT 'BRL',
    initial_balance INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
    await database.execute('''
CREATE TABLE categories (
    id TEXT PRIMARY KEY,
    user_id TEXT,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('income', 'expense', 'both')),
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
CREATE TABLE transactions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    type TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    description TEXT,
    transaction_date TEXT NOT NULL,
    competence_date TEXT,
    due_date TEXT,
    status TEXT NOT NULL DEFAULT 'confirmed' CHECK (
        status IN ('pending', 'confirmed', 'cancelled')
    ),
    account_id TEXT,
    category_id TEXT,
    source TEXT NOT NULL DEFAULT 'manual',
    external_id TEXT,
    notes TEXT,
    reconciled_at TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (account_id) REFERENCES accounts(id),
    FOREIGN KEY (category_id) REFERENCES categories(id)
)
''');
    await database.execute('''
CREATE TABLE transaction_entries (
    id TEXT PRIMARY KEY,
    transaction_id TEXT NOT NULL,
    account_id TEXT,
    amount INTEGER NOT NULL CHECK (amount != 0),
    created_at TEXT NOT NULL,
    FOREIGN KEY (transaction_id) REFERENCES transactions(id),
    FOREIGN KEY (account_id) REFERENCES accounts(id)
)
''');
    await database.execute(
      'CREATE INDEX idx_accounts_user_id ON accounts(user_id)',
    );
    await database.execute(
      'CREATE INDEX idx_categories_user_id ON categories(user_id)',
    );
    await database.execute(
      'CREATE INDEX idx_transactions_account ON transactions(account_id)',
    );
    await database.execute(
      'CREATE INDEX idx_transactions_date ON transactions(transaction_date)',
    );
    await database.execute(
      'CREATE INDEX idx_transactions_category ON transactions(category_id)',
    );
    await database.execute(
      'CREATE INDEX idx_transactions_status ON transactions(status)',
    );
    await database.execute(
      'CREATE INDEX idx_transactions_external_id ON transactions(external_id)',
    );
    await database.execute(
      'CREATE INDEX idx_transaction_entries_transaction ON transaction_entries(transaction_id)',
    );
    await database.execute(
      'CREATE INDEX idx_transaction_entries_account ON transaction_entries(account_id)',
    );
  }
}
