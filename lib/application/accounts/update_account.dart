import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/repositories/account_repository.dart';

class UpdateAccount {
  const UpdateAccount({
    required AccountRepository accounts,
    required Clock clock,
  }) : _accounts = accounts,
       _clock = clock;

  final AccountRepository _accounts;
  final Clock _clock;

  Future<Account> call({
    required String id,
    required String name,
    required AccountType type,
    required Money initialBalance,
    required bool isActive,
    String? institutionName,
    String? institutionCode,
  }) async {
    final current = await _accounts.findById(id);
    if (current == null || current.isDeleted) {
      throw const ValidationException('Conta não encontrada.');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ValidationException('Informe o nome da conta.');
    }

    final updated = current.copyWith(
      name: trimmedName,
      type: type,
      initialBalance: initialBalance,
      isActive: isActive,
      institutionName: _blankToNull(institutionName),
      clearInstitutionName: _blankToNull(institutionName) == null,
      institutionCode: _blankToNull(institutionCode),
      clearInstitutionCode: _blankToNull(institutionCode) == null,
      updatedAt: _clock.nowUtc(),
    );
    await _accounts.save(updated);
    return updated;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
