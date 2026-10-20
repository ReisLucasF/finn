/// Data civil, sem horário. Persistida como `YYYY-MM-DD` para não mudar de dia
/// por conversão de fuso.
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day)
    : assert(month >= 1 && month <= 12, 'mês inválido'),
      assert(day >= 1 && day <= 31, 'dia inválido');

  final int year;
  final int month;
  final int day;

  static LocalDate parse(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      throw FormatException('Data inválida: $value');
    }
    return LocalDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static LocalDate fromDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    return LocalDate(local.year, local.month, local.day);
  }

  String toIso() {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  LocalDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day).add(Duration(days: days));
    return LocalDate(shifted.year, shifted.month, shifted.day);
  }

  /// Soma meses civis e limita o dia ao último dia do mês de destino.
  LocalDate addMonths(int months) {
    final cursor = DateTime.utc(year, month + months, 1);
    final lastDay = DateTime.utc(cursor.year, cursor.month + 1, 0).day;
    return LocalDate(cursor.year, cursor.month, day > lastDay ? lastDay : day);
  }

  @override
  int compareTo(LocalDate other) {
    final yearCompare = year.compareTo(other.year);
    if (yearCompare != 0) return yearCompare;
    final monthCompare = month.compareTo(other.month);
    if (monthCompare != 0) return monthCompare;
    return day.compareTo(other.day);
  }

  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}
