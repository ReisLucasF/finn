import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';

class ConfirmTransaction {
  const ConfirmTransaction({
    required TransactionRepository transactions,
    required Clock clock,
  }) : _transactions = transactions,
       _clock = clock;

  final TransactionRepository _transactions;
  final Clock _clock;

  Future<Transaction> call(String id) async {
    final current = await _transactions.findById(id);
    if (current == null || current.isDeleted) {
      throw const ValidationException('Lançamento não encontrado.');
    }
    if (current.status == TransactionStatus.cancelled) {
      throw const ValidationException(
        'Lançamento cancelado não pode ser confirmado.',
      );
    }
    if (current.status == TransactionStatus.confirmed) return current;
    final updated = current.copyWith(
      status: TransactionStatus.confirmed,
      updatedAt: _clock.nowUtc(),
    );
    await _transactions.update(updated);
    return updated;
  }
}
