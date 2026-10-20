import 'package:sqflite/sqflite.dart';

class Migration003 {
  const Migration003._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE credit_cards (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    issuer TEXT,
    brand TEXT,
    last_four_digits TEXT,
    credit_limit INTEGER NOT NULL CHECK (credit_limit >= 0),
    initial_used_limit INTEGER NOT NULL DEFAULT 0 CHECK (initial_used_limit >= 0),
    closing_day INTEGER CHECK (closing_day BETWEEN 1 AND 31),
    due_day INTEGER CHECK (due_day BETWEEN 1 AND 31),
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
    await database.execute('''
CREATE TABLE credit_card_statements (
    id TEXT PRIMARY KEY,
    credit_card_id TEXT NOT NULL,
    reference_month TEXT NOT NULL,
    closing_date TEXT NOT NULL,
    due_date TEXT NOT NULL,
    total_amount INTEGER NOT NULL CHECK (total_amount > 0),
    status TEXT NOT NULL CHECK (status IN ('open', 'closed', 'paid', 'overdue')),
    FOREIGN KEY (credit_card_id) REFERENCES credit_cards(id)
)
''');
    await database.execute('''
CREATE TABLE transfers (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    source_account_id TEXT NOT NULL,
    destination_account_id TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    transaction_date TEXT NOT NULL,
    description TEXT,
    status TEXT NOT NULL DEFAULT 'confirmed',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (source_account_id) REFERENCES accounts(id),
    FOREIGN KEY (destination_account_id) REFERENCES accounts(id),
    CHECK (source_account_id != destination_account_id)
)
''');
    await database.execute('''
CREATE TABLE recurrences (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    category_id TEXT,
    account_id TEXT,
    credit_card_id TEXT,
    frequency TEXT NOT NULL,
    interval_value INTEGER NOT NULL DEFAULT 1 CHECK (interval_value > 0),
    start_date TEXT NOT NULL,
    end_date TEXT,
    next_occurrence TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
    await database.execute('''
CREATE TABLE provisions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    recurrence_id TEXT,
    description TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    type TEXT NOT NULL,
    due_date TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (
        status IN ('pending', 'due', 'overdue', 'settled', 'cancelled')
    ),
    transaction_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (recurrence_id) REFERENCES recurrences(id),
    FOREIGN KEY (transaction_id) REFERENCES transactions(id)
)
''');
    await database.execute('''
CREATE TABLE investments (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    institution TEXT,
    type TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'BRL',
    current_value INTEGER NOT NULL DEFAULT 0,
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
    await database.execute('''
CREATE TABLE investment_transactions (
    id TEXT PRIMARY KEY,
    investment_id TEXT NOT NULL,
    type TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    transaction_date TEXT NOT NULL,
    quantity INTEGER,
    unit_price INTEGER,
    description TEXT,
    linked_transaction_id TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (investment_id) REFERENCES investments(id),
    FOREIGN KEY (linked_transaction_id) REFERENCES transactions(id)
)
''');
    await database.execute('''
CREATE TABLE financial_goals (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,
    target_amount INTEGER NOT NULL CHECK (target_amount > 0),
    current_amount INTEGER NOT NULL DEFAULT 0,
    target_date TEXT,
    expected_monthly_return_rate REAL,
    expected_monthly_savings INTEGER,
    goal_type TEXT NOT NULL DEFAULT 'net_worth',
    is_active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
    await database.execute('''
CREATE TABLE emergency_fund_settings (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    target_months INTEGER NOT NULL DEFAULT 6 CHECK (target_months > 0),
    manual_target_amount INTEGER,
    use_automatic_calculation INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id)
)
''');
    await database.execute(
      'ALTER TABLE transactions ADD COLUMN credit_card_id TEXT',
    );
    await database.execute(
      'ALTER TABLE transactions ADD COLUMN transfer_id TEXT',
    );
    await database.execute(
      'ALTER TABLE transactions ADD COLUMN investment_id TEXT',
    );
    await database.execute(
      'ALTER TABLE transactions ADD COLUMN recurrence_id TEXT',
    );
    await database.execute(
      'ALTER TABLE transactions ADD COLUMN provision_id TEXT',
    );
    await database.execute(
      'ALTER TABLE transaction_entries ADD COLUMN credit_card_id TEXT',
    );
    await database.execute(
      'ALTER TABLE transaction_entries ADD COLUMN investment_id TEXT',
    );
    await database.execute(
      'CREATE INDEX idx_credit_cards_user ON credit_cards(user_id)',
    );
    await database.execute(
      'CREATE INDEX idx_transfers_user ON transfers(user_id)',
    );
    await database.execute(
      'CREATE INDEX idx_provisions_user ON provisions(user_id, due_date)',
    );
    await database.execute(
      'CREATE UNIQUE INDEX idx_provisions_recurrence_due ON provisions(recurrence_id, due_date) WHERE recurrence_id IS NOT NULL',
    );
    await database.execute(
      'CREATE INDEX idx_investments_user ON investments(user_id)',
    );
    await database.execute(
      'CREATE INDEX idx_goals_user ON financial_goals(user_id)',
    );
  }
}
