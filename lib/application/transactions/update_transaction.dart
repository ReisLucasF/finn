import 'package:finan/application/planning/planning_actions.dart';
import 'package:finan/application/transactions/expense_investment_funding.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/transaction_posting.dart';
import 'package:finan/domain/services/transaction_rules.dart';

class UpdateTransaction {
  const UpdateTransaction({
    required TransactionRepository transactions,
    required AccountRepository accounts,
    required CategoryRepository categories,
    required TransactionRules rules,
    required TransactionPosting posting,
    required ExpenseInvestmentFunding investmentFunding,
    required LinkInvestmentCash linkInvestmentCash,
    required UnlinkInvestmentCash unlinkInvestmentCash,
    required Clock clock,
    required IdGenerator ids,
  }) : _transactions = transactions,
       _accounts = accounts,
       _categories = categories,
       _rules = rules,
       _posting = posting,
       _investmentFunding = investmentFunding,
       _linkInvestmentCash = linkInvestmentCash,
       _unlinkInvestmentCash = unlinkInvestmentCash,
       _clock = clock,
       _ids = ids;

  final TransactionRepository _transactions;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final TransactionRules _rules;
  final TransactionPosting _posting;
  final ExpenseInvestmentFunding _investmentFunding;
  final LinkInvestmentCash _linkInvestmentCash;
  final UnlinkInvestmentCash _unlinkInvestmentCash;
  final Clock _clock;
  final IdGenerator _ids;

  Future<Transaction> call({
    required String id,
    required TransactionType type,
    required Money amount,
    required LocalDate transactionDate,
    required String accountId,
    String? categoryId,
    required TransactionStatus status,
    String? description,
    String? notes,
    bool? fundFromInvestment,
    String? investmentProductLabel,
    String? fundingInvestmentId,
    String? linkInvestmentId,
  }) async {
    final current = await _transactions.findById(id);
    if (current == null || current.isDeleted) {
      throw const ValidationException('Lançamento não encontrado.');
    }
    _rules.validateAmount(amount);
    final account = await _accounts.findById(accountId);
    if (account == null) {
      throw const ValidationException('Conta não encontrada.');
    }
    _rules.validateAccountForUpdate(
      account,
      current.userId,
      previousAccountId: current.accountId,
    );
    final trimmedCategory = categoryId?.trim();
    final category = trimmedCategory == null || trimmedCategory.isEmpty
        ? null
        : await _categories.findById(trimmedCategory);
    if (trimmedCategory != null &&
        trimmedCategory.isNotEmpty &&
        category == null) {
      throw const ValidationException('Categoria não encontrada.');
    }
    if (category != null) {
      final keepingCategory = category.id == current.categoryId;
      _rules.validateCategory(
        category,
        type,
        allowInactive: keepingCategory && !category.isActive,
      );
    }
    final storedType = category?.type.storedType(type) ?? type;
    if (storedType == TransactionType.investmentContribution ||
        storedType == TransactionType.investmentWithdrawal) {
      if (current.creditCardId != null || current.transferId != null) {
        throw const ValidationException(
          'Esse lançamento não pode ser aplicação ou resgate.',
        );
      }
    }
    if (storedType == TransactionType.transfer &&
        category?.type == CategoryType.internalTransfer) {
      if (current.creditCardId != null || current.transferId != null) {
        throw const ValidationException(
          'Transferência pareada ou de cartão não vira transferência interna.',
        );
      }
    }
    final fundingEnabled =
        (fundFromInvestment ?? current.pairedTransactionId != null) &&
        storedType == TransactionType.expense;
    if (fundFromInvestment == true && storedType != TransactionType.expense) {
      throw const ValidationException(
        'Só despesa pode gerar retirada de investimento.',
      );
    }
    // null = não alterar vínculo; '' = desvincular; id = vincular
    final linkId = linkInvestmentId?.trim();
    final clearLink = linkInvestmentId != null && (linkId == null || linkId.isEmpty);
    if (linkId != null &&
        linkId.isNotEmpty &&
        storedType != TransactionType.investmentContribution &&
        storedType != TransactionType.investmentWithdrawal) {
      throw const ValidationException(
        'Só aplicação ou retirada pode vincular a um investimento.',
      );
    }
    if (current.investmentId != null &&
        linkId != null &&
        linkId.isNotEmpty &&
        linkId != current.investmentId) {
      throw const ValidationException(
        'Desvincule antes de ligar a outro investimento.',
      );
    }

    final now = _clock.nowUtc();
    final updated = current.copyWith(
      type: storedType,
      amount: amount,
      transactionDate: transactionDate,
      competenceDate: transactionDate,
      accountId: accountId,
      categoryId: category?.id,
      clearCategory: category == null,
      status: status,
      description: _blankToNull(description),
      clearDescription: _blankToNull(description) == null,
      notes: _blankToNull(notes),
      clearNotes: _blankToNull(notes) == null,
      updatedAt: now,
    );
    var entrySign = type;
    if (storedType == TransactionType.transfer &&
        type != TransactionType.income &&
        type != TransactionType.expense) {
      final existing = await _transactions.entriesFor(id);
      entrySign = existing.isNotEmpty && existing.first.amount.cents < 0
          ? TransactionType.expense
          : TransactionType.income;
    }
    final entries = _posting.forAccount(
      entryId: _ids.next(),
      transactionId: id,
      accountId: accountId,
      type: _entryType(storedType, requested: entrySign),
      amount: amount,
      createdAt: now,
    );
    await _transactions.update(updated, entries: entries);

    var label = investmentProductLabel?.trim() ?? '';
    var fundingInvestment = fundingInvestmentId;
    if (fundingEnabled && current.pairedTransactionId != null) {
      final pair = await _transactions.findById(current.pairedTransactionId!);
      if (label.isEmpty) label = pair?.description?.trim() ?? '';
      // null = manter o investimento atual da retirada; '' = nenhum.
      fundingInvestment ??= pair?.investmentId;
    }
    await _investmentFunding.sync(
      expense: updated,
      enabled: fundingEnabled,
      source: fundingEnabled
          ? InvestmentFundingSource(
              productLabel: label,
              investmentId: fundingInvestment,
            )
          : null,
    );
    if (clearLink && current.investmentId != null) {
      await _unlinkInvestmentCash(
        userId: current.userId,
        transactionId: id,
      );
    } else if (current.investmentId == null &&
        linkId != null &&
        linkId.isNotEmpty &&
        (storedType == TransactionType.investmentContribution ||
            storedType == TransactionType.investmentWithdrawal)) {
      await _linkInvestmentCash(
        userId: current.userId,
        investmentId: linkId,
        transactionId: id,
      );
    }
    return (await _transactions.findById(id)) ?? updated;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

TransactionType _entryType(
  TransactionType stored, {
  required TransactionType requested,
}) {
  return switch (stored) {
    TransactionType.investmentContribution => TransactionType.expense,
    TransactionType.investmentWithdrawal => TransactionType.income,
    TransactionType.transfer =>
      requested == TransactionType.expense
          ? TransactionType.expense
          : TransactionType.income,
    _ => stored,
  };
}
