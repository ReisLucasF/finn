import 'package:finan/application/dashboard/dashboard_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const today = LocalDate(2026, 10, 6);

  test('presets de mês financeiro e janelas', () {
    final current = DashboardPeriodFilter.currentMonth.resolve(
      today: today,
      monthStartDay: 1,
    );
    expect(current.startInclusive, const LocalDate(2026, 10, 1));
    expect(current.endExclusive, const LocalDate(2026, 11, 1));

    final previous = DashboardPeriodFilter.previousMonth.resolve(
      today: today,
      monthStartDay: 1,
    );
    expect(previous.startInclusive, const LocalDate(2026, 9, 1));
    expect(previous.endExclusive, const LocalDate(2026, 10, 1));

    final last3 = DashboardPeriodFilter.last3Months.resolve(
      today: today,
      monthStartDay: 1,
    );
    expect(last3.startInclusive, const LocalDate(2026, 8, 1));
    expect(last3.endExclusive, const LocalDate(2026, 11, 1));

    final ytd = DashboardPeriodFilter.yearToDate.resolve(
      today: today,
      monthStartDay: 1,
    );
    expect(ytd.startInclusive, const LocalDate(2026, 1, 1));
    expect(ytd.endExclusive, const LocalDate(2026, 11, 1));
  });

  test('período personalizado valida as datas', () {
    final range = DashboardPeriodFilter.custom(
      start: const LocalDate(2026, 3, 1),
      endInclusive: const LocalDate(2026, 3, 15),
    ).resolve(today: today, monthStartDay: 1);
    expect(range.startInclusive, const LocalDate(2026, 3, 1));
    expect(range.endExclusive, const LocalDate(2026, 3, 16));

    expect(
      () => DashboardPeriodFilter.custom(
        start: const LocalDate(2026, 3, 15),
        endInclusive: const LocalDate(2026, 3, 1),
      ).resolve(today: today, monthStartDay: 1),
      throwsA(isA<ValidationException>()),
    );
  });
}
