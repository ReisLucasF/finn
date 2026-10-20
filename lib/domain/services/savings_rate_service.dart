import 'package:finan/core/money/money.dart';

class SavingsRateService {
  const SavingsRateService();

  Money savings({required Money income, required Money expenses}) {
    return Money(income.cents - expenses.cents);
  }

  /// Zero quando não há receita. Transferências não entram neste cálculo.
  double rate({required Money income, required Money expenses}) {
    if (income.cents <= 0) return 0;
    return (income.cents - expenses.cents) / income.cents;
  }
}
