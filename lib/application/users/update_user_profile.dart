import 'package:finan/app/app_config.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/user.dart';
import 'package:finan/domain/repositories/user_repository.dart';

class UpdateUserProfile {
  const UpdateUserProfile({
    required UserRepository users,
    required Clock clock,
    required IdGenerator ids,
  }) : _users = users,
       _clock = clock,
       _ids = ids;

  final UserRepository _users;
  final Clock _clock;
  final IdGenerator _ids;

  Future<AppUser> call({
    required String name,
    String currency = AppConfig.defaultCurrency,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe seu nome.');
    }
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) {
      throw const ValidationException('Informe a moeda.');
    }

    final now = _clock.nowUtc();
    final current = await _users.findCurrent();
    final user =
        (current ??
                AppUser(
                  id: _ids.next(),
                  name: trimmed,
                  currency: normalizedCurrency,
                  locale: AppConfig.defaultLocale,
                  timezone: AppConfig.defaultTimezone,
                  financialMonthStart: AppConfig.defaultFinancialMonthStart,
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              name: trimmed,
              currency: normalizedCurrency,
              updatedAt: now,
            );
    await _users.save(user);
    return user;
  }
}
