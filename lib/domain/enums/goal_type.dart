enum GoalType {
  netWorth('net_worth'),
  savings('savings'),
  investment('investment'),
  purchase('purchase'),
  custom('custom');

  const GoalType(this.value);

  final String value;

  static GoalType fromValue(String value) {
    return GoalType.values.firstWhere((type) => type.value == value);
  }
}
