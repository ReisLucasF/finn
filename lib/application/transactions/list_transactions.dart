import 'package:finan/app/app_config.dart';
import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/repositories/user_repository.dart';

enum TransactionPeriodKind {
  all,
  currentMonth,
  previousMonth,
  last3Months,
  last6Months,
  yearToDate,
  custom,
}

class TransactionPeriod {
  const TransactionPeriod({
    required this.kind,
    this.customStart,
    this.customEndInclusive,
  });

  static const all = TransactionPeriod(kind: TransactionPeriodKind.all);

  static const currentMonth = TransactionPeriod(
    kind: TransactionPeriodKind.currentMonth,
  );

  static const previousMonth = TransactionPeriod(
    kind: TransactionPeriodKind.previousMonth,
  );

  static const last3Months = TransactionPeriod(
    kind: TransactionPeriodKind.last3Months,
  );

  static const last6Months = TransactionPeriod(
    kind: TransactionPeriodKind.last6Months,
  );

  static const yearToDate = TransactionPeriod(
    kind: TransactionPeriodKind.yearToDate,
  );

  factory TransactionPeriod.custom({
    required LocalDate start,
    required LocalDate endInclusive,
  }) {
    return TransactionPeriod(
      kind: TransactionPeriodKind.custom,
      customStart: start,
      customEndInclusive: endInclusive,
    );
  }

  final TransactionPeriodKind kind;
  final LocalDate? customStart;
  final LocalDate? customEndInclusive;

  String get label => switch (kind) {
    TransactionPeriodKind.all => 'Tudo',
    TransactionPeriodKind.currentMonth => 'Este mês',
    TransactionPeriodKind.previousMonth => 'Mês passado',
    TransactionPeriodKind.last3Months => 'Últimos 3 meses',
    TransactionPeriodKind.last6Months => 'Últimos 6 meses',
    TransactionPeriodKind.yearToDate => 'Ano atual',
    TransactionPeriodKind.custom => 'Personalizado',
  };

  FinancialPeriod? resolve({
    required LocalDate today,
    required int monthStartDay,
  }) {
    final current = FinancialPeriod.containing(today, monthStartDay);
    return switch (kind) {
      TransactionPeriodKind.all => null,
      TransactionPeriodKind.currentMonth => current,
      TransactionPeriodKind.previousMonth => FinancialPeriod.containing(
        current.startInclusive.addDays(-1),
        monthStartDay,
      ),
      TransactionPeriodKind.last3Months => _trailing(current, monthStartDay, 3),
      TransactionPeriodKind.last6Months => _trailing(current, monthStartDay, 6),
      TransactionPeriodKind.yearToDate => FinancialPeriod(
        startInclusive: LocalDate(today.year, 1, 1),
        endExclusive: current.endExclusive,
      ),
      TransactionPeriodKind.custom => _custom(),
    };
  }

  FinancialPeriod _custom() {
    final start = customStart;
    final end = customEndInclusive;
    if (start == null || end == null) {
      throw const ValidationException('Informe o período personalizado.');
    }
    if (start > end) {
      throw const ValidationException(
        'A data inicial deve ser anterior à final.',
      );
    }
    return FinancialPeriod(
      startInclusive: start,
      endExclusive: end.addDays(1),
    );
  }

  static FinancialPeriod _trailing(
    FinancialPeriod current,
    int monthStartDay,
    int count,
  ) {
    var start = current.startInclusive;
    var cursor = current.startInclusive.addDays(-1);
    for (var index = 1; index < count; index++) {
      final previous = FinancialPeriod.containing(cursor, monthStartDay);
      start = previous.startInclusive;
      cursor = previous.startInclusive.addDays(-1);
    }
    return FinancialPeriod(
      startInclusive: start,
      endExclusive: current.endExclusive,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TransactionPeriod &&
      other.kind == kind &&
      other.customStart == customStart &&
      other.customEndInclusive == customEndInclusive;

  @override
  int get hashCode => Object.hash(kind, customStart, customEndInclusive);
}

class ListTransactions {
  const ListTransactions({
    required TransactionRepository transactions,
    required UserRepository users,
    required Clock clock,
  }) : _transactions = transactions,
       _users = users,
       _clock = clock;

  final TransactionRepository _transactions;
  final UserRepository _users;
  final Clock _clock;

  Future<TransactionPage> call({
    required String userId,
    TransactionType? type,
    String? accountId,
    List<String>? categoryIds,
    bool includeUncategorized = false,
    String? investmentId,
    TransactionPeriod period = TransactionPeriod.all,
    String? search,
    bool uncategorizedOnly = false,
    bool newestFirst = true,
    int limit = AppConfig.transactionPageSize,
    int offset = 0,
  }) async {
    final range = await _range(userId, period);
    final normalizedSearch = search?.trim();
    return _transactions.list(
      TransactionQuery(
        userId: userId,
        type: type,
        accountId: accountId,
        categoryIds: categoryIds,
        includeUncategorized: includeUncategorized,
        investmentId: investmentId,
        fromInclusive: range?.startInclusive,
        toInclusive: range?.endInclusive,
        search: normalizedSearch == null || normalizedSearch.isEmpty
            ? null
            : normalizedSearch,
        uncategorizedOnly: uncategorizedOnly,
        newestFirst: newestFirst,
        limit: limit,
        offset: offset,
      ),
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
