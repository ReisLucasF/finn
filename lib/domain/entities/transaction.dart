import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';

class Transaction {
  const Transaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.transactionDate,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.competenceDate,
    this.dueDate,
    this.accountId,
    this.categoryId,
    this.creditCardId,
    this.transferId,
    this.investmentId,
    this.recurrenceId,
    this.provisionId,
    this.pairedTransactionId,
    this.externalId,
    this.notes,
    this.reconciledAt,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final TransactionType type;
  final Money amount;
  final String? description;
  final LocalDate transactionDate;
  final LocalDate? competenceDate;
  final LocalDate? dueDate;
  final TransactionStatus status;
  final String? accountId;
  final String? categoryId;
  final String? creditCardId;
  final String? transferId;
  final String? investmentId;
  final String? recurrenceId;
  final String? provisionId;
  final String? pairedTransactionId;
  final TransactionSource source;
  final String? externalId;
  final String? notes;
  final DateTime? reconciledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  bool get countsTowardBalance => !isDeleted && status.affectsBalance;

  Transaction copyWith({
    TransactionType? type,
    Money? amount,
    String? description,
    bool clearDescription = false,
    LocalDate? transactionDate,
    LocalDate? competenceDate,
    TransactionStatus? status,
    String? accountId,
    String? categoryId,
    String? notes,
    bool clearNotes = false,
    bool clearCategory = false,
    String? investmentId,
    bool clearInvestmentId = false,
    String? pairedTransactionId,
    bool clearPairedTransactionId = false,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Transaction(
      id: id,
      userId: userId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      description: clearDescription ? null : description ?? this.description,
      transactionDate: transactionDate ?? this.transactionDate,
      competenceDate: competenceDate ?? this.competenceDate,
      dueDate: dueDate,
      status: status ?? this.status,
      accountId: accountId ?? this.accountId,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      creditCardId: creditCardId,
      transferId: transferId,
      investmentId:
          clearInvestmentId ? null : investmentId ?? this.investmentId,
      recurrenceId: recurrenceId,
      provisionId: provisionId,
      pairedTransactionId: clearPairedTransactionId
          ? null
          : pairedTransactionId ?? this.pairedTransactionId,
      source: source,
      externalId: externalId,
      notes: clearNotes ? null : notes ?? this.notes,
      reconciledAt: reconciledAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }
}
