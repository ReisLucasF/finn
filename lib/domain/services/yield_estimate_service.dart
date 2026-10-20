import 'dart:math' as math;

import 'package:finan/core/date/business_calendar.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/services/investment_tax_service.dart';

/// Estima o valor de renda fixa indexada (CDI ou prefixada), com IR e IOF
/// regressivos por lote de aporte.
///
/// Convenções (aproximação do que os bancos fazem):
/// - a taxa do dia útil `d` rende de `d` para o dia útil seguinte; o aporte
///   rende a partir do próprio dia e o valor é apurado no início de [asOf];
/// - dias úteis são os publicados pelo BCB; depois da última publicação,
///   usa o calendário de feriados nacionais e o CDI anualizado (série 4389);
/// - resgates e taxas saem dos lotes mais antigos primeiro (FIFO), pelo
///   valor bruto; resgate sem lote para cobrir (histórico incompleto) é
///   descontado dos aportes seguintes;
/// - rendimentos e perdas lançados à mão são ignorados, já que o rendimento
///   é calculado.
class YieldEstimateService {
  const YieldEstimateService({
    this.calendar = const BusinessCalendar(),
    this.taxes = const InvestmentTaxService(),
  });

  final BusinessCalendar calendar;
  final InvestmentTaxService taxes;

  /// Nulo quando não há aporte ou faltam dados do CDI para estimar.
  InvestmentEstimate? estimate({
    required InvestmentYield config,
    required List<DatedInvestmentMovement> movements,
    required CdiSnapshot cdi,
    required LocalDate asOf,
  }) {
    final sorted = [...movements]
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        // No mesmo dia, aporte antes de resgate.
        return _order(a.type).compareTo(_order(b.type));
      });
    final firstContribution = sorted
        .where((m) => m.type == InvestmentMovementType.contribution)
        .map((m) => m.date)
        .fold<LocalDate?>(null, (min, d) => min == null || d < min ? d : min);
    if (firstContribution == null || firstContribution > asOf) return null;

    final usesCdi = config.indexer != YieldIndexer.prefixed;
    if (usesCdi && !cdi.hasData) return null;

    final lastPublished = cdi.lastDailyDate;
    final firstPublished = cdi.daily.isEmpty
        ? null
        : cdi.daily.keys.reduce((a, b) => a < b ? a : b);
    final fallbackDaily = cdi.annualPercent == null
        ? null
        : math.pow(1 + cdi.annualPercent! / 100, 1 / 252) - 1;

    // Índices acumulados no início de cada data relevante.
    final checkpoints = <LocalDate>{for (final m in sorted) m.date, asOf};
    final index = <LocalDate, double>{};
    final cdiIndex = <LocalDate, double>{};
    var acc = 1.0;
    var cdiAcc = 1.0;
    var businessDays = 0;
    var projectedDays = 0;
    for (var day = firstContribution; day <= asOf; day = day.addDays(1)) {
      if (checkpoints.contains(day)) {
        index[day] = acc;
        cdiIndex[day] = cdiAcc;
      }
      if (day == asOf) break;
      final published = cdi.daily[day];
      double? cdiRate;
      if (published != null) {
        cdiRate = published / 100;
      } else {
        // Sem publicação: feriado (dentro da série) ou dado ainda não saiu.
        final insideSeries =
            firstPublished != null &&
            lastPublished != null &&
            day >= firstPublished &&
            day <= lastPublished;
        if (insideSeries || !calendar.isBusinessDay(day)) continue;
        if (usesCdi && fallbackDaily == null) return null;
        cdiRate = fallbackDaily?.toDouble() ?? 0;
        projectedDays++;
      }
      businessDays++;
      cdiAcc *= 1 + cdiRate;
      acc *= _factor(config, cdiRate);
    }

    final lots = <_Lot>[];
    var ignoredIncome = 0;
    // Resgate sem lote para cobrir (histórico incompleto): desconta dos
    // próximos aportes, para o capital bater com as movimentações.
    var pendingDebit = 0.0;
    // Posição pelas movimentações: quando zera (resgate total), todos os
    // lotes foram resgatados e o ciclo recomeça no próximo aporte.
    var balance = 0;
    for (final movement in sorted) {
      if (movement.date > asOf) continue;
      balance += _signed(movement);
      if (movement.date >= firstContribution && balance <= 0) {
        lots.clear();
        pendingDebit = 0;
        continue;
      }
      if (movement.date < firstContribution) {
        if (movement.type == InvestmentMovementType.withdrawal ||
            movement.type == InvestmentMovementType.fee) {
          pendingDebit += movement.amount.cents;
        }
        continue;
      }
      final at = index[movement.date]!;
      final cdiAt = cdiIndex[movement.date]!;
      switch (movement.type) {
        case InvestmentMovementType.contribution:
          final covered = math.min(pendingDebit, movement.amount.cents * 1.0);
          pendingDebit -= covered;
          final amount = movement.amount.cents - covered;
          if (amount <= 0) break;
          lots.add(
            _Lot(
              date: movement.date,
              principal: amount,
              units: amount / at,
              cdiUnits: amount / cdiAt,
            ),
          );
        case InvestmentMovementType.withdrawal || InvestmentMovementType.fee:
          var remaining = movement.amount.cents.toDouble();
          while (remaining > 0.0001 && lots.isNotEmpty) {
            final lot = lots.first;
            final value = lot.units * at;
            if (value <= remaining) {
              remaining -= value;
              lots.removeAt(0);
            } else {
              final keep = 1 - remaining / value;
              lot.units *= keep;
              lot.cdiUnits *= keep;
              lot.principal *= keep;
              remaining = 0;
            }
          }
          pendingDebit += remaining > 0.0001 ? remaining : 0;
        case InvestmentMovementType.income:
          ignoredIncome += movement.amount.cents;
        case InvestmentMovementType.loss:
          break;
      }
    }

    final finalIndex = index[asOf]!;
    final finalCdi = cdiIndex[asOf]!;
    var principal = 0.0;
    var gross = 0.0;
    var cdiGross = 0.0;
    var iof = 0.0;
    var incomeTax = 0.0;
    for (final lot in lots) {
      final value = lot.units * finalIndex;
      principal += lot.principal;
      gross += value;
      cdiGross += lot.cdiUnits * finalCdi;
      final gain = value - lot.principal;
      if (config.taxRegime == TaxRegime.exempt || gain <= 0) continue;
      final days = BusinessCalendar.calendarDays(lot.date, asOf);
      final lotIof = gain * taxes.iofRate(days);
      iof += lotIof;
      incomeTax += (gain - lotIof) * taxes.incomeTaxRate(days);
    }

    return InvestmentEstimate(
      investmentId: config.investmentId,
      asOf: asOf,
      principal: Money(principal.round()),
      gross: Money(gross.round()),
      iof: Money(iof.round()),
      incomeTax: Money(incomeTax.round()),
      businessDays: businessDays,
      calendarDays: BusinessCalendar.calendarDays(firstContribution, asOf),
      // Mesmos aportes, nas mesmas datas, a 100% do CDI.
      cdiPeriodReturn: principal <= 0 ? 0 : cdiGross / principal - 1,
      projectedDays: projectedDays,
      ignoredIncome: Money(ignoredIncome),
    );
  }

  /// Fator de um dia útil para o indexador.
  double _factor(InvestmentYield config, double cdiDaily) {
    return switch (config.indexer) {
      YieldIndexer.cdiPercent => 1 + cdiDaily * config.rate / 100,
      YieldIndexer.cdiPlus =>
        (1 + cdiDaily) * math.pow(1 + config.rate / 100, 1 / 252),
      YieldIndexer.prefixed =>
        math.pow(1 + config.rate / 100, 1 / 252).toDouble(),
    };
  }

  static int _signed(DatedInvestmentMovement movement) =>
      switch (movement.type) {
        InvestmentMovementType.contribution ||
        InvestmentMovementType.income => movement.amount.cents,
        InvestmentMovementType.withdrawal ||
        InvestmentMovementType.loss ||
        InvestmentMovementType.fee => -movement.amount.cents,
      };

  /// Rendimento real de ciclos encerrados (posição zerada por resgate):
  /// total resgatado menos total aportado em cada ciclo.
  Money realizedGain(List<DatedInvestmentMovement> movements) {
    final sorted = [...movements]
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : _order(a.type).compareTo(_order(b.type));
      });
    var realized = 0;
    var balance = 0;
    var contributed = 0;
    var withdrawn = 0;
    for (final movement in sorted) {
      balance += _signed(movement);
      switch (movement.type) {
        case InvestmentMovementType.contribution:
          contributed += movement.amount.cents;
        case InvestmentMovementType.withdrawal:
          withdrawn += movement.amount.cents;
        default:
          break;
      }
      if (balance <= 0) {
        if (contributed > 0) realized += withdrawn - contributed;
        balance = 0;
        contributed = 0;
        withdrawn = 0;
      }
    }
    return Money(realized);
  }

  static int _order(InvestmentMovementType type) => switch (type) {
    InvestmentMovementType.contribution => 0,
    InvestmentMovementType.income => 1,
    InvestmentMovementType.withdrawal => 2,
    InvestmentMovementType.loss || InvestmentMovementType.fee => 3,
  };
}

class _Lot {
  _Lot({
    required this.date,
    required this.principal,
    required this.units,
    required this.cdiUnits,
  });

  final LocalDate date;
  double principal;

  /// Cotas: valor do lote = cotas × índice acumulado.
  double units;

  /// Cotas do mesmo lote se rendesse 100% do CDI (referência).
  double cdiUnits;
}
