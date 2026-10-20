enum InvestmentKind {
  fixedIncome('fixed_income'),
  stocks('stocks'),
  funds('funds'),
  etf('etf'),
  crypto('crypto'),
  pension('pension'),
  other('other');

  const InvestmentKind(this.value);

  final String value;

  static InvestmentKind fromValue(String value) {
    return InvestmentKind.values.firstWhere((type) => type.value == value);
  }

  String get label {
    return switch (this) {
      InvestmentKind.fixedIncome => 'Renda fixa',
      InvestmentKind.stocks => 'Ações',
      InvestmentKind.funds => 'Fundos',
      InvestmentKind.etf => 'ETF',
      InvestmentKind.crypto => 'Cripto',
      InvestmentKind.pension => 'Previdência',
      InvestmentKind.other => 'Outro',
    };
  }
}
