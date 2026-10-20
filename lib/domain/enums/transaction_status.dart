enum TransactionStatus {
  pending('pending'),
  confirmed('confirmed'),
  cancelled('cancelled');

  const TransactionStatus(this.value);

  final String value;

  bool get affectsBalance => this == TransactionStatus.confirmed;

  static TransactionStatus fromValue(String value) {
    return TransactionStatus.values.firstWhere(
      (status) => status.value == value,
    );
  }

  String get label {
    return switch (this) {
      TransactionStatus.pending => 'Pendente',
      TransactionStatus.confirmed => 'Confirmada',
      TransactionStatus.cancelled => 'Cancelada',
    };
  }
}
