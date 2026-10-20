import 'package:finan/core/money/money.dart';

class TransactionEntry {
  const TransactionEntry({
    required this.id,
    required this.transactionId,
    required this.amount,
    required this.createdAt,
    this.accountId,
    this.creditCardId,
    this.investmentId,
  });

  final String id;
  final String transactionId;
  final String? accountId;
  final String? creditCardId;
  final String? investmentId;
  final Money amount;
  final DateTime createdAt;
}
