import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';

class InvestmentPositionService {
  const InvestmentPositionService();

  Money valueOf(Iterable<({InvestmentMovementType type, Money amount})> movements) {
    var cents = 0;
    for (final movement in movements) {
      final signed = switch (movement.type) {
        InvestmentMovementType.contribution ||
        InvestmentMovementType.income => movement.amount.cents,
        InvestmentMovementType.withdrawal ||
        InvestmentMovementType.loss ||
        InvestmentMovementType.fee => -movement.amount.cents,
      };
      cents += signed;
    }
    return Money(cents);
  }
}
