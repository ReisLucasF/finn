import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/services/card_limit_service.dart';
import 'package:finan/domain/services/emergency_fund_service.dart';
import 'package:finan/domain/services/goal_projection_service.dart';
import 'package:finan/domain/services/investment_position_service.dart';
import 'package:finan/domain/services/investment_rate_service.dart';
import 'package:finan/domain/services/net_worth_service.dart';
import 'package:finan/domain/services/projected_balance_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('patrimônio soma contas e investimentos e desconta o cartão', () {
    const service = NetWorthService();
    expect(
      service.calculate(
        accounts: const Money(100000),
        investments: const Money(40000),
        cardDebt: const Money(5000),
      ),
      const Money(135000),
    );
  });

  test('disponível do cartão não passa do limite', () {
    const service = CardLimitService();
    final used = service.used(
      initialUsed: const Money(1000),
      confirmedEntries: const Money(4000),
    );
    expect(used, const Money(5000));
    expect(
      service.available(limit: const Money(10000), used: used),
      const Money(5000),
    );
    expect(
      service.available(limit: const Money(10000), used: const Money(-100)),
      const Money(10000),
    );
  });

  test('provisão muda o saldo projetado e não o saldo real', () {
    const service = ProjectedBalanceService();
    expect(
      service.project(
        currentBalance: const Money(10000),
        provisionedIncome: const Money(2000),
        provisionedExpenses: const Money(500),
      ),
      const Money(11500),
    );
  });

  test('aporte e rendimento compõem a posição sem virar receita', () {
    const service = InvestmentPositionService();
    final value = service.valueOf(const [
      (type: InvestmentMovementType.contribution, amount: Money(1000000)),
      (type: InvestmentMovementType.income, amount: Money(200000)),
      (type: InvestmentMovementType.withdrawal, amount: Money(1200000)),
    ]);
    expect(value, Money.zero);
    expect(
      const InvestmentRateService().rate(
        contributions: const Money(1000000),
        income: const Money(500000),
      ),
      closeTo(2, 0.0001),
    );
  });

  test('reserva é a despesa média vezes os meses', () {
    const service = EmergencyFundService();
    final average = service.averageMonthly(const [
      Money(500000),
      Money(700000),
      Money(600000),
    ]);
    expect(average, const Money(600000));
    expect(
      service.target(averageEssentialExpenses: average, months: 6),
      const Money(3600000),
    );
    expect(
      service.runway(reserve: const Money(2400000), averageEssentialExpenses: average),
      closeTo(4, 0.0001),
    );
  });

  test('reserva usa categorias salvas e ignora lazer no padrão', () {
    const service = EmergencyFundService();
    expect(
      service.resolveEssentialCategoryIds(saved: const ['cat-a', 'cat-b']),
      ['cat-a', 'cat-b'],
    );
    final defaults = service.resolveEssentialCategoryIds(saved: null);
    expect(defaults, contains('019a0000-0000-7000-8000-000000000007'));
    expect(defaults, isNot(contains('019a0000-0000-7000-8000-00000000000c')));
    expect(defaults, isNot(contains('019a0000-0000-7000-8000-00000000000e')));
  });

  test('projeção sem juros é patrimônio mais aportes', () {
    const service = GoalProjectionService();
    expect(
      service.futureValue(
        present: const Money(100000),
        monthlyContribution: const Money(10000),
        ratePerMillion: 0,
        months: 12,
      ),
      const Money(220000),
    );
    expect(
      service.monthsToTarget(
        present: const Money(100000),
        monthlyContribution: const Money(10000),
        ratePerMillion: 0,
        target: const Money(220000),
      ),
      12,
    );
    expect(
      service.requiredMonthlySavings(
        present: const Money(100000),
        ratePerMillion: 0,
        months: 12,
        target: const Money(220000),
      ),
      const Money(10000),
    );
  });
}
