import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/repositories/finance_repository.dart';

class TransferPairs {
  const TransferPairs({
    required FinanceRepository finance,
    required IdGenerator ids,
    required Clock clock,
  }) : _finance = finance,
       _ids = ids,
       _clock = clock;

  final FinanceRepository _finance;
  final IdGenerator _ids;
  final Clock _clock;

  Future<TransferPairSuggestion?> find(String userId) {
    return _finance.findTransferPair(userId);
  }

  Future<void> convert(String userId, TransferPairSuggestion pair) {
    final now = _clock.nowUtc();
    return _finance.convertPairToTransfer(
      userId: userId,
      expenseTransactionId: pair.expenseTransactionId,
      incomeTransactionId: pair.incomeTransactionId,
      sourceAccountId: pair.expenseAccountId,
      destinationAccountId: pair.incomeAccountId,
      amount: pair.amount,
      date: pair.date,
      description: pair.expenseDescription,
      now: now,
      transferId: _ids.next(),
      transactionId: _ids.next(),
      sourceEntryId: _ids.next(),
      destinationEntryId: _ids.next(),
    );
  }

  Future<void> dismiss(String userId, TransferPairSuggestion pair) {
    return _finance.dismissTransferPair(
      id: _ids.next(),
      userId: userId,
      firstTransactionId: pair.expenseTransactionId,
      secondTransactionId: pair.incomeTransactionId,
      createdAt: _clock.nowUtc(),
    );
  }
}
