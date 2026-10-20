import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/transaction_type.dart';

class TransactionPosting {
  const TransactionPosting();

  /// Receita entra positiva na conta. Despesa entra negativa.
  /// O valor do lançamento permanece absoluto.
  List<TransactionEntry> forAccount({
    required String entryId,
    required String transactionId,
    required String accountId,
    required TransactionType type,
    required Money amount,
    required DateTime createdAt,
  }) {
    if (amount.cents <= 0) {
      throw const ValidationException('Informe um valor maior que zero.');
    }
    final signed = switch (type) {
      TransactionType.income => amount,
      TransactionType.expense => Money(-amount.cents),
      TransactionType.transfer ||
      TransactionType.investmentContribution ||
      TransactionType.investmentWithdrawal ||
      TransactionType.investmentIncome ||
      TransactionType.investmentLoss ||
      TransactionType.creditCardPayment => throw const ValidationException(
        'Esse tipo usa um lançamento próprio.',
      ),
    };
    return [
      TransactionEntry(
        id: entryId,
        transactionId: transactionId,
        accountId: accountId,
        amount: signed,
        createdAt: createdAt,
      ),
    ];
  }
}
