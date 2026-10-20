import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';

class DailyAccountTotal {
  const DailyAccountTotal({
    required this.accountId,
    required this.date,
    required this.amount,
  });

  final String accountId;
  final LocalDate date;
  final Money amount;
}

class BalanceService {
  const BalanceService();

  /// Saldo real = saldo inicial + entries de lançamentos confirmados.
  /// Pendentes, cancelados e excluídos ficam de fora da soma recebida.
  Money accountBalance({
    required Money initialBalance,
    required Money confirmedEntries,
  }) {
    return Money(initialBalance.cents + confirmedEntries.cents);
  }

  /// Saldo da conta no fim do dia: inicial + movimentos confirmados até essa data.
  Money balanceAt({
    required Money initialBalance,
    required Iterable<DailyAccountTotal> movements,
    required LocalDate date,
  }) {
    var cents = initialBalance.cents;
    for (final movement in movements) {
      if (movement.date <= date) cents += movement.amount.cents;
    }
    return Money(cents);
  }
}
