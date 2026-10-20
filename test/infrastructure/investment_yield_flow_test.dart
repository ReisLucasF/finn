import 'dart:math' as math;

import 'package:finan/core/date/business_calendar.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_graph.dart';

/// BCB falso: CDI de 0,05% em todo dia útil; registra as chamadas.
class _FakeBcb implements MarketDataGateway {
  final dailyCalls = <(LocalDate, LocalDate)>[];
  var latestCalls = 0;

  @override
  Future<List<(LocalDate, double)>> daily(
    int series,
    LocalDate from,
    LocalDate to,
  ) async {
    dailyCalls.add((from, to));
    const calendar = BusinessCalendar();
    return [
      for (var d = from; d <= to; d = d.addDays(1))
        if (calendar.isBusinessDay(d)) (d, 0.05),
    ];
  }

  @override
  Future<List<(LocalDate, double)>> latest(int series, int count) async {
    latestCalls++;
    return series == MarketDataRepository.cdiAnnual
        ? [(const LocalDate(2026, 10, 30), 13.65)]
        : [(const LocalDate(2026, 10, 1), 0.61)];
  }
}

void main() {
  test(
    'sincroniza o CDI, estima com impostos e reflete na dashboard',
    () async {
      final bcb = _FakeBcb();
      final graph = await openTestGraph(
        today: const LocalDate(2026, 11, 3),
        marketGateway: bcb,
      );
      final user = await graph.bootstrap();
      final account = await graph.createAccount(
        userId: user.id,
        name: 'Corrente',
        type: AccountType.checking,
        initialBalance: const Money(10000000),
      );
      final investment = await graph.createInvestment(
        userId: user.id,
        name: 'CDB 110%',
        kind: InvestmentKind.fixedIncome,
      );
      await graph.moveInvestment(
        userId: user.id,
        investmentId: investment.id,
        movement: InvestmentMovementType.contribution,
        amount: const Money(1000000),
        date: const LocalDate(2026, 10, 1),
        accountId: account.id,
      );

      var summary = await graph.getDashboardSummary(user.id);
      expect(summary.totalInvestments, const Money(1000000));
      expect(summary.investmentYield, isNull);

      await graph.saveInvestmentYield(
        investmentId: investment.id,
        indexer: YieldIndexer.cdiPercent,
        rate: 110,
        taxRegime: TaxRegime.regressive,
      );
      expect(await graph.syncMarketData(user.id), isTrue);
      expect(bcb.dailyCalls.single, (
        const LocalDate(2026, 10, 1),
        const LocalDate(2026, 11, 2),
      ));

      final overview = await graph.getInvestmentEstimates(user.id);
      final estimate = overview.estimates[investment.id]!;
      // Dias úteis de 1/10 a 2/11 (exclui 12/10 e 2/11): 21.
      expect(estimate.businessDays, 21);
      final gross = 1000000 * math.pow(1 + 0.0005 * 1.1, 21);
      expect(estimate.gross.cents, gross.round());
      // 33 dias corridos: sem IOF, IR de 22,5%.
      expect(estimate.iof, Money.zero);
      expect(estimate.incomeTax.cents, closeTo((gross - 1000000) * 0.225, 1));
      expect(overview.cdi.annualPercent, 13.65);

      summary = await graph.getDashboardSummary(user.id);
      expect(summary.totalInvestments, estimate.net);
      expect(summary.investmentYield!.netGain, estimate.netGain);

      // Cache em dia: nova sincronização não chama a série diária.
      expect(await graph.syncMarketData(user.id), isFalse);
      expect(bcb.dailyCalls, hasLength(1));

      // Sem indexador volta ao valor das movimentações.
      await graph.removeInvestmentYield(investment.id);
      summary = await graph.getDashboardSummary(user.id);
      expect(summary.totalInvestments, const Money(1000000));
    },
  );

  test('valida a taxa do indexador', () async {
    final graph = await openTestGraph(marketGateway: _FakeBcb());
    final user = await graph.bootstrap();
    final investment = await graph.createInvestment(
      userId: user.id,
      name: 'CDB',
      kind: InvestmentKind.fixedIncome,
    );
    await expectLater(
      graph.saveInvestmentYield(
        investmentId: investment.id,
        indexer: YieldIndexer.cdiPercent,
        rate: 0,
        taxRegime: TaxRegime.regressive,
      ),
      throwsA(isA<ValidationException>()),
    );
  });
}
