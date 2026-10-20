enum TransactionType {
  income('income'),
  expense('expense'),
  transfer('transfer'),
  investmentContribution('investment_contribution'),
  investmentWithdrawal('investment_withdrawal'),
  investmentIncome('investment_income'),
  investmentLoss('investment_loss'),
  creditCardPayment('credit_card_payment');

  const TransactionType(this.value);

  final String value;

  static TransactionType fromValue(String value) {
    return TransactionType.values.firstWhere((type) => type.value == value);
  }

  bool get countsAsIncome => this == TransactionType.income;

  bool get countsAsExpense => this == TransactionType.expense;

  String get label {
    return switch (this) {
      TransactionType.income => 'Receita',
      TransactionType.expense => 'Despesa',
      TransactionType.transfer => 'Transferência',
      TransactionType.investmentContribution => 'Aporte',
      TransactionType.investmentWithdrawal => 'Resgate',
      TransactionType.investmentIncome => 'Rendimento',
      TransactionType.investmentLoss => 'Perda',
      TransactionType.creditCardPayment => 'Pagamento de cartão',
    };
  }
}
