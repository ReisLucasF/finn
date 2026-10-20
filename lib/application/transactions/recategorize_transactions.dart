import 'package:finan/app/app_config.dart';
import 'package:finan/application/transactions/list_transactions.dart';
import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/repositories/user_repository.dart';

class RecategorizeTransactions {
  const RecategorizeTransactions({
    required TransactionRepository transactions,
    required CategoryRepository categories,
    required UserRepository users,
    required Clock clock,
  }) : _transactions = transactions,
       _categories = categories,
       _users = users,
       _clock = clock;

  final TransactionRepository _transactions;
  final CategoryRepository _categories;
  final UserRepository _users;
  final Clock _clock;

  Future<int> call({
    required String userId,
    required String categoryId,
    TransactionType? type,
    String? accountId,
    String? currentCategoryId,
    List<String>? currentCategoryIds,
    bool includeUncategorized = false,
    bool uncategorizedOnly = false,
    TransactionPeriod period = TransactionPeriod.currentMonth,
    String? search,
  }) async {
    final category = await _categories.findById(categoryId);
    if (category == null ||
        category.deletedAt != null ||
        (category.userId != null && category.userId != userId)) {
      throw const ValidationException('Categoria não encontrada.');
    }
    if (!category.isActive) {
      throw const ValidationException('A categoria está desativada.');
    }
    final effect = _effect(category.type);
    final types = [
      for (final source in effect.sources)
        if (type == null || source == type) source,
    ];
    if (types.isEmpty) return 0;
    final range = await _range(userId, period);
    final normalizedSearch = search?.trim();
    final cashOnly = _needsAccountCashGuard(effect);
    final ids = [
      ...?currentCategoryIds,
      ?currentCategoryId,
    ];
    return _transactions.recategorize(
      query: TransactionQuery(
        userId: userId,
        type: type,
        accountId: accountId,
        categoryIds: uncategorizedOnly || ids.isEmpty ? null : ids,
        includeUncategorized: !uncategorizedOnly && includeUncategorized,
        uncategorizedOnly: uncategorizedOnly,
        fromInclusive: range?.startInclusive,
        toInclusive: range?.endInclusive,
        search: normalizedSearch == null || normalizedSearch.isEmpty
            ? null
            : normalizedSearch,
      ),
      categoryId: category.id,
      updatedAt: _clock.nowUtc(),
      types: types,
      postedType: effect.posted,
      accountCashOnly: cashOnly,
    );
  }

  Future<FinancialPeriod?> _range(
    String userId,
    TransactionPeriod period,
  ) async {
    final user = await _users.findCurrent();
    final startDay =
        user?.financialMonthStart ?? AppConfig.defaultFinancialMonthStart;
    return period.resolve(today: _clock.today(), monthStartDay: startDay);
  }
}

({List<TransactionType> sources, TransactionType? posted}) _effect(
  CategoryType type,
) {
  return switch (type) {
    CategoryType.investmentApplication => (
      sources: [
        TransactionType.expense,
        TransactionType.investmentContribution,
      ],
      posted: TransactionType.investmentContribution,
    ),
    CategoryType.investmentRedemption => (
      sources: [TransactionType.income, TransactionType.investmentWithdrawal],
      posted: TransactionType.investmentWithdrawal,
    ),
    CategoryType.internalTransfer => (
      sources: [
        TransactionType.income,
        TransactionType.expense,
        TransactionType.transfer,
      ],
      posted: TransactionType.transfer,
    ),
    // Desfaz aplicação/resgate/transferência interna sem mudar o caixa.
    CategoryType.expense => (
      sources: [
        TransactionType.expense,
        TransactionType.investmentContribution,
        TransactionType.transfer,
      ],
      posted: TransactionType.expense,
    ),
    CategoryType.income => (
      sources: [
        TransactionType.income,
        TransactionType.investmentWithdrawal,
        TransactionType.transfer,
      ],
      posted: TransactionType.income,
    ),
    CategoryType.both => (
      sources: [TransactionType.income, TransactionType.expense],
      posted: null,
    ),
  };
}

bool _needsAccountCashGuard(
  ({List<TransactionType> sources, TransactionType? posted}) effect,
) {
  const guarded = {
    TransactionType.investmentContribution,
    TransactionType.investmentWithdrawal,
    TransactionType.transfer,
  };
  if (effect.posted != null && guarded.contains(effect.posted)) {
    return true;
  }
  return effect.sources.any(guarded.contains);
}
