import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/transaction_type.dart';

enum DuplicateBand { none, possible, probable, veryLikely }

class PossibleTransfer {
  const PossibleTransfer({
    required this.accountId,
    required this.date,
    required this.confidence,
    this.transactionId,
  });

  final String accountId;
  final String? transactionId;
  final LocalDate date;
  final double confidence;
}

class CategorySuggestion {
  const CategorySuggestion({
    required this.categoryId,
    required this.confidence,
    required this.reason,
  });

  final String categoryId;
  final double confidence;
  final String reason;
}

class OfxReviewLine {
  const OfxReviewLine({
    required this.id,
    required this.postedAtRaw,
    required this.postedDate,
    required this.signedAmount,
    required this.absoluteAmount,
    required this.type,
    required this.originalDescription,
    required this.normalizedDescription,
    required this.rawHash,
    required this.duplicateScore,
    required this.duplicateBand,
    required this.importByDefault,
    this.fitId,
    this.trnType,
    this.name,
    this.memo,
    this.checkNumber,
    this.referenceNumber,
    this.matchedTransactionId,
    this.possibleTransfer,
    this.suggestion,
    this.coveredByExistingTransfer = false,
  });

  final String id;
  final String? fitId;
  final String? trnType;
  final String postedAtRaw;
  final LocalDate postedDate;
  final Money signedAmount;
  final Money absoluteAmount;
  final TransactionType type;
  final String? name;
  final String? memo;
  final String? checkNumber;
  final String? referenceNumber;
  final String originalDescription;
  final String normalizedDescription;
  final String rawHash;
  final double duplicateScore;
  final DuplicateBand duplicateBand;
  final String? matchedTransactionId;
  final bool importByDefault;
  final PossibleTransfer? possibleTransfer;
  final CategorySuggestion? suggestion;
  final bool coveredByExistingTransfer;
}

class OfxAnalysis {
  const OfxAnalysis({
    required this.accountId,
    required this.lines,
    this.fileName,
  });

  final String accountId;
  final String? fileName;
  final List<OfxReviewLine> lines;
}

class OfxImportDecision {
  const OfxImportDecision({
    required this.lineId,
    required this.import,
    this.categoryId,
    this.transferAccountId,
    this.linkTransactionId,
  });

  final String lineId;
  final bool import;
  final String? categoryId;
  final String? transferAccountId;
  final String? linkTransactionId;
}
