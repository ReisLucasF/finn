import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';

enum DashboardPeriodKind {
  currentMonth,
  previousMonth,
  last3Months,
  last6Months,
  yearToDate,
  custom,
}

class DashboardPeriodFilter {
  const DashboardPeriodFilter({
    required this.kind,
    this.customStart,
    this.customEndInclusive,
  });

  static const currentMonth = DashboardPeriodFilter(
    kind: DashboardPeriodKind.currentMonth,
  );

  static const previousMonth = DashboardPeriodFilter(
    kind: DashboardPeriodKind.previousMonth,
  );

  static const last3Months = DashboardPeriodFilter(
    kind: DashboardPeriodKind.last3Months,
  );

  static const last6Months = DashboardPeriodFilter(
    kind: DashboardPeriodKind.last6Months,
  );

  static const yearToDate = DashboardPeriodFilter(
    kind: DashboardPeriodKind.yearToDate,
  );

  factory DashboardPeriodFilter.custom({
    required LocalDate start,
    required LocalDate endInclusive,
  }) {
    return DashboardPeriodFilter(
      kind: DashboardPeriodKind.custom,
      customStart: start,
      customEndInclusive: endInclusive,
    );
  }

  final DashboardPeriodKind kind;
  final LocalDate? customStart;
  final LocalDate? customEndInclusive;

  String get label => switch (kind) {
    DashboardPeriodKind.currentMonth => 'Este mês',
    DashboardPeriodKind.previousMonth => 'Mês passado',
    DashboardPeriodKind.last3Months => 'Últimos 3 meses',
    DashboardPeriodKind.last6Months => 'Últimos 6 meses',
    DashboardPeriodKind.yearToDate => 'Ano atual',
    DashboardPeriodKind.custom => 'Personalizado',
  };

  FinancialPeriod resolve({
    required LocalDate today,
    required int monthStartDay,
  }) {
    final current = FinancialPeriod.containing(today, monthStartDay);
    return switch (kind) {
      DashboardPeriodKind.currentMonth => current,
      DashboardPeriodKind.previousMonth => FinancialPeriod.containing(
        current.startInclusive.addDays(-1),
        monthStartDay,
      ),
      DashboardPeriodKind.last3Months => _trailing(
        current,
        monthStartDay,
        3,
      ),
      DashboardPeriodKind.last6Months => _trailing(
        current,
        monthStartDay,
        6,
      ),
      DashboardPeriodKind.yearToDate => FinancialPeriod(
        startInclusive: LocalDate(today.year, 1, 1),
        endExclusive: current.endExclusive,
      ),
      DashboardPeriodKind.custom => _custom(),
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
}
