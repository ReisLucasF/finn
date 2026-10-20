import 'package:finan/core/money/money.dart';

/// Converte o decimal do OFX para centavos sem usar ponto flutuante.
Money? tryParseOfxAmount(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final negative = trimmed.startsWith('-');
  var unsigned = trimmed.replaceFirst(RegExp(r'^[+-]'), '');
  if (unsigned.contains(',') && !unsigned.contains('.')) {
    unsigned = unsigned.replaceAll(',', '.');
  } else {
    unsigned = unsigned.replaceAll(',', '');
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(unsigned)) return null;
  final parts = unsigned.split('.');
  final whole = int.parse(parts[0]);
  var fraction = 0;
  if (parts.length == 2 && parts[1].isNotEmpty) {
    final padded = parts[1].padRight(3, '0');
    final cents = int.parse(padded.substring(0, 2));
    final roundUp = int.parse(padded.substring(2, 3)) >= 5 ? 1 : 0;
    fraction = cents + roundUp;
  }
  final value = whole * 100 + fraction;
  return Money(negative ? -value : value);
}
