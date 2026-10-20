import 'package:finan/core/money/money.dart';

class GoalProjection {
  const GoalProjection({
    required this.futureValue,
    required this.monthsToTarget,
    required this.requiredMonthlySavings,
  });

  final Money futureValue;
  final int? monthsToTarget;
  final Money requiredMonthlySavings;
}

class GoalProjectionService {
  const GoalProjectionService();

  static const maxMonths = 1200;

  /// Juros compostos em centavos.
  /// A taxa entra em partes por milhão: 8000 = 0,8% ao mês.
  Money futureValue({
    required Money present,
    required Money monthlyContribution,
    required int ratePerMillion,
    required int months,
  }) {
    var cents = present.cents;
    for (var month = 0; month < months; month++) {
      cents = _applyRate(cents, ratePerMillion) + monthlyContribution.cents;
    }
    return Money(cents);
  }

  int? monthsToTarget({
    required Money present,
    required Money monthlyContribution,
    required int ratePerMillion,
    required Money target,
  }) {
    if (present.cents >= target.cents) return 0;
    var cents = present.cents;
    for (var month = 1; month <= maxMonths; month++) {
      cents = _applyRate(cents, ratePerMillion) + monthlyContribution.cents;
      if (cents >= target.cents) return month;
    }
    return null;
  }

  Money requiredMonthlySavings({
    required Money present,
    required int ratePerMillion,
    required int months,
    required Money target,
  }) {
    if (months <= 0) return Money.zero;
    if (present.cents >= target.cents) return Money.zero;
    var low = 0;
    var high = target.cents - present.cents;
    while (
      futureValue(
            present: present,
            monthlyContribution: Money(high),
            ratePerMillion: ratePerMillion,
            months: months,
          ).cents <
          target.cents
    ) {
      high *= 2;
      if (high > 1 << 52) break;
    }
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final reached = futureValue(
        present: present,
        monthlyContribution: Money(mid),
        ratePerMillion: ratePerMillion,
        months: months,
      );
      if (reached.cents >= target.cents) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return Money(low);
  }

  int _applyRate(int cents, int ratePerMillion) {
    if (ratePerMillion == 0 || cents == 0) return cents;
    final interest = _roundDiv(cents * ratePerMillion, 1000000);
    return cents + interest;
  }

  int _roundDiv(int numerator, int denominator) {
    if (numerator >= 0) {
      return (numerator + denominator ~/ 2) ~/ denominator;
    }
    return -(((-numerator) + denominator ~/ 2) ~/ denominator);
  }
}
