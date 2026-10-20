import 'package:sqflite/sqflite.dart';

class Migration010 {
  const Migration010._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE emergency_fund_categories (
    user_id TEXT NOT NULL,
    category_id TEXT NOT NULL,
    PRIMARY KEY (user_id, category_id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (category_id) REFERENCES categories(id)
)
''');
  }
}
