import 'package:finan/domain/entities/dashboard_summary.dart';

enum FinancialHealthLevel { excellent, good, attention, critical }

class FinancialHealthPillar {
  const FinancialHealthPillar({
    required this.label,
    required this.points,
    required this.maxPoints,
  });

  final String label;
  final double points;
  final double maxPoints;

  double get ratio => maxPoints <= 0 ? 0 : points / maxPoints;
}

class FinancialHealth {
  const FinancialHealth({required this.pillars});

  final List<FinancialHealthPillar> pillars;

  int get score =>
      pillars.fold<double>(0, (sum, pillar) => sum + pillar.points).round();

  FinancialHealthLevel get level {
    final value = score;
    if (value >= 80) return FinancialHealthLevel.excellent;
    if (value >= 60) return FinancialHealthLevel.good;
    if (value >= 40) return FinancialHealthLevel.attention;
    return FinancialHealthLevel.critical;
  }

  String get label => switch (level) {
    FinancialHealthLevel.excellent => 'Excelente',
    FinancialHealthLevel.good => 'Boa',
    FinancialHealthLevel.attention => 'Atenção',
    FinancialHealthLevel.critical => 'Crítica',
  };
}

/// Pontuação 0–100 a partir de quatro pilares:
/// economia (30), reserva (30), aportes (20) e endividamento do cartão (20).
class FinancialHealthService {
  const FinancialHealthService();

  static const savingsTarget = 0.2;
  static const investmentTarget = 0.1;

  FinancialHealth evaluate(DashboardSummary summary) {
    final savings = _ratio(summary.savingsRate, savingsTarget) * 30;
    final reserve = summary.emergency.averageEssential.cents <= 0
        ? 0.0
        : summary.emergency.coverage.clamp(0.0, 1.0) * 30;
    final investing = _ratio(summary.investmentRate, investmentTarget) * 20;
    return FinancialHealth(
      pillars: [
        FinancialHealthPillar(
          label: 'Economia',
          points: savings,
          maxPoints: 30,
        ),
        FinancialHealthPillar(label: 'Reserva', points: reserve, maxPoints: 30),
        FinancialHealthPillar(
          label: 'Aportes',
          points: investing,
          maxPoints: 20,
        ),
        FinancialHealthPillar(
          label: 'Dívidas',
          points: _debtPoints(summary),
          maxPoints: 20,
        ),
      ],
    );
  }

  double _ratio(double value, double target) =>
      (value / target).clamp(0.0, 1.0);

  /// Fatura até 30% da renda mensal média = nota cheia; 100% ou mais = zero.
  double _debtPoints(DashboardSummary summary) {
    final debt = summary.creditCardDebt.cents.abs();
    if (debt == 0) return 20;
    final months = summary.charts.months;
    var income = 0;
    for (final month in months) {
      income += month.income.cents;
    }
    final monthly = months.isEmpty
        ? summary.monthlyIncome.cents
        : income ~/ months.length;
    if (monthly <= 0) return 0;
    final share = debt / monthly;
    if (share <= 0.3) return 20;
    if (share >= 1) return 0;
    return 20 * (1 - (share - 0.3) / 0.7);
  }
}
