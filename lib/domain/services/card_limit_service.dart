import 'package:finan/core/money/money.dart';

class CardLimitService {
  const CardLimitService();

  Money used({required Money initialUsed, required Money confirmedEntries}) {
    return Money(initialUsed.cents + confirmedEntries.cents);
  }

  /// O disponível não passa do limite, mesmo com pagamento acima da dívida.
  Money available({required Money limit, required Money used}) {
    final raw = limit.cents - used.cents;
    if (raw > limit.cents) return limit;
    return Money(raw);
  }
}
