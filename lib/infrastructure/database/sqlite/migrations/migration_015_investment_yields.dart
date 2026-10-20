import 'package:sqflite/sqflite.dart';

class Migration015 {
  const Migration015._();

  static Future<void> up(DatabaseExecutor database) async {
    // Indexador e tributação por investimento (renda fixa).
    await database.execute('''
CREATE TABLE investment_yields (
    investment_id TEXT PRIMARY KEY,
    indexer TEXT NOT NULL,
    rate REAL NOT NULL CHECK (rate >= 0),
    tax_regime TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    sync_version INTEGER NOT NULL DEFAULT 1,
    sync_state TEXT NOT NULL DEFAULT 'local',
    FOREIGN KEY (investment_id) REFERENCES investments(id)
)
''');
    // Cache das séries do Banco Central (SGS): 12, 4389, 4391.
    await database.execute('''
CREATE TABLE indicator_values (
    series INTEGER NOT NULL,
    date TEXT NOT NULL,
    value REAL NOT NULL,
    PRIMARY KEY (series, date)
)
''');
  }
}
