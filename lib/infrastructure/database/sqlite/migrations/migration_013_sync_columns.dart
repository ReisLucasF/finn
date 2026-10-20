import 'package:sqflite/sqflite.dart';

class Migration013 {
  const Migration013._();

  static const tables = <String>[
    'users',
    'accounts',
    'categories',
    'transactions',
    'transaction_entries',
    'credit_cards',
    'transfers',
    'recurrences',
    'provisions',
    'investments',
    'investment_transactions',
    'financial_goals',
    'emergency_fund_settings',
  ];

  static Future<void> up(DatabaseExecutor database) async {
    for (final table in tables) {
      await database.execute(
        "ALTER TABLE $table ADD COLUMN sync_version INTEGER NOT NULL DEFAULT 1",
      );
      await database.execute(
        "ALTER TABLE $table ADD COLUMN sync_state TEXT NOT NULL DEFAULT 'local'",
      );
    }
  }
}
