import 'package:sqflite/sqflite.dart';

/// Conta padrão do investimento (de onde saem os aportes e para onde vão os
/// resgates).
class Migration016 {
  const Migration016._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('ALTER TABLE investments ADD COLUMN account_id TEXT');
  }
}
