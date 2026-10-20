import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/ofx_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/duplicate_detection_service.dart';
import 'package:finan/domain/services/transaction_posting.dart';
import 'package:finan/domain/services/transaction_rules.dart';

class OfxImportResult {
  const OfxImportResult({
    required this.imported,
    required this.ignored,
    required this.duplicates,
  });

  final int imported;
  final int ignored;
  final int duplicates;
}

class ImportOfx {
  const ImportOfx({
    required OfxRepository ofx,
    required AccountRepository accounts,
    required CategoryRepository categories,
    required TransactionRepository transactions,
    required TransactionRules rules,
    required TransactionPosting posting,
    required Clock clock,
    required IdGenerator ids,
  }) : _ofx = ofx,
       _accounts = accounts,
       _categories = categories,
       _transactions = transactions,
       _rules = rules,
       _posting = posting,
       _clock = clock,
       _ids = ids;

  final OfxRepository _ofx;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final TransactionRules _rules;
  final TransactionPosting _posting;
  final Clock _clock;
  final IdGenerator _ids;

  Future<OfxImportResult> call({
    required String userId,
    required OfxAnalysis analysis,
    required List<OfxImportDecision> decisions,
  }) async {
    final account = await _accounts.findById(analysis.accountId);
    if (account == null || account.isDeleted || account.userId != userId) {
      throw const ValidationException('Conta inválida.');
    }
    if (!account.isActive) {
      throw const ValidationException('A conta está desativada.');
    }
    final byLine = {for (final decision in decisions) decision.lineId: decision};
    final now = _clock.nowUtc();
    final importId = _ids.next();
    final usedFitIds = <String>{};
    final transactions = <Transaction>[];
    final entries = <TransactionEntry>[];
    final transfers = <OfxRecordedTransfer>[];
    final retireIds = <String>[];
    final stored = <OfxImportLineRecord>[];
    var imported = 0;
    var ignored = 0;
    var duplicates = 0;

    for (final line in analysis.lines) {
      if (line.duplicateScore >= DuplicateMatch.highProbabilityThreshold) {
        duplicates++;
      }
      final decision = byLine[line.id];
      final fitId = line.fitId?.trim();
      final repeatedFitId =
          fitId != null && fitId.isNotEmpty && usedFitIds.contains(fitId);
      final wantsImport = (decision?.import ?? false) && !repeatedFitId;
      if (!wantsImport) {
        ignored++;
        stored.add(_line(importId, line, now, reconciled: false));
        continue;
      }
      final transferAccountId = decision?.transferAccountId;
      if (transferAccountId != null && transferAccountId.isNotEmpty) {
        await _asTransfer(
          userId: userId,
          analysis: analysis,
          line: line,
          otherAccountId: transferAccountId,
          linkTransactionId: decision?.linkTransactionId,
          fitId: fitId,
          now: now,
          transactions: transactions,
          entries: entries,
          transfers: transfers,
          retireIds: retireIds,
        );
        if (fitId != null && fitId.isNotEmpty) usedFitIds.add(fitId);
        imported++;
        stored.add(_line(importId, line, now, reconciled: true));
        continue;
      }
      final categoryId = decision?.categoryId;
      Category? category;
      if (categoryId != null && categoryId.isNotEmpty) {
        category = await _categories.findById(categoryId);
        if (category == null) {
          throw const ValidationException('Categoria não encontrada.');
        }
        _rules.validateCategory(category, line.type, allowInactive: false);
      }
      final transactionId = _ids.next();
      final memo = line.memo?.trim();
      final transaction = Transaction(
        id: transactionId,
        userId: userId,
        type: line.type,
        amount: line.absoluteAmount,
        description: line.originalDescription,
        transactionDate: line.postedDate,
        competenceDate: line.postedDate,
        status: TransactionStatus.confirmed,
        accountId: analysis.accountId,
        categoryId: category?.id,
        source: TransactionSource.ofx,
        externalId: fitId,
        notes: memo == null || memo == line.originalDescription ? null : memo,
        reconciledAt: now,
        createdAt: now,
        updatedAt: now,
      );
      transactions.add(transaction);
      entries.addAll(
        _posting.forAccount(
          entryId: _ids.next(),
          transactionId: transactionId,
          accountId: analysis.accountId,
          type: line.type,
          amount: line.absoluteAmount,
          createdAt: now,
        ),
      );
      if (fitId != null && fitId.isNotEmpty) usedFitIds.add(fitId);
      imported++;
      stored.add(_line(importId, line, now, reconciled: true));
    }

    await _ofx.save(
      OfxImportBundle(
        header: OfxImportHeader(
          id: importId,
          userId: userId,
          accountId: analysis.accountId,
          fileName: analysis.fileName,
          importedAt: now,
          totalRecords: analysis.lines.length,
          importedRecords: imported,
          duplicateRecords: duplicates,
          ignoredRecords: ignored,
        ),
        lines: stored,
        transactions: transactions,
        entries: entries,
        transfers: transfers,
        retireTransactionIds: retireIds,
      ),
    );
    return OfxImportResult(
      imported: imported,
      ignored: ignored,
      duplicates: duplicates,
    );
  }

  Future<void> _asTransfer({
    required String userId,
    required OfxAnalysis analysis,
    required OfxReviewLine line,
    required String otherAccountId,
    required String? linkTransactionId,
    required String? fitId,
    required DateTime now,
    required List<Transaction> transactions,
    required List<TransactionEntry> entries,
    required List<OfxRecordedTransfer> transfers,
    required List<String> retireIds,
  }) async {
    if (otherAccountId == analysis.accountId) {
      throw const ValidationException('Escolha a outra conta da transferência.');
    }
    final other = await _accounts.findById(otherAccountId);
    if (other == null || other.userId != userId || !other.isActive) {
      throw const ValidationException('Conta da transferência não encontrada.');
    }
    final outflow = line.type == TransactionType.expense;
    final sourceId = outflow ? analysis.accountId : otherAccountId;
    final destinationId = outflow ? otherAccountId : analysis.accountId;
    if (linkTransactionId != null && linkTransactionId.isNotEmpty) {
      final existing = await _transactions.findById(linkTransactionId);
      final opposite = outflow ? TransactionType.income : TransactionType.expense;
      if (existing != null && existing.deletedAt == null) {
        final distance = DateTime.utc(
          existing.transactionDate.year,
          existing.transactionDate.month,
          existing.transactionDate.day,
        ).difference(
          DateTime.utc(line.postedDate.year, line.postedDate.month, line.postedDate.day),
        ).inDays.abs();
        if (existing.userId == userId &&
            existing.accountId == otherAccountId &&
            existing.type == opposite &&
            existing.amount == line.absoluteAmount &&
            distance <= 2 &&
            !retireIds.contains(existing.id)) {
          retireIds.add(existing.id);
        }
      }
    }
    final transferId = _ids.next();
    final transactionId = _ids.next();
    transfers.add(
      OfxRecordedTransfer(
        id: transferId,
        userId: userId,
        sourceAccountId: sourceId,
        destinationAccountId: destinationId,
        amount: line.absoluteAmount,
        date: line.postedDate,
        description: line.originalDescription,
        createdAt: now,
      ),
    );
    transactions.add(
      Transaction(
        id: transactionId,
        userId: userId,
        type: TransactionType.transfer,
        amount: line.absoluteAmount,
        description: line.originalDescription,
        transactionDate: line.postedDate,
        status: TransactionStatus.confirmed,
        accountId: sourceId,
        transferId: transferId,
        source: TransactionSource.ofx,
        externalId: fitId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    entries.add(
      TransactionEntry(
        id: _ids.next(),
        transactionId: transactionId,
        accountId: sourceId,
        amount: -line.absoluteAmount,
        createdAt: now,
      ),
    );
    entries.add(
      TransactionEntry(
        id: _ids.next(),
        transactionId: transactionId,
        accountId: destinationId,
        amount: line.absoluteAmount,
        createdAt: now,
      ),
    );
  }

  OfxImportLineRecord _line(
    String importId,
    OfxReviewLine line,
    DateTime now, {
    required bool reconciled,
  }) {
    return OfxImportLineRecord(
      id: _ids.next(),
      importId: importId,
      fitId: line.fitId,
      transactionType: line.trnType,
      postedAt: line.postedAtRaw,
      amountCents: line.signedAmount.cents,
      name: line.name,
      memo: line.memo,
      checkNumber: line.checkNumber,
      referenceNumber: line.referenceNumber,
      rawHash: line.rawHash,
      duplicateScore: line.duplicateScore,
      duplicateStatus: _status(line.duplicateBand),
      matchedTransactionId: line.matchedTransactionId,
      reconciliationStatus: reconciled ? 'reconciled' : 'ignored',
      createdAt: now,
    );
  }

  String _status(DuplicateBand band) {
    return switch (band) {
      DuplicateBand.none => 'none',
      DuplicateBand.possible => 'possible',
      DuplicateBand.probable => 'probable',
      DuplicateBand.veryLikely => 'very_likely',
    };
  }
}
