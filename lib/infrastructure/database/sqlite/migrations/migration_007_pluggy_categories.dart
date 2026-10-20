import 'package:sqflite/sqflite.dart';

class Migration007 {
  const Migration007._();

  static Future<void> up(DatabaseExecutor database) async {
    await database.execute('''
CREATE TABLE pluggy_category_links (
    user_id TEXT NOT NULL,
    pluggy_category TEXT NOT NULL,
    category_id TEXT,
    PRIMARY KEY (user_id, pluggy_category),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (category_id) REFERENCES categories(id)
)
''');
  }
}
