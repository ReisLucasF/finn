import 'package:finan/core/date/business_calendar.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:finan/domain/services/yield_estimate_service.dart';

/// Estimativas de todos os investimentos com indexador configurado.
class InvestmentYieldOverview {
  const InvestmentYieldOverview({
    required this.configs,
    required this.estimates,
    required this.cdi,
    this.realized = const {},
  });

  static const empty = InvestmentYieldOverview(
    configs: {},
    estimates: {},
    cdi: CdiSnapshot.empty,
  );

  final Map<String, InvestmentYield> configs;
  final Map<String, InvestmentEstimate> estimates;
  final CdiSnapshot cdi;

  /// Rendimento real de ciclos encerrados por resgate total, por investimento.
  final Map<String, Money> realized;

  Money get realizedTotal =>
      realized.values.fold(Money.zero, (sum, item) => sum + item);

  Money _sum(Money Function(InvestmentEstimate) pick) =>
      estimates.values.fold(Money.zero, (sum, item) => sum + pick(item));

  Money get principal => _sum((item) => item.principal);
  Money get gross => _sum((item) => item.gross);
  Money get taxes => _sum((item) => item.taxes);
  Money get net => _sum((item) => item.net);
  Money get grossGain => _sum((item) => item.grossGain);
  Money get netGain => _sum((item) => item.netGain);
}

class GetInvestmentEstimates {
  const GetInvestmentEstimates({
    required InvestmentYieldRepository yields,
    required FinanceRepository finance,
    required MarketDataRepository market,
    required Clock clock,
    YieldEstimateService service = const YieldEstimateService(),
  }) : _yields = yields,
       _finance = finance,
       _market = market,
       _clock = clock,
       _service = service;

  final InvestmentYieldRepository _yields;
  final FinanceRepository _finance;
  final MarketDataRepository _market;
  final Clock _clock;
  final YieldEstimateService _service;

  Future<InvestmentYieldOverview> call(String userId) async {
    final configs = await _yields.listByUser(userId);
    final annual = await _market.latest(MarketDataRepository.cdiAnnual);
    final monthly = await _market.latest(MarketDataRepository.cdiMonthly);
    final movements = await _finance.movementsByInvestment(userId);
    final realized = <String, Money>{
      for (final entry in movements.entries)
        entry.key: _service.realizedGain(entry.value),
    }..removeWhere((_, value) => value.isZero);
    if (configs.isEmpty) {
      return InvestmentYieldOverview(
        configs: const {},
        estimates: const {},
        realized: realized,
        cdi: CdiSnapshot(
          daily: const {},
          annualPercent: annual?.$2,
          annualDate: annual?.$1,
          monthlyPercent: monthly?.$2,
          monthlyDate: monthly?.$1,
        ),
      );
    }
    final start = earliestContribution({
      for (final config in configs)
        config.investmentId: movements[config.investmentId] ?? const [],
    });
    final cdi = CdiSnapshot(
      daily: start == null
          ? const {}
          : await _market.values(MarketDataRepository.cdiDaily, from: start),
      annualPercent: annual?.$2,
      annualDate: annual?.$1,
      monthlyPercent: monthly?.$2,
      monthlyDate: monthly?.$1,
    );
    final today = _clock.today();
    final estimates = <String, InvestmentEstimate>{};
    for (final config in configs) {
      final estimate = _service.estimate(
        config: config,
        movements: movements[config.investmentId] ?? const [],
        cdi: cdi,
        asOf: today,
      );
      if (estimate != null) estimates[config.investmentId] = estimate;
    }
    return InvestmentYieldOverview(
      configs: {for (final config in configs) config.investmentId: config},
      estimates: estimates,
      realized: realized,
      cdi: cdi,
    );
  }

  static LocalDate? earliestContribution(
    Map<String, List<DatedInvestmentMovement>> movementsById,
  ) {
    LocalDate? first;
    for (final list in movementsById.values) {
      for (final movement in list) {
        if (movement.type != InvestmentMovementType.contribution) continue;
        if (first == null || movement.date < first) first = movement.date;
      }
    }
    return first;
  }

  /// Resumo para a dashboard.
  static YieldSummary? summarize(InvestmentYieldOverview overview) {
    final open = [
      for (final item in overview.estimates.values)
        if (item.principal.cents > 0) item,
    ];
    if (open.isEmpty && overview.realized.isEmpty) return null;
    return YieldSummary(
      count: open.length,
      principal: overview.principal,
      gross: overview.gross,
      taxes: overview.taxes,
      realizedGain: overview.realizedTotal,
      cdiAnnualPercent: overview.cdi.annualPercent,
    );
  }
}

/// Atualiza o cache do CDI a partir do Banco Central, só no que falta.
class SyncMarketData {
  const SyncMarketData({
    required MarketDataGateway gateway,
    required MarketDataRepository market,
    required InvestmentYieldRepository yields,
    required FinanceRepository finance,
    required Clock clock,
    BusinessCalendar calendar = const BusinessCalendar(),
  }) : _gateway = gateway,
       _market = market,
       _yields = yields,
       _finance = finance,
       _clock = clock,
       _calendar = calendar;

  final MarketDataGateway _gateway;
  final MarketDataRepository _market;
  final InvestmentYieldRepository _yields;
  final FinanceRepository _finance;
  final Clock _clock;
  final BusinessCalendar _calendar;

  /// Retorna `true` se algo novo foi gravado. Lança [AppException] sem rede.
  Future<bool> call(String userId) async {
    final today = _clock.today();
    final lastBusiness = _previousBusinessDay(today);
    var changed = false;

    // Indicadores de exibição: CDI anualizado e mensal.
    final annual = await _market.latest(MarketDataRepository.cdiAnnual);
    if (annual == null || annual.$1 < lastBusiness) {
      changed |= await _store(
        MarketDataRepository.cdiAnnual,
        await _gateway.latest(MarketDataRepository.cdiAnnual, 5),
      );
      changed |= await _store(
        MarketDataRepository.cdiMonthly,
        await _gateway.latest(MarketDataRepository.cdiMonthly, 13),
      );
    }

    // Série diária: só se houver investimento indexado.
    final configs = await _yields.listByUser(userId);
    if (configs.isEmpty) return changed;
    final movements = await _finance.movementsByInvestment(userId);
    final start = GetInvestmentEstimates.earliestContribution({
      for (final config in configs)
        config.investmentId: movements[config.investmentId] ?? const [],
    });
    if (start == null || start >= today) return changed;

    const series = MarketDataRepository.cdiDaily;
    final cachedFirst = await _market.earliest(series);
    final cachedLast = (await _market.latest(series))?.$1;
    final end = today.addDays(-1);
    if (cachedFirst == null || cachedLast == null) {
      changed |= await _store(series, await _gateway.daily(series, start, end));
      return changed;
    }
    if (start < cachedFirst) {
      changed |= await _store(
        series,
        await _gateway.daily(series, start, cachedFirst.addDays(-1)),
      );
    }
    if (cachedLast < lastBusiness) {
      changed |= await _store(
        series,
        await _gateway.daily(series, cachedLast.addDays(1), end),
      );
    }
    return changed;
  }

  Future<bool> _store(int series, List<(LocalDate, double)> values) async {
    if (values.isEmpty) return false;
    await _market.saveValues(series, values);
    return true;
  }

  /// Último dia útil antes de [date] (a taxa de hoje sai só amanhã).
  LocalDate _previousBusinessDay(LocalDate date) {
    var day = date.addDays(-1);
    while (!_calendar.isBusinessDay(day)) {
      day = day.addDays(-1);
    }
    return day;
  }
}

class SaveInvestmentYield {
  const SaveInvestmentYield({
    required InvestmentYieldRepository yields,
    required FinanceRepository finance,
    required Clock clock,
  }) : _yields = yields,
       _finance = finance,
       _clock = clock;

  final InvestmentYieldRepository _yields;
  final FinanceRepository _finance;
  final Clock _clock;

  Future<void> call({
    required String investmentId,
    required YieldIndexer indexer,
    required double rate,
    required TaxRegime taxRegime,
  }) async {
    final max = switch (indexer) {
      YieldIndexer.cdiPercent => 300.0,
      YieldIndexer.cdiPlus => 50.0,
      YieldIndexer.prefixed => 100.0,
    };
    if (rate.isNaN || rate <= 0 || rate > max) {
      throw ValidationException(
        'Informe uma taxa entre 0 e ${max.toStringAsFixed(0)}.',
      );
    }
    final investment = await _finance.findInvestment(investmentId);
    if (investment == null || investment.isDeleted) {
      throw const ValidationException('Investimento não encontrado.');
    }
    await _yields.save(
      InvestmentYield(
        investmentId: investmentId,
        indexer: indexer,
        rate: rate,
        taxRegime: taxRegime,
        updatedAt: _clock.nowUtc(),
      ),
    );
  }
}

class RemoveInvestmentYield {
  const RemoveInvestmentYield({required InvestmentYieldRepository yields})
    : _yields = yields;

  final InvestmentYieldRepository _yields;

  Future<void> call(String investmentId) => _yields.delete(investmentId);
}
