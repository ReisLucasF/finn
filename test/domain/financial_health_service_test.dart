import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/services/financial_health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = FinancialHealthService();

  DashboardSummary summary({
    double savingsRate = 0,
    double investmentRate = 0,
    Money cardDebt = Money.zero,
    Money monthlyIncome = const Money(500000),
    Money reserve = const Money(60000),
    Money essential = const Money(10000),
  }) {
    return DashboardSummary(
      netWorth: Money.zero,
      totalAccounts: Money.zero,
      totalInvestments: Money.zero,
      creditCardDebt: cardDebt,
      monthlyIncome: monthlyIncome,
      monthlyExpenses: Money.zero,
      monthlySavings: Money.zero,
      savingsRate: savingsRate,
      investmentRate: investmentRate,
      emergencyRunway: 0,
      emergency: EmergencyOverview(
        reserve: reserve,
        averageEssential: essential,
        targetMonths: 6,
        targetAmount: const Money(60000),
        runwayMonths: 6,
      ),
      projectedBalance: Money.zero,
      investmentGain: Money.zero,
      periodStart: const LocalDate(2026, 10, 1),
      periodEndExclusive: const LocalDate(2026, 11, 1),
      charts: DashboardCharts(
        months: [
          FlowMonth(
            start: const LocalDate(2026, 10, 1),
            income: monthlyIncome,
            expense: Money.zero,
          ),
        ],
        incomeByCategory: const [],
        expenseByCategory: const [],
        netWorth: const [],
        investments: const [],
      ),
    );
  }

  test('nota máxima quando todos os pilares batem a meta', () {
    final health = service.evaluate(
      summary(savingsRate: 0.25, investmentRate: 0.12),
    );
    expect(health.score, 100);
    expect(health.level, FinancialHealthLevel.excellent);
  });

  test('sem despesa essencial de referência a reserva não pontua', () {
    final health = service.evaluate(
      summary(savingsRate: 0.2, investmentRate: 0.1, essential: Money.zero),
    );
    expect(health.score, 70);
    expect(health.level, FinancialHealthLevel.good);
  });

  test('fatura do cartão acima da renda zera o pilar de dívidas', () {
    final health = service.evaluate(
      summary(cardDebt: const Money(600000), reserve: Money.zero),
    );
    expect(health.pillars.last.points, 0);
    expect(health.level, FinancialHealthLevel.critical);
  });

  test('fatura entre 30% e 100% da renda pontua proporcionalmente', () {
    final health = service.evaluate(summary(cardDebt: const Money(325000)));
    expect(health.pillars.last.points, closeTo(10, 0.01));
  });
}
