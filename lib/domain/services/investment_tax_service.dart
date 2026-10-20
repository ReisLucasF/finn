/// Tabelas regressivas de IR e IOF sobre rendimentos de renda fixa.
class InvestmentTaxService {
  const InvestmentTaxService();

  /// Alíquota de IR pelo prazo em dias corridos desde a aplicação.
  /// Até 180 dias: 22,5% · 181–360: 20% · 361–720: 17,5% · acima: 15%.
  double incomeTaxRate(int calendarDays) {
    if (calendarDays <= 180) return 0.225;
    if (calendarDays <= 360) return 0.20;
    if (calendarDays <= 720) return 0.175;
    return 0.15;
  }

  /// Alíquota de IOF sobre o rendimento (Decreto 6.306/2007, anexo).
  /// Regressiva do 1º ao 29º dia; zero a partir do 30º.
  double iofRate(int calendarDays) {
    if (calendarDays <= 0) return 0.96;
    if (calendarDays >= 30) return 0;
    return _iofTable[calendarDays - 1] / 100;
  }

  static const _iofTable = <int>[
    96, 93, 90, 86, 83, 80, 76, 73, 70, 66, //
    63, 60, 56, 53, 50, 46, 43, 40, 36, 33, //
    30, 26, 23, 20, 16, 13, 10, 6, 3,
  ];
}
