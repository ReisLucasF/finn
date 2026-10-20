import 'dart:typed_data';

import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/entities/parsed_ofx_transaction.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/repositories/ofx_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/category_suggestion_service.dart';
import 'package:finan/domain/services/duplicate_detection_service.dart';
import 'package:finan/domain/services/ofx_fingerprint.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';
import 'package:finan/domain/services/ofx_parser.dart';
import 'package:finan/domain/services/transfer_detection_service.dart';

class AnalyzeOfx {
  const AnalyzeOfx({
    required OfxParser parser,
    required AccountRepository accounts,
    required CategoryRepository categories,
    required TransactionRepository transactions,
    required OfxRepository ofx,
    required FinanceRepository finance,
    required DuplicateDetectionService duplicates,
    required TransferDetectionService transfers,
    required CategorySuggestionService suggestions,
    required IdGenerator ids,
  }) : _parser = parser,
       _accounts = accounts,
       _categories = categories,
       _transactions = transactions,
       _ofx = ofx,
       _finance = finance,
       _duplicates = duplicates,
       _transfers = transfers,
       _suggestions = suggestions,
       _ids = ids;

  final OfxParser _parser;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final OfxRepository _ofx;
  final FinanceRepository _finance;
  final DuplicateDetectionService _duplicates;
  final TransferDetectionService _transfers;
  final CategorySuggestionService _suggestions;
  final IdGenerator _ids;

  Future<OfxAnalysis> call({
    required String userId,
    required String accountId,
    required Uint8List bytes,
    String? fileName,
  }) async {
    final account = await _accounts.findById(accountId);
    if (account == null || account.isDeleted || account.userId != userId) {
      throw const ValidationException('Conta inválida.');
    }
    if (!account.isActive) {
      throw const ValidationException('A conta está desativada.');
    }
    final parsed = _parser.parseBytes(bytes);
    final categories = await _categories.listByUser(
      userId,
      includeInactive: false,
    );
    final history = await _transactions.recentClassifications(userId);
    final seenFitIds = <String>{};
    final consumedTransfers = <String>{};
    final lines = <OfxReviewLine>[];
    for (final item in parsed) {
      lines.add(
        await _line(
          userId: userId,
          accountId: accountId,
          item: item,
          categories: categories,
          history: history,
          seenFitIds: seenFitIds,
          consumedTransfers: consumedTransfers,
        ),
      );
    }
    return OfxAnalysis(accountId: accountId, fileName: fileName, lines: lines);
  }

  Future<OfxReviewLine> _line({
    required String userId,
    required String accountId,
    required ParsedOfxTransaction item,
    required List<Category> categories,
    required List<ClassifiedDescription> history,
    required Set<String> seenFitIds,
    required Set<String> consumedTransfers,
  }) async {
    final description = _description(item);
    final normalized = normalizeDescription(description);
    final rows = await _transactions.findReconciliationCandidates(
      userId: userId,
      accountId: accountId,
      absoluteAmount: item.absoluteAmount,
      date: item.postedDate,
      externalId: item.fitId,
    );
    final candidates = [
      for (final row in rows)
        DuplicateCandidate(
          transactionId: row.id,
          accountId: row.accountId ?? '',
          amount: row.amount,
          date: row.transactionDate,
          description: row.description,
          externalId: row.externalId,
        ),
    ];
    var match = _duplicates.evaluate(
      accountId: accountId,
      absoluteAmount: item.absoluteAmount,
      date: item.postedDate,
      normalizedDescription: normalized,
      fitId: item.fitId,
      candidates: candidates,
    );
    // Crédito do extrato que é o resgate de uma despesa "paga com
    // investimento" já lançada: a retirada pareada já creditou a conta.
    if (item.signedAmount.cents > 0) {
      for (final row in rows) {
        if (row.type == TransactionType.investmentWithdrawal &&
            row.pairedTransactionId != null &&
            row.accountId == accountId &&
            row.amount == item.absoluteAmount) {
          match = DuplicateMatch(
            score: match.score < 0.95 ? 0.95 : match.score,
            band: DuplicateBand.veryLikely,
            transactionId: row.id,
          );
          break;
        }
      }
    }
    final fitId = item.fitId?.trim();
    if (fitId != null && fitId.isNotEmpty && !seenFitIds.add(fitId)) {
      match = DuplicateMatch(
        score: match.score < 0.95 ? 0.95 : match.score,
        band: DuplicateBand.veryLikely,
        transactionId: match.transactionId,
      );
    }
    if (fitId != null &&
        fitId.isNotEmpty &&
        await _ofx.wasReconciledFitId(
          userId: userId,
          accountId: accountId,
          fitId: fitId,
        )) {
      match = DuplicateMatch(
        score: match.score < 0.95 ? 0.95 : match.score,
        band: DuplicateBand.veryLikely,
        transactionId: match.transactionId,
      );
    }
    RecordedTransferMatch? covered;
    final recorded = await _finance.findCoveringTransfers(
      userId: userId,
      accountId: accountId,
      amount: item.absoluteAmount,
      date: item.postedDate,
    );
    for (final candidate in recorded) {
      if (consumedTransfers.add(candidate.transactionId)) {
        covered = candidate;
        break;
      }
    }
    if (covered != null) {
      match = DuplicateMatch(
        score: match.score < 0.95 ? 0.95 : match.score,
        band: DuplicateBand.veryLikely,
        transactionId: covered.transactionId,
      );
    }
    final suggestion = _suggestions.suggest(
      normalizedDescription: normalized,
      categories: categories,
      history: history,
    );
    return OfxReviewLine(
      id: _ids.next(),
      fitId: item.fitId,
      trnType: item.trnType,
      postedAtRaw: item.postedAtRaw,
      postedDate: item.postedDate,
      signedAmount: item.signedAmount,
      absoluteAmount: item.absoluteAmount,
      type: item.signedAmount.cents < 0
          ? TransactionType.expense
          : TransactionType.income,
      name: item.name,
      memo: item.memo,
      checkNumber: item.checkNumber,
      referenceNumber: item.referenceNumber,
      originalDescription: description,
      normalizedDescription: normalized,
      rawHash: ofxFingerprint(
        accountId: accountId,
        fitId: item.fitId,
        amountCents: item.signedAmount.cents,
        dateIso: item.postedDate.toIso(),
        normalizedDescription: normalized,
      ),
      duplicateScore: match.score,
      duplicateBand: match.band,
      matchedTransactionId: match.transactionId,
      importByDefault: !match.isHighProbability,
      possibleTransfer: covered == null
          ? _transfers.find(
              accountId: accountId,
              absoluteAmount: item.absoluteAmount,
              date: item.postedDate,
              normalizedDescription: normalized,
              candidates: candidates,
            )
          : null,
      suggestion: suggestion,
      coveredByExistingTransfer: covered != null,
    );
  }

  String _description(ParsedOfxTransaction item) {
    final name = item.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    final memo = item.memo?.trim();
    if (memo != null && memo.isNotEmpty) return memo;
    return 'Lançamento OFX';
  }
}
