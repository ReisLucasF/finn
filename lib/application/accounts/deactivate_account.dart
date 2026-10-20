import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/repositories/account_repository.dart';

class DeactivateAccount {
  const DeactivateAccount({
    required AccountRepository accounts,
    required Clock clock,
  }) : _accounts = accounts,
       _clock = clock;

  final AccountRepository _accounts;
  final Clock _clock;

  Future<Account> call(String id) async {
    final current = await _accounts.findById(id);
    if (current == null || current.isDeleted) {
      throw const ValidationException('Conta não encontrada.');
    }
    final updated = current.copyWith(
      isActive: false,
      updatedAt: _clock.nowUtc(),
    );
    await _accounts.save(updated);
    return updated;
  }
}
