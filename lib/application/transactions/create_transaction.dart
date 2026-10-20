import 'package:finan/application/planning/planning_actions.dart';
import 'package:finan/application/transactions/expense_investment_funding.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/transaction_posting.dart';
import 'package:finan/domain/services/transaction_rules.dart';

class CreateTransaction {
  const CreateTransaction({
    required TransactionRepository transactions,
    required AccountRepository accounts,
    required CategoryRepository categories,
    required TransactionRules rules,
    required TransactionPosting posting,
    required ExpenseInvestmentFunding investmentFunding,
    required LinkInvestmentCash linkInvestmentCash,
    required Clock clock,
    required IdGenerator ids,
  }) : _transactions = transactions,
       _accounts = accounts,
       _categories = categories,
       _rules = rules,
       _posting = posting,
       _investmentFunding = investmentFunding,
       _linkInvestmentCash = linkInvestmentCash,
       _clock = clock,
       _ids = ids;

  final TransactionRepository _transactions;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final TransactionRules _rules;
  final TransactionPosting _posting;
  final ExpenseInvestmentFunding _investmentFunding;
  final LinkInvestmentCash _linkInvestmentCash;
  final Clock _clock;
  final IdGenerator _ids;

  Future<Transaction> call({
    required String userId,
    required TransactionType type,
    required Money amount,
    required LocalDate transactionDate,
    required String accountId,
    String? categoryId,
    String? description,
    String? notes,
    TransactionStatus status = TransactionStatus.confirmed,
    bool fundFromInvestment = false,
    String? investmentProductLabel,
    String? fundingInvestmentId,
    String? linkInvestmentId,
  }) async {
    _rules.validateAmount(amount);
    final account = await _accounts.findById(accountId);
    if (account == null) {
      throw const ValidationException('Conta não encontrada.');
    }
    _rules.validateAccountForCreate(account, userId);
    final category = categoryId == null || categoryId.isEmpty
        ? null
        : await _categories.findById(categoryId);
    if (categoryId != null && categoryId.isNotEmpty && category == null) {
      throw const ValidationException('Categoria não encontrada.');
    }
    if (category != null) {
      _rules.validateCategory(category, type, allowInactive: false);
    }
    final storedType = category?.type.storedType(type) ?? type;
    if (fundFromInvestment && storedType != TransactionType.expense) {
      throw const ValidationException(
        'Só despesa pode gerar retirada de investimento.',
      );
    }

    final now = _clock.nowUtc();
    final id = _ids.next();
    final transaction = Transaction(
      id: id,
      userId: userId,
      type: storedType,
      amount: amount,
      description: _blankToNull(description),
      transactionDate: transactionDate,
      competenceDate: transactionDate,
      status: status,
      accountId: accountId,
      categoryId: category?.id,
      source: TransactionSource.manual,
      notes: _blankToNull(notes),
      createdAt: now,
      updatedAt: now,
    );
    final entries = _posting.forAccount(
      entryId: _ids.next(),
      transactionId: id,
      accountId: accountId,
      type: _entryType(storedType, requested: type),
      amount: amount,
      createdAt: now,
    );
    await _transactions.insert(transaction, entries);
    if (fundFromInvestment) {
      await _investmentFunding.sync(
        expense: transaction,
        enabled: true,
        source: InvestmentFundingSource(
          productLabel: investmentProductLabel ?? '',
          investmentId: fundingInvestmentId,
        ),
      );
    }
    final linkId = linkInvestmentId?.trim();
    if (linkId != null &&
        linkId.isNotEmpty &&
        (storedType == TransactionType.investmentContribution ||
            storedType == TransactionType.investmentWithdrawal)) {
      await _linkInvestmentCash(
        userId: userId,
        investmentId: linkId,
        transactionId: id,
      );
    } else if (linkId != null &&
        linkId.isNotEmpty &&
        storedType != TransactionType.investmentContribution &&
        storedType != TransactionType.investmentWithdrawal) {
      throw const ValidationException(
        'Só aplicação ou retirada pode vincular a um investimento.',
      );
    }
    return (await _transactions.findById(id)) ?? transaction;
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
