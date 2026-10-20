import 'package:sqflite/sqflite.dart';

class Migration009 {
  const Migration009._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute(
      'ALTER TABLE pluggy_account_links ADD COLUMN item_id TEXT',
    );
  }
}
