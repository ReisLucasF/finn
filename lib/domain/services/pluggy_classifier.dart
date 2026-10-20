import 'package:finan/core/money/money.dart';
import 'package:finan/domain/pluggy/pluggy_models.dart';

class PluggyClassifier {
  const PluggyClassifier();

  /// Converte o decimal da API para centavos, arredondando o terceiro dígito.
  int cents(num amount) {
    final negative = amount.isNegative;
    final rounded = (amount.abs() * 100).round();
    return negative ? -rounded : rounded;
  }

  PluggyPosting classify({
    required String accountKind,
    required String movementType,
    required Money amount,
    required String status,
    String? operationType,
  }) {
    if (status.toUpperCase() != 'POSTED') return PluggyPosting.pending;
    if (amount.cents == 0) return PluggyPosting.ignored;
    final operation = (operationType ?? '').toUpperCase();
    if (operation.contains('PAGAMENTO_FATURA')) return PluggyPosting.cardBill;
    if (operation.contains('RESGATE_APLIC')) {
      return PluggyPosting.investmentRedemption;
    }
    if (operation.contains('APLIC')) return PluggyPosting.investmentApplication;
    final creditAccount = accountKind.toUpperCase() == 'CREDIT';
    final credit = movementType.toUpperCase() == 'CREDIT';
    if (creditAccount && credit) return PluggyPosting.cardBill;
    if (creditAccount) return PluggyPosting.cardExpense;
    if (credit) return PluggyPosting.bankIncome;
    return PluggyPosting.bankExpense;
  }
}
