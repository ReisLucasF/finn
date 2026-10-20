/// Valor monetário em centavos. Cálculos usam [cents], nunca ponto flutuante.
class Money implements Comparable<Money> {
  const Money(this.cents);

  final int cents;

  static const zero = Money(0);

  bool get isNegative => cents < 0;
  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;

  Money operator +(Money other) => Money(cents + other.cents);

  Money operator -(Money other) => Money(cents - other.cents);

  Money operator -() => Money(-cents);

  /// Apenas para exibição. Não usar em cálculo financeiro.
  double get decimal => cents / 100;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  bool operator >(Money other) => cents > other.cents;

  bool operator <(Money other) => cents < other.cents;

  bool operator >=(Money other) => cents >= other.cents;

  bool operator <=(Money other) => cents <= other.cents;

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money($cents)';
}

/// Interpreta texto em formato BR (`1.234,56`, `R$ 10,5`, `20`).
Money? parseMoneyInput(String input, {bool allowNegative = false}) {
  var raw = input
      .trim()
      .replaceAll('R\$', '')
      .replaceAll(' ', '')
      .replaceAll('\u00A0', '');
  if (raw.isEmpty) return null;
  final negative = raw.startsWith('-');
  if (negative) {
    if (!allowNegative) return null;
    raw = raw.substring(1);
  }
  if (raw.isEmpty) return null;

  final String normalized;
  if (raw.contains(',')) {
    normalized = raw.replaceAll('.', '').replaceAll(',', '.');
  } else {
    normalized = raw;
  }
  final parts = normalized.split('.');
  if (parts.length > 2 || (parts[0].isEmpty && parts.length == 1)) {
    return null;
  }
  if (!RegExp(r'^\d*$').hasMatch(parts[0])) return null;
  final whole = parts[0].isEmpty ? 0 : int.tryParse(parts[0]);
  if (whole == null) return null;
  var fraction = 0;
  if (parts.length == 2) {
    if (!RegExp(r'^\d{0,2}$').hasMatch(parts[1])) return null;
    fraction = int.parse(parts[1].padRight(2, '0').padLeft(2, '0'));
    if (parts[1].isEmpty) fraction = 0;
  }
  final cents = whole * 100 + fraction;
  return Money(negative ? -cents : cents);
}
