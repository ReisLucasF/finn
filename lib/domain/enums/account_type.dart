enum AccountType {
  checking('checking'),
  savings('savings'),
  cash('cash'),
  digitalWallet('digital_wallet'),
  other('other');

  const AccountType(this.value);

  final String value;

  static AccountType fromValue(String value) {
    return AccountType.values.firstWhere((type) => type.value == value);
  }

  String get label {
    return switch (this) {
      AccountType.checking => 'Conta corrente',
      AccountType.savings => 'Poupança',
      AccountType.cash => 'Dinheiro',
      AccountType.digitalWallet => 'Carteira digital',
      AccountType.other => 'Outra',
    };
  }
}
