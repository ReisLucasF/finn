import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';

class OfxImportHeader {
  const OfxImportHeader({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.importedAt,
    required this.totalRecords,
    required this.importedRecords,
    required this.duplicateRecords,
    required this.ignoredRecords,
    this.fileName,
  });

  final String id;
  final String userId;
  final String accountId;
  final String? fileName;
  final DateTime importedAt;
  final int totalRecords;
  final int importedRecords;
  final int duplicateRecords;
  final int ignoredRecords;
}

class OfxImportLineRecord {
  const OfxImportLineRecord({
    required this.id,
    required this.importId,
    required this.amountCents,
    required this.duplicateScore,
    required this.duplicateStatus,
    required this.reconciliationStatus,
    required this.createdAt,
    this.fitId,
    this.transactionType,
    this.postedAt,
    this.name,
    this.memo,
    this.checkNumber,
    this.referenceNumber,
    this.rawHash,
    this.matchedTransactionId,
  });

  final String id;
  final String importId;
  final String? fitId;
  final String? transactionType;
  final String? postedAt;
  final int amountCents;
  final String? name;
  final String? memo;
  final String? checkNumber;
  final String? referenceNumber;
  final String? rawHash;
  final double duplicateScore;
  final String duplicateStatus;
  final String? matchedTransactionId;
  final String reconciliationStatus;
  final DateTime createdAt;
}

class OfxImportBundle {
  const OfxImportBundle({
    required this.header,
    required this.lines,
    required this.transactions,
    required this.entries,
    this.transfers = const [],
    this.retireTransactionIds = const [],
  });

  final OfxImportHeader header;
  final List<OfxImportLineRecord> lines;
  final List<Transaction> transactions;
  final List<TransactionEntry> entries;
  final List<OfxRecordedTransfer> transfers;
  final List<String> retireTransactionIds;
}

class OfxRecordedTransfer {
  const OfxRecordedTransfer({
    required this.id,
    required this.userId,
    required this.sourceAccountId,
    required this.destinationAccountId,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.description,
  });

  final String id;
  final String userId;
  final String sourceAccountId;
  final String destinationAccountId;
  final Money amount;
  final LocalDate date;
  final String? description;
  final DateTime createdAt;
}

abstract class OfxRepository {
  Future<void> save(OfxImportBundle bundle);

  Future<bool> wasReconciledFitId({
    required String userId,
    required String accountId,
    required String fitId,
  });
}
