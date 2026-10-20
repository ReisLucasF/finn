import 'package:sqflite/sqflite.dart';

class Migration011 {
  const Migration011._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute(
      'ALTER TABLE transactions ADD COLUMN paired_transaction_id TEXT',
    );
    await database.execute(
      'CREATE INDEX idx_transactions_paired ON transactions(paired_transaction_id)',
    );
  }
}
