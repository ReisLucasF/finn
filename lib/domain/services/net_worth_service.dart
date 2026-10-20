import 'package:finan/core/money/money.dart';

class NetWorthService {
  const NetWorthService();

  /// Patrimônio = contas + investimentos − dívida de cartão.
  Money calculate({
    required Money accounts,
    required Money investments,
    required Money cardDebt,
  }) {
    return Money(accounts.cents + investments.cents - cardDebt.cents);
  }

  Money fromAccountBalances(Iterable<Money> balances) {
    var total = 0;
    for (final balance in balances) {
      total += balance.cents;
    }
    return Money(total);
  }
}
