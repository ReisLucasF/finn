import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/app_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:flutter/material.dart';

const monthNames = <String>[
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

String signedAmount(TransactionType type, Money amount) {
  final prefix = switch (type) {
    TransactionType.income ||
    TransactionType.investmentWithdrawal ||
    TransactionType.investmentIncome => '+',
    TransactionType.transfer => '',
    TransactionType.expense ||
    TransactionType.investmentContribution ||
    TransactionType.investmentLoss ||
    TransactionType.creditCardPayment => '−',
  };
  return '$prefix${formatMoney(amount)}';
}

String formatMoney(Money money) {
  final negative = money.cents < 0;
  final absolute = money.cents.abs();
  final whole = absolute ~/ 100;
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      grouped.write('.');
    }
    grouped.write(digits[index]);
  }
  return '${negative ? '-' : ''}R\$ $grouped,$fraction';
}

String formatRate(double rate) {
  final negative = rate < 0;
  final basisPoints = (rate.abs() * 1000).round();
  final whole = basisPoints ~/ 10;
  final fraction = basisPoints % 10;
  return '${negative ? '-' : ''}$whole,$fraction%';
}

String formatLocalDate(LocalDate date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String formatPeriod(LocalDate start, LocalDate endExclusive) {
  final end = endExclusive.addDays(-1);
  final calendarMonth = start.day == 1 && endExclusive.day == 1;
  if (calendarMonth && start.month == end.month) {
    return '${monthNames[start.month - 1]} de ${start.year}';
  }
  return '${formatLocalDate(start)} – ${formatLocalDate(end)}';
}

String friendlyError(Object error) {
  if (error is AppException) return error.message;
  return 'Não foi possível concluir a operação.';
}

Color colorFromHex(String? hex, Color fallback) {
  if (hex == null || hex.isEmpty) return fallback;
  final normalized = hex.replaceAll('#', '');
  final value = int.tryParse(normalized, radix: 16);
  if (value == null) return fallback;
  return Color(0xFF000000 | value);
}

IconData iconFromName(String? name) {
  return switch (name) {
    'payments' => Icons.payments_outlined,
    'work' => Icons.work_outline,
    'handshake' => Icons.handshake_outlined,
    'trending_up' => Icons.trending_up,
    'percent' => Icons.percent,
    'home' => Icons.home_outlined,
    'restaurant' => Icons.restaurant_outlined,
    'directions_car' => Icons.directions_car_outlined,
    'favorite' => Icons.favorite_border,
    'school' => Icons.school_outlined,
    'local_activity' => Icons.local_activity_outlined,
    'subscriptions' => Icons.subscriptions_outlined,
    'shopping_bag' => Icons.shopping_bag_outlined,
    'account_balance' => Icons.account_balance_outlined,
    'build' => Icons.build_outlined,
    'flight' => Icons.flight_outlined,
    'label' => Icons.label_outline,
    _ => Icons.label_outline,
  };
}

Money? tryParseMoney(String input, {bool allowNegative = false}) {
  return parseMoneyInput(input, allowNegative: allowNegative);
}
