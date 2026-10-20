import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';

/// Como o investimento rende.
enum YieldIndexer {
  /// Percentual do CDI (ex.: 110% do CDI).
  cdiPercent('cdi_percent'),

  /// CDI mais uma taxa ao ano (ex.: CDI + 1,5% a.a.).
  cdiPlus('cdi_plus'),

  /// Taxa fixa ao ano, base 252 dias úteis (ex.: 12% a.a.).
  prefixed('prefixed');

  const YieldIndexer(this.value);

  final String value;

  static YieldIndexer fromValue(String value) =>
      YieldIndexer.values.firstWhere((item) => item.value == value);

  String get label => switch (this) {
    YieldIndexer.cdiPercent => '% do CDI',
    YieldIndexer.cdiPlus => 'CDI + taxa',
    YieldIndexer.prefixed => 'Prefixado',
  };
}

/// Tributação aplicada no resgate.
enum TaxRegime {
  /// IR regressivo (22,5% a 15%) e IOF regressivo nos primeiros 30 dias.
  regressive('regressive'),

  /// Isento de IR e IOF (LCI, LCA, CRI, CRA, debêntures incentivadas).
  exempt('exempt');

  const TaxRegime(this.value);

  final String value;

  static TaxRegime fromValue(String value) =>
      TaxRegime.values.firstWhere((item) => item.value == value);

  String get label => switch (this) {
    TaxRegime.regressive => 'Tributável (IR + IOF)',
    TaxRegime.exempt => 'Isento (LCI, LCA…)',
  };
}

/// Configuração de rentabilidade de um investimento.
class InvestmentYield {
  const InvestmentYield({
    required this.investmentId,
    required this.indexer,
    required this.rate,
    required this.taxRegime,
    required this.updatedAt,
  });

  final String investmentId;
  final YieldIndexer indexer;

  /// Em pontos percentuais: 110 = 110% do CDI; 1,5 = CDI + 1,5% a.a.;
  /// 12 = 12% a.a. prefixado.
  final double rate;
  final TaxRegime taxRegime;
  final DateTime updatedAt;

  String get label {
    final number = _number(rate);
    return switch (indexer) {
      YieldIndexer.cdiPercent => '$number% do CDI',
      YieldIndexer.cdiPlus => 'CDI + $number% a.a.',
      YieldIndexer.prefixed => '$number% a.a.',
    };
  }

  static String _number(double value) {
    final fixed = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
    return fixed.replaceAll('.', ',');
  }
}

/// Taxa diária do CDI publicada pelo BCB (série 12), em % ao dia.
class CdiDailyRate {
  const CdiDailyRate({required this.date, required this.percent});

  final LocalDate date;
  final double percent;
}

/// Indicadores mais recentes do CDI para exibição e projeção.
class CdiSnapshot {
  const CdiSnapshot({
    required this.daily,
    this.annualPercent,
    this.annualDate,
    this.monthlyPercent,
    this.monthlyDate,
  });

  /// Taxas diárias em cache, por data (dias úteis publicados).
  final Map<LocalDate, double> daily;

  /// CDI anualizado base 252 (série 4389), em % a.a.
  final double? annualPercent;
  final LocalDate? annualDate;

  /// CDI acumulado no mês (série 4391), em %.
  final double? monthlyPercent;
  final LocalDate? monthlyDate;

  static const empty = CdiSnapshot(daily: {});

  LocalDate? get lastDailyDate {
    LocalDate? last;
    for (final date in daily.keys) {
      if (last == null || date > last) last = date;
    }
    return last;
  }

  bool get hasData => daily.isNotEmpty || annualPercent != null;
}

/// Estimativa de valor, rendimento e impostos na data de referência.
class InvestmentEstimate {
  const InvestmentEstimate({
    required this.investmentId,
    required this.asOf,
    required this.principal,
    required this.gross,
    required this.iof,
    required this.incomeTax,
    required this.businessDays,
    required this.calendarDays,
    required this.cdiPeriodReturn,
    required this.projectedDays,
    required this.ignoredIncome,
  });

  final String investmentId;
  final LocalDate asOf;

  /// Capital aplicado ainda em aberto (após resgates).
  final Money principal;

  /// Valor bruto estimado.
  final Money gross;
  final Money iof;
  final Money incomeTax;

  /// Dias úteis com rendimento desde o primeiro aporte.
  final int businessDays;

  /// Dias corridos desde o primeiro aporte.
  final int calendarDays;

  /// Quanto os mesmos aportes, nas mesmas datas, teriam rendido a 100% do
  /// CDI, sobre o capital em aberto (fração; 0,05 = 5%).
  final double cdiPeriodReturn;

  /// Dias úteis estimados com a taxa anual porque o BCB ainda não publicou.
  final int projectedDays;

  /// Rendimentos lançados à mão, ignorados porque o cálculo é automático.
  final Money ignoredIncome;

  Money get grossGain => gross - principal;

  Money get taxes => iof + incomeTax;

  Money get net => gross - taxes;

  Money get netGain => net - principal;

  /// Rentabilidade bruta sobre o capital em aberto (fração).
  double get grossReturn =>
      principal.cents <= 0 ? 0 : grossGain.cents / principal.cents;

  /// Quanto do CDI o investimento rendeu no período (fração; 1,1 = 110%).
  double? get cdiShare =>
      cdiPeriodReturn <= 0 ? null : grossReturn / cdiPeriodReturn;
}

/// Totais aproximados dos investimentos indexados, para a dashboard.
class YieldSummary {
  const YieldSummary({
    required this.count,
    required this.principal,
    required this.gross,
    required this.taxes,
    this.realizedGain = Money.zero,
    this.cdiAnnualPercent,
  });

  final int count;

  /// Rendimento real de investimentos resgatados por completo.
  final Money realizedGain;
  final Money principal;
  final Money gross;
  final Money taxes;
  final double? cdiAnnualPercent;

  Money get net => gross - taxes;

  Money get grossGain => gross - principal;

  Money get netGain => net - principal;
}
