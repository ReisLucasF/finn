import 'package:finan/app/dependency_injection.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_graph.dart';

class _NoNetwork implements MarketDataGateway {
  @override
  Future<List<(LocalDate, double)>> daily(int s, LocalDate f, LocalDate t) =>
      Future.value(const []);

  @override
  Future<List<(LocalDate, double)>> latest(int s, int c) =>
      Future.value([(const LocalDate(2026, 10, 19), 13.65)]);
}

void main() {
  Future<({AppGraph graph, String userId, String accountId, String id})>
  setup() async {
    final graph = await openTestGraph(
      today: const LocalDate(2026, 10, 20),
      marketGateway: _NoNetwork(),
    );
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Inter',
      type: AccountType.checking,
      initialBalance: const Money(1000000),
    );
    final investment = await graph.createInvestment(
      userId: user.id,
      name: 'CDB Inter',
      kind: InvestmentKind.fixedIncome,
      accountId: account.id,
    );
    expect(investment.accountId, account.id);
    // Aportes e resgates do seu histórico: posição final R$ 539,58.
    for (final (type, cents, date) in [
      (InvestmentMovementType.contribution, 335162, LocalDate(2026, 7, 17)),
      (InvestmentMovementType.contribution, 1936, LocalDate(2026, 7, 21)),
      (InvestmentMovementType.withdrawal, 130394, LocalDate(2026, 8, 20)),
      (InvestmentMovementType.withdrawal, 1962, LocalDate(2026, 9, 4)),
      (InvestmentMovementType.withdrawal, 150784, LocalDate(2026, 9, 15)),
    ]) {
      await graph.moveInvestment(
        userId: user.id,
        investmentId: investment.id,
        movement: type,
        amount: Money(cents),
        date: date,
        accountId: account.id,
      );
    }
    final current = await graph.finance.findInvestment(investment.id);
    expect(current!.currentValue, const Money(53958));
    return (
      graph: graph,
      userId: user.id,
      accountId: account.id,
      id: investment.id,
    );
  }

  test('resgatar tudo zera a posição e registra o rendimento real', () async {
    final s = await setup();
    final graph = s.graph;
    await graph.saveInvestmentYield(
      investmentId: s.id,
      indexer: YieldIndexer.cdiPercent,
      rate: 100,
      taxRegime: TaxRegime.regressive,
    );
    final before = await graph.calculateAccountBalance(s.accountId);

    final adjustment = await graph.redeemInvestment(
      userId: s.userId,
      investmentId: s.id,
      received: const Money(58175),
      date: const LocalDate(2026, 10, 20),
      accountId: s.accountId,
    );
    expect(adjustment, const Money(4217));

    final investment = await graph.finance.findInvestment(s.id);
    expect(investment!.currentValue, Money.zero);
    expect(
      await graph.calculateAccountBalance(s.accountId),
      Money(before.cents + 58175),
    );

    final overview = await graph.getInvestmentEstimates(s.userId);
    // Rendimento real do ciclo: resgatado − aportado.
    expect(overview.realized[s.id], const Money(4217));
    // Indexado zerado: nada mais rende até um novo aporte.
    expect(overview.estimates[s.id]?.principal ?? Money.zero, Money.zero);

    final summary = await graph.getDashboardSummary(s.userId);
    expect(summary.totalInvestments, Money.zero);
    expect(summary.investmentYield!.realizedGain, const Money(4217));
  });

  test('resgate total abaixo da posição registra perda', () async {
    final s = await setup();
    final graph = s.graph;
    final adjustment = await graph.redeemInvestment(
      userId: s.userId,
      investmentId: s.id,
      received: const Money(50000),
      date: const LocalDate(2026, 10, 20),
      accountId: s.accountId,
    );
    expect(adjustment, const Money(-3958));
    final investment = await graph.finance.findInvestment(s.id);
    expect(investment!.currentValue, Money.zero);
    final overview = await graph.getInvestmentEstimates(s.userId);
    expect(overview.realized[s.id], const Money(-3958));
  });
}
