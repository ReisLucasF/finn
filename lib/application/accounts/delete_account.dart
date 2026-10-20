import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/repositories/account_repository.dart';

class DeleteAccount {
  const DeleteAccount({
    required AccountRepository accounts,
    required Clock clock,
  }) : _accounts = accounts,
       _clock = clock;

  final AccountRepository _accounts;
  final Clock _clock;

  /// Exclusão lógica. O histórico de lançamentos permanece.
  Future<Account> call(String id) async {
    final current = await _accounts.findById(id);
    if (current == null) {
      throw const ValidationException('Conta não encontrada.');
    }
    if (current.isDeleted) return current;
    final now = _clock.nowUtc();
    final updated = current.copyWith(
      isActive: false,
      deletedAt: now,
      updatedAt: now,
    );
    await _accounts.save(updated);
    return updated;
  }
}
