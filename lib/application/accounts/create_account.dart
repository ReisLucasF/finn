import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/repositories/account_repository.dart';

class CreateAccount {
  const CreateAccount({
    required AccountRepository accounts,
    required Clock clock,
    required IdGenerator ids,
  }) : _accounts = accounts,
       _clock = clock,
       _ids = ids;

  final AccountRepository _accounts;
  final Clock _clock;
  final IdGenerator _ids;

  Future<Account> call({
    required String userId,
    required String name,
    required AccountType type,
    Money initialBalance = const Money(0),
    String currency = 'BRL',
    String? institutionName,
    String? institutionCode,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw const ValidationException('Informe o nome da conta.');
    }
    final normalizedCurrency = currency.trim().toUpperCase();
    if (normalizedCurrency.isEmpty) {
      throw const ValidationException('Informe a moeda.');
    }
    if (userId.isEmpty) {
      throw const ValidationException('Usuário inválido.');
    }

    final now = _clock.nowUtc();
    final account = Account(
      id: _ids.next(),
      userId: userId,
      name: trimmedName,
      type: type,
      currency: normalizedCurrency,
      initialBalance: initialBalance,
      isActive: true,
      institutionName: _blankToNull(institutionName),
      institutionCode: _blankToNull(institutionCode),
      createdAt: now,
      updatedAt: now,
    );
    await _accounts.save(account);
    return account;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
