import 'package:finan/core/money/money.dart';
import 'package:finan/domain/pluggy/pluggy_models.dart';
import 'package:finan/domain/services/pluggy_classifier.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const classifier = PluggyClassifier();

  test('centavos arredondam o valor decimal da API', () {
    expect(classifier.cents(10.1), 1010);
    expect(classifier.cents(-75), -7500);
    expect(classifier.cents(10.295), 1030);
  });

  test('fatura de cartão e aplicação não viram receita ou despesa', () {
    expect(
      classifier.classify(
        accountKind: 'CREDIT',
        movementType: 'CREDIT',
        amount: const Money(-15000),
        status: 'POSTED',
      ),
      PluggyPosting.cardBill,
    );
    expect(
      classifier.classify(
        accountKind: 'BANK',
        movementType: 'DEBIT',
        amount: const Money(-1000),
        status: 'POSTED',
        operationType: 'PAGAMENTO_FATURA',
      ),
      PluggyPosting.cardBill,
    );
    expect(
      classifier.classify(
        accountKind: 'BANK',
        movementType: 'DEBIT',
        amount: const Money(-1000),
        status: 'POSTED',
        operationType: 'APLICACAO',
      ),
      PluggyPosting.investmentApplication,
    );
    expect(
      classifier.classify(
        accountKind: 'BANK',
        movementType: 'CREDIT',
        amount: const Money(1200),
        status: 'POSTED',
        operationType: 'RESGATE_APLIC_FINANCEIRA',
      ),
      PluggyPosting.investmentRedemption,
    );
    expect(
      classifier.classify(
        accountKind: 'BANK',
        movementType: 'DEBIT',
        amount: const Money(-2000),
        status: 'POSTED',
      ),
      PluggyPosting.bankExpense,
    );
    expect(
      classifier.classify(
        accountKind: 'BANK',
        movementType: 'DEBIT',
        amount: const Money(-500),
        status: 'PENDING',
      ),
      PluggyPosting.pending,
    );
  });
}
