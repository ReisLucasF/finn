import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/domain/services/dashboard_chart_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const charts = DashboardChartService();

  test('gráficos separam patrimônio, fluxo e capital investido', () {
    final result = charts.build(
      today: const LocalDate(2026, 10, 6),
      monthStartDay: 1,
      accounts: const [
        OpeningBalance(
          id: 'conta',
          initial: Money(10000),
          openedOn: LocalDate(2026, 9, 1),
        ),
      ],
      accountMovements: const [
        DailyAccountTotal(
          accountId: 'conta',
          date: LocalDate(2026, 9, 15),
          amount: Money(-2000),
        ),
        DailyAccountTotal(
          accountId: 'conta',
          date: LocalDate(2026, 10, 6),
          amount: Money(5000),
        ),
      ],
      cards: const [
        OpeningBalance(
          id: 'cartao',
          initial: Money(0),
          openedOn: LocalDate(2026, 10, 1),
        ),
      ],
      cardMovements: const [
        DailyAccountTotal(
          accountId: 'cartao',
          date: LocalDate(2026, 10, 2),
          amount: Money(3000),
        ),
      ],
      investmentMovements: const [
        DatedInvestmentMovement(
          date: LocalDate(2026, 8, 10),
          type: InvestmentMovementType.contribution,
          amount: Money(1000),
        ),
        DatedInvestmentMovement(
          date: LocalDate(2026, 10, 1),
          type: InvestmentMovementType.income,
          amount: Money(200),
        ),
      ],
      cashEvents: const [
        InvestmentCashEvent(
          description: 'CDB',
          type: TransactionType.investmentContribution,
          amount: Money(4000),
          date: LocalDate(2026, 9, 20),
        ),
      ],
      flows: const [
        DatedFlow(
          date: LocalDate(2026, 9, 15),
          type: TransactionType.expense,
          amount: Money(2000),
        ),
        DatedFlow(
          date: LocalDate(2026, 10, 2),
          type: TransactionType.expense,
          amount: Money(3000),
        ),
        DatedFlow(
          date: LocalDate(2026, 10, 6),
          type: TransactionType.income,
          amount: Money(5000),
        ),
      ],
      incomeCategories: const [
        CategoryAmount(label: 'Salário', amount: Money(5000)),
      ],
      expenseCategories: const [
        CategoryAmount(label: 'Moradia', amount: Money(3000)),
      ],
    );

    expect(result.months, hasLength(6));
    expect(result.months.last.income, const Money(5000));
    expect(result.months.last.expense, const Money(3000));
    expect(result.months[4].expense, const Money(2000));
    expect(result.netWorth[3].amount, const Money(1000));
    expect(result.netWorth[4].amount, const Money(13000));
    expect(result.netWorth.last.amount, const Money(15200));
    expect(result.investments[4].invested, const Money(5000));
    expect(result.investments[4].current, const Money(5000));
    expect(result.investments.last.invested, const Money(5000));
    expect(result.investments.last.current, const Money(5200));
    expect(result.incomeByCategory.single.label, 'Salário');
  });
}
