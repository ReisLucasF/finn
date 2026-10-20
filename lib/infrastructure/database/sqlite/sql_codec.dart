int boolToSql(bool value) => value ? 1 : 0;

bool boolFromSql(Object? value) => value == 1;

String formatTimestamp(DateTime value) => value.toUtc().toIso8601String();

DateTime parseTimestamp(String value) => DateTime.parse(value).toUtc();

int asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('Inteiro inválido: $value');
}
