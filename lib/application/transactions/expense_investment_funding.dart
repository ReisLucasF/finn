import 'package:finan/application/planning/planning_actions.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/transaction_posting.dart';

/// Produto/cofrinho cuja retirada financia a despesa (casa com o extrato).
class InvestmentFundingSource {
  const InvestmentFundingSource({
    required this.productLabel,
    this.investmentId,
  });

  final String productLabel;

  /// Investimento cadastrado de onde sai o dinheiro. A retirada é vinculada
  /// a ele e desconta da posição.
  final String? investmentId;
}

String withdrawalDescriptionForProduct(String label) {
  final trimmed = label.trim();
  if (trimmed.isEmpty) return 'Dinheiro retirado';
  final replaced = trimmed.replaceFirst(
    RegExp(r'^dinheiro reservado\s+', caseSensitive: false),
    'Dinheiro retirado ',
  );
  if (replaced != trimmed) return replaced;
  if (RegExp(r'^dinheiro retirado\b', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed;
  }
  return 'Dinheiro retirado $trimmed';
}

/// Cria/atualiza/remove a retirada pareada de uma despesa.
///
/// O dinheiro sai do investimento: a retirada **credita** a conta com o mesmo
/// valor que a despesa debita, então o saldo da conta não muda e só o
/// investimento diminui. Exceção: se o extrato importado já trouxe essa
/// retirada (mesma conta, valor e data, com id do banco), o crédito já está
/// lá e a retirada pareada não credita de novo.
class ExpenseInvestmentFunding {
  const ExpenseInvestmentFunding({
    required TransactionRepository transactions,
    required Clock clock,
    required IdGenerator ids,
    LinkInvestmentCash? link,
    UnlinkInvestmentCash? unlink,
    TransactionPosting posting = const TransactionPosting(),
  }) : _transactions = transactions,
       _clock = clock,
       _ids = ids,
       _posting = posting,
       _link = link,
       _unlink = unlink;

  final TransactionRepository _transactions;
  final Clock _clock;
  final IdGenerator _ids;
  final TransactionPosting _posting;
  final LinkInvestmentCash? _link;
  final UnlinkInvestmentCash? _unlink;

  /// Crédito na conta da despesa (o resgate cobre o pagamento), salvo se o
  /// extrato importado já creditou essa retirada.
  Future<List<TransactionEntry>> _credit(Transaction withdrawal) async {
    final accountId = withdrawal.accountId;
    if (accountId == null) return const [];
    if (await _statementCovers(withdrawal)) return const [];
    return _posting.forAccount(
      entryId: _ids.next(),
      transactionId: withdrawal.id,
      accountId: accountId,
      type: TransactionType.income,
      amount: withdrawal.amount,
      createdAt: _clock.nowUtc(),
    );
  }

  /// Já existe resgate importado do banco equivalente a esta retirada?
  Future<bool> _statementCovers(Transaction withdrawal) async {
    final accountId = withdrawal.accountId;
    if (accountId == null) return false;
    final candidates = await _transactions.findReconciliationCandidates(
      userId: withdrawal.userId,
      accountId: accountId,
      absoluteAmount: withdrawal.amount,
      date: withdrawal.transactionDate,
    );
    return candidates.any(
      (item) =>
          item.id != withdrawal.id &&
          item.type == TransactionType.investmentWithdrawal &&
          item.pairedTransactionId == null &&
          item.accountId == accountId &&
          item.amount == withdrawal.amount &&
          (item.externalId?.isNotEmpty ?? false),
    );
  }

  Future<void> _linkPair(Transaction pair, String? investmentId) async {
    final id = investmentId?.trim();
    if (id == null || id.isEmpty || _link == null) return;
    await _link(userId: pair.userId, investmentId: id, transactionId: pair.id);
  }

  Future<void> _unlinkPair(Transaction pair) async {
    if (pair.investmentId == null || pair.isDeleted || _unlink == null) return;
    await _unlink(userId: pair.userId, transactionId: pair.id);
  }

  Future<void> sync({
    required Transaction expense,
    required bool enabled,
    InvestmentFundingSource? source,
  }) async {
    if (expense.type != TransactionType.expense) {
      if (expense.pairedTransactionId != null) await removePair(expense);
      return;
    }
    if (!enabled) {
      if (expense.pairedTransactionId != null) await removePair(expense);
      return;
    }
    if (source == null ||
        (source.productLabel.trim().isEmpty &&
            (source.investmentId?.trim().isEmpty ?? true))) {
      throw const ValidationException(
        'Escolha o produto do investimento da retirada.',
      );
    }
    final existingId = expense.pairedTransactionId;
    if (existingId != null) {
      await _updatePair(
        expense: expense,
        withdrawalId: existingId,
        source: source,
      );
      return;
    }
    await _createPair(expense: expense, source: source);
  }

  Future<void> removePair(Transaction expense) async {
    final pairId = expense.pairedTransactionId;
    if (pairId == null) return;
    final now = _clock.nowUtc();
    final pair = await _transactions.findById(pairId);
    if (pair != null && !pair.isDeleted) {
      await _unlinkPair(pair);
      final fresh = await _transactions.findById(pairId) ?? pair;
      await _transactions.update(
        fresh.copyWith(deletedAt: now, updatedAt: now),
      );
    }
    await _transactions.update(
      expense.copyWith(clearPairedTransactionId: true, updatedAt: now),
    );
  }

  Future<void> _createPair({
    required Transaction expense,
    required InvestmentFundingSource source,
  }) async {
    final now = _clock.nowUtc();
    final withdrawalId = _ids.next();
    final description = withdrawalDescriptionForProduct(source.productLabel);
    final withdrawal = Transaction(
      id: withdrawalId,
      userId: expense.userId,
      type: TransactionType.investmentWithdrawal,
      amount: expense.amount,
      description: description,
      transactionDate: expense.transactionDate,
      competenceDate: expense.transactionDate,
      status: expense.status,
      accountId: expense.accountId,
      pairedTransactionId: expense.id,
      source: TransactionSource.manual,
      notes: 'Retirada vinculada à despesa',
      createdAt: now,
      updatedAt: now,
    );
    await _transactions.insert(withdrawal, await _credit(withdrawal));
    await _transactions.update(
      expense.copyWith(pairedTransactionId: withdrawalId, updatedAt: now),
    );
    await _linkPair(withdrawal, source.investmentId);
  }

  Future<void> _updatePair({
    required Transaction expense,
    required String withdrawalId,
    required InvestmentFundingSource source,
  }) async {
    final pair = await _transactions.findById(withdrawalId);
    if (pair == null || pair.isDeleted) {
      await _transactions.update(
        expense.copyWith(
          clearPairedTransactionId: true,
          updatedAt: _clock.nowUtc(),
        ),
      );
      await _createPair(expense: expense, source: source);
      return;
    }
    // Desvincula antes de mudar valor/data e revincula depois, para a
    // posição do investimento acompanhar.
    await _unlinkPair(pair);
    final fresh = await _transactions.findById(withdrawalId) ?? pair;
    final now = _clock.nowUtc();
    final next = fresh.copyWith(
      amount: expense.amount,
      transactionDate: expense.transactionDate,
      competenceDate: expense.transactionDate,
      accountId: expense.accountId,
      status: expense.status,
      description: withdrawalDescriptionForProduct(source.productLabel),
      updatedAt: now,
    );
    await _transactions.update(next, entries: await _credit(next));
    final updated = await _transactions.findById(withdrawalId);
    if (updated != null) await _linkPair(updated, source.investmentId);
  }
}
