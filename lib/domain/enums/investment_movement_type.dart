enum InvestmentMovementType {
  contribution('contribution'),
  withdrawal('withdrawal'),
  income('income'),
  loss('loss'),
  fee('fee');

  const InvestmentMovementType(this.value);

  final String value;

  static InvestmentMovementType fromValue(String value) {
    return InvestmentMovementType.values.firstWhere(
      (type) => type.value == value,
    );
  }
}
