enum TransactionSource {
  manual('manual'),
  ofx('ofx'),
  pluggy('pluggy');

  const TransactionSource(this.value);

  final String value;

  static TransactionSource fromValue(String value) {
    return TransactionSource.values.firstWhere(
      (source) => source.value == value,
    );
  }
}
