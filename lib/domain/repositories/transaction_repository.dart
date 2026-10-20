import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';

class TransactionQuery {
  const TransactionQuery({
    required this.userId,
    this.type,
    this.accountId,
    this.categoryIds,
    this.includeUncategorized = false,
    this.investmentId,
    this.fromInclusive,
    this.toInclusive,
    this.search,
    this.uncategorizedOnly = false,
    this.newestFirst = true,
    this.limit = 40,
    this.offset = 0,
  });

  final String userId;
  final TransactionType? type;
  final String? accountId;
  /// Uma ou mais categorias (OR). Vazio/nulo = sem filtro por id.
  final List<String>? categoryIds;
  /// Inclui lançamentos sem categoria (OR com [categoryIds]).
  final bool includeUncategorized;
  final String? investmentId;
  final LocalDate? fromInclusive;
  final LocalDate? toInclusive;
  final String? search;
  /// Atalho: só sem categoria (ignora [categoryIds]).
  final bool uncategorizedOnly;
  /// `true` = mais recente primeiro; `false` = mais antigo primeiro.
  final bool newestFirst;
  final int limit;
  final int offset;
}

class AccountBalanceParts {
  const AccountBalanceParts({
    required this.accountId,
    required this.initialBalance,
    required this.confirmedEntries,
  });

  final String accountId;
  final Money initialBalance;
  final Money confirmedEntries;
}

class TransactionPage {
  const TransactionPage({
    required this.items,
    required this.total,
    this.nextDate,
  });

  final List<Transaction> items;
  final int total;

  /// Data do lançamento seguinte, fora desta página. Nula quando a lista acabou.
  final LocalDate? nextDate;
}

class ClassifiedDescription {
  const ClassifiedDescription({
    required this.description,
    required this.categoryId,
  });

  final String description;
  final String categoryId;
}

abstract class TransactionRepository {
  Future<void> insert(Transaction transaction, List<TransactionEntry> entries);

  Future<void> update(
    Transaction transaction, {
    List<TransactionEntry>? entries,
  });

  Future<Transaction?> findById(String id);

  Future<List<TransactionEntry>> entriesFor(String transactionId);

  Future<TransactionPage> list(TransactionQuery query);

  Future<int> recategorize({
    required TransactionQuery query,
    required String categoryId,
    required DateTime updatedAt,
    required List<TransactionType> types,
    TransactionType? postedType,
    bool accountCashOnly = false,
  });

  Future<List<InvestmentCashEvent>> listUnlinkedInvestmentCash(String userId);

  /// Aportes/resgates confirmados, vinculados ou não.
  Future<List<InvestmentCashEvent>> listInvestmentCash(String userId);

  Future<Money> sumConfirmedAmount({
    required String userId,
    required TransactionType type,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
    Iterable<String>? categoryIds,
  });

  Future<List<DatedFlow>> confirmedFlows({
    required String userId,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  });

  Future<List<CategoryAmount>> categoryTotals({
    required String userId,
    required TransactionType type,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  });

  /// Despesas confirmadas agrupadas por id de categoria (sem as não categorizadas).
  Future<Map<String, Money>> expenseByCategoryId({
    required String userId,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  });

  Future<List<AccountBalanceParts>> balancePartsForUser(String userId);

  Future<List<DailyAccountTotal>> confirmedDailyTotals(String userId);

  Future<bool> existsByCategory(String categoryId);

  Future<List<Transaction>> findReconciliationCandidates({
    required String userId,
    required String accountId,
    required Money absoluteAmount,
    required LocalDate date,
    String? externalId,
  });

  Future<List<ClassifiedDescription>> recentClassifications(
    String userId, {
    int limit = 200,
  });

  Future<void> insertMany(
    List<Transaction> transactions,
    List<TransactionEntry> entries,
  );

  Future<Set<String>> existingExternalIds(String userId, List<String> externalIds);

  Future<bool> linkExternalId({
    required String userId,
    required String transactionId,
    required String externalId,
    required DateTime reconciledAt,
    String? categoryId,
  });
}
