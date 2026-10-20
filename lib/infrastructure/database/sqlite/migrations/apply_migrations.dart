import 'package:finan/infrastructure/database/sqlite/migrations/migration_001_initial.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_002_add_ofx.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_003_planning.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_004_transfer_pairs.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_005_investment_categories.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_006_pluggy.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_007_pluggy_categories.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_008_pluggy_items.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_009_pluggy_link_item.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_010_emergency_categories.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_011_paired_transactions.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_012_internal_transfer_category.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_013_sync_columns.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_014_budgets.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_015_investment_yields.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_016_investment_account.dart';
import 'package:sqflite/sqflite.dart';

Future<void> applyMigrations(
  DatabaseExecutor database,
  int from,
  int to,
) async {
  if (from < 1 && to >= 1) await Migration001.up(database);
  if (from < 2 && to >= 2) await Migration002.up(database);
  if (from < 3 && to >= 3) await Migration003.up(database);
  if (from < 4 && to >= 4) await Migration004.up(database);
  if (from < 5 && to >= 5) await Migration005.up(database);
  if (from < 6 && to >= 6) await Migration006.up(database);
  if (from < 7 && to >= 7) await Migration007.up(database);
  if (from < 8 && to >= 8) await Migration008.up(database);
  if (from < 9 && to >= 9) await Migration009.up(database);
  if (from < 10 && to >= 10) await Migration010.up(database);
  if (from < 11 && to >= 11) await Migration011.up(database);
  if (from < 12 && to >= 12) await Migration012.up(database);
  if (from < 13 && to >= 13) await Migration013.up(database);
  if (from < 14 && to >= 14) await Migration014.up(database);
  if (from < 15 && to >= 15) await Migration015.up(database);
  if (from < 16 && to >= 16) await Migration016.up(database);
}
