import 'package:finan/app/app_config.dart';
import 'package:finan/application/categories/seed_categories.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/user.dart';
import 'package:finan/domain/repositories/user_repository.dart';

class BootstrapApp {
  const BootstrapApp({
    required UserRepository users,
    required SeedCategories seedCategories,
    required Clock clock,
    required IdGenerator ids,
  }) : _users = users,
       _seedCategories = seedCategories,
       _clock = clock,
       _ids = ids;

  final UserRepository _users;
  final SeedCategories _seedCategories;
  final Clock _clock;
  final IdGenerator _ids;

  Future<AppUser> call() async {
    final existing = await _users.findCurrent();
    if (existing != null) {
      await _seedCategories();
      return existing;
    }
    final now = _clock.nowUtc();
    final created = AppUser(
      id: _ids.next(),
      name: '',
      currency: AppConfig.defaultCurrency,
      locale: AppConfig.defaultLocale,
      timezone: AppConfig.defaultTimezone,
      financialMonthStart: AppConfig.defaultFinancialMonthStart,
      createdAt: now,
      updatedAt: now,
    );
    await _users.save(created);
    await _seedCategories();
    return created;
  }
}
