import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formata reais com separador brasileiro', () {
    expect(formatMoney(const Money(10050)), r'R$ 100,50');
    expect(formatMoney(const Money(123456)), r'R$ 1.234,56');
    expect(formatMoney(const Money(0)), r'R$ 0,00');
    expect(formatMoney(const Money(-50)), r'-R$ 0,50');
  });

  test('interpreta texto monetário em centavos', () {
    expect(tryParseMoney('1.234,56')?.cents, 123456);
    expect(tryParseMoney('R\$ 10,5')?.cents, 1050);
    expect(tryParseMoney('-20,00', allowNegative: true)?.cents, -2000);
    expect(tryParseMoney('-20,00'), isNull);
    expect(tryParseMoney('10,555'), isNull);
    expect(tryParseMoney('abc'), isNull);
    expect(tryParseMoney(''), isNull);
  });

  test('formata data, período e percentual', () {
    expect(formatLocalDate(const LocalDate(2026, 10, 6)), '06/10/2026');
    expect(
      formatPeriod(const LocalDate(2026, 10, 1), const LocalDate(2026, 11, 1)),
      'outubro de 2026',
    );
    expect(formatRate(0.369), '36,9%');
    expect(formatRate(0), '0,0%');
  });
}
