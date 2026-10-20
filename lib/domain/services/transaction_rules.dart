import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/transaction_type.dart';

class TransactionRules {
  const TransactionRules();

  void validateAmount(Money amount) {
    if (amount.cents <= 0) {
      throw const ValidationException('Informe um valor maior que zero.');
    }
  }

  void validateAccountForCreate(Account account, String userId) {
    if (account.userId != userId || account.isDeleted) {
      throw const ValidationException('Conta inválida.');
    }
    if (!account.isActive) {
      throw const ValidationException('A conta está desativada.');
    }
  }

  void validateAccountForUpdate(
    Account account,
    String userId, {
    required String? previousAccountId,
  }) {
    if (account.userId != userId || account.isDeleted) {
      throw const ValidationException('Conta inválida.');
    }
    final keepingSameAccount = account.id == previousAccountId;
    if (!account.isActive && !keepingSameAccount) {
      throw const ValidationException('A conta está desativada.');
    }
  }

  void validateCategory(
    Category category,
    TransactionType type, {
    required bool allowInactive,
  }) {
    if (category.deletedAt != null) {
      throw const ValidationException('Categoria inválida.');
    }
    if (!category.isActive && !allowInactive) {
      throw const ValidationException('A categoria está desativada.');
    }
    if (!category.type.accepts(type)) {
      throw const ValidationException(
        'A categoria não corresponde ao tipo do lançamento.',
      );
    }
  }
}
