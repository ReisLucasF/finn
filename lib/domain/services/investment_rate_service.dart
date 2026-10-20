import 'package:finan/core/money/money.dart';

class InvestmentRateService {
  const InvestmentRateService();

  /// Aportes confirmados divididos pela receita. Zero sem receita.
  double rate({required Money contributions, required Money income}) {
    if (income.cents <= 0) return 0;
    return contributions.cents / income.cents;
  }
}
