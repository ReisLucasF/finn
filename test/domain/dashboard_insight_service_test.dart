import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/services/dashboard_insight_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = DashboardInsightService();

  DashboardSummary summary({
    Money? income,
    Money? expenses,
    Money? savings,
    double savingsRate = 0,
    double investmentRate = 0,
    EmergencyOverview? emergency,
    List<FlowMonth> months = const [],
    List<CategorySlice> expenseByCategory = const [],
  }) {
    final resolvedIncome = income ?? Money.zero;
    final resolvedExpenses = expenses ?? Money.zero;
    return DashboardSummary(
      netWorth: const Money(100000),
      totalAccounts: const Money(80000),
      totalInvestments: const Money(20000),
      creditCardDebt: Money.zero,
      monthlyIncome: resolvedIncome,
      monthlyExpenses: resolvedExpenses,
      monthlySavings: savings ?? Money(resolvedIncome.cents - resolvedExpenses.cents),
      savingsRate: savingsRate,
      investmentRate: investmentRate,
      emergencyRunway: emergency?.runwayMonths ?? 0,
      emergency: emergency ??
          const EmergencyOverview(
            reserve: Money(100000),
            averageEssential: Money(10000),
            targetMonths: 6,
            targetAmount: Money(60000),
            runwayMonths: 10,
          ),
      projectedBalance: const Money(80000),
      investmentGain: Money.zero,
      periodStart: const LocalDate(2026, 10, 1),
      periodEndExclusive: const LocalDate(2026, 11, 1),
      charts: DashboardCharts(
        months: months,
        incomeByCategory: const [],
        expenseByCategory: expenseByCategory,
        netWorth: const [
          MoneyPoint(date: LocalDate(2026, 10, 1), amount: Money(100000)),
        ],
        investments: const [
          InvestmentPoint(
            date: LocalDate(2026, 10, 1),
            invested: Money(20000),
            current: Money(20000),
          ),
        ],
      ),
    );
  }

  test('alerta quando a reserva está abaixo da meta', () {
    final insights = service.build(
      summary: summary(
        income: const Money(500000),
        expenses: const Money(400000),
        savingsRate: 0.2,
        emergency: const EmergencyOverview(
          reserve: Money(20000),
          averageEssential: Money(10000),
          targetMonths: 6,
          targetAmount: Money(60000),
          runwayMonths: 2,
        ),
      ),
      activeGoals: 1,
      goalsOnTrack: 1,
    );
    expect(
      insights.any((item) => item.title == 'Reserva abaixo da meta'),
      isTrue,
    );
  });

  test('sugere criar meta quando não há nenhuma ativa', () {
    final insights = service.build(
      summary: summary(
        income: const Money(500000),
        expenses: const Money(300000),
        savingsRate: 0.4,
      ),
      activeGoals: 0,
      goalsOnTrack: 0,
    );
    expect(
      insights.any((item) => item.title == 'Nenhuma meta ativa'),
      isTrue,
    );
  });
}
