import 'package:finan/application/planning/planning_actions.dart';
import 'package:finan/application/transactions/expense_investment_funding.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';

class DeleteTransaction {
  const DeleteTransaction({
    required TransactionRepository transactions,
    required ExpenseInvestmentFunding investmentFunding,
    required Clock clock,
    UnlinkInvestmentCash? unlinkInvestmentCash,
  }) : _transactions = transactions,
       _investmentFunding = investmentFunding,
       _clock = clock,
       _unlink = unlinkInvestmentCash;

  final TransactionRepository _transactions;
  final ExpenseInvestmentFunding _investmentFunding;
  final Clock _clock;
  final UnlinkInvestmentCash? _unlink;

  /// Exclusão lógica. O lançamento deixa de entrar no saldo e nos totais.
  Future<Transaction> call(String id) async {
    final current = await _transactions.findById(id);
    if (current == null) {
      throw const ValidationException('Lançamento não encontrado.');
    }
    if (current.isDeleted) return current;

    if (current.type == TransactionType.expense &&
        current.pairedTransactionId != null) {
      await _investmentFunding.removePair(current);
    } else if (current.type == TransactionType.investmentWithdrawal &&
        current.pairedTransactionId != null) {
      final expense = await _transactions.findById(
        current.pairedTransactionId!,
      );
      if (expense != null &&
          !expense.isDeleted &&
          expense.pairedTransactionId == current.id) {
        await _transactions.update(
          expense.copyWith(
            clearPairedTransactionId: true,
            updatedAt: _clock.nowUtc(),
          ),
        );
      }
    }

    // Vinculado a investimento: desfaz a movimentação antes de excluir,
    // senão a posição continua somando um lançamento que sumiu.
    final linked = await _transactions.findById(id) ?? current;
    if (linked.investmentId != null && !linked.isDeleted && _unlink != null) {
      await _unlink(userId: linked.userId, transactionId: linked.id);
    }

    final latest = await _transactions.findById(id) ?? current;
    if (latest.isDeleted) return latest;
    final now = _clock.nowUtc();
    final updated = latest.copyWith(deletedAt: now, updatedAt: now);
    await _transactions.update(updated);
    return updated;
  }
}
