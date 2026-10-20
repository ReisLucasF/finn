import 'package:finan/core/date/local_date.dart';

class FinancialPeriod {
  const FinancialPeriod({
    required this.startInclusive,
    required this.endExclusive,
  });

  final LocalDate startInclusive;
  final LocalDate endExclusive;

  LocalDate get endInclusive => endExclusive.addDays(-1);

  /// Período que contém [date], começando no dia [monthStartDay] de cada mês.
  /// Se o dia não existir naquele mês, usa o último dia do mês.
  static FinancialPeriod containing(LocalDate date, int monthStartDay) {
    final startDay = monthStartDay < 1
        ? 1
        : monthStartDay > 31
        ? 31
        : monthStartDay;
    final thisAnchor = _anchor(date.year, date.month, startDay);
    final LocalDate start;
    if (date.compareTo(thisAnchor) >= 0) {
      start = thisAnchor;
    } else {
      final previous = _shiftMonth(date.year, date.month, -1);
      start = _anchor(previous.$1, previous.$2, startDay);
    }
    final next = _shiftMonth(start.year, start.month, 1);
    final end = _anchor(next.$1, next.$2, startDay);
    return FinancialPeriod(startInclusive: start, endExclusive: end);
  }

  static LocalDate _anchor(int year, int month, int day) {
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    final resolved = day > lastDay ? lastDay : day;
    return LocalDate(year, month, resolved);
  }

  static (int, int) _shiftMonth(int year, int month, int delta) {
    final index = (year * 12 + (month - 1)) + delta;
    final shiftedYear = index ~/ 12;
    final shiftedMonth = index % 12 + 1;
    return (shiftedYear, shiftedMonth);
  }
}
