import 'package:finan/core/money/money.dart';

class ProjectedBalanceService {
  const ProjectedBalanceService();

  /// Saldo projetado não substitui o saldo real.
  /// Provisionamento entra aqui e fica fora do saldo confirmado.
  Money project({
    required Money currentBalance,
    required Money provisionedIncome,
    required Money provisionedExpenses,
  }) {
    return Money(
      currentBalance.cents +
          provisionedIncome.cents -
          provisionedExpenses.cents,
    );
  }
}
