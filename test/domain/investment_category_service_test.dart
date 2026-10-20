import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = InvestmentCategoryService();
  const day = LocalDate(2026, 10, 6);

  InvestmentCashEvent event(TransactionType type, int cents, [String name = 'CDB']) {
    return InvestmentCashEvent(
      description: name,
      type: type,
      amount: Money(cents),
      date: day,
    );
  }

  test('aporte fica aplicado e resgate maior vira rendimento', () {
    final open = service.settle([
      event(TransactionType.investmentContribution, 1000000),
    ]);
    expect(open.openCapital, const Money(1000000));
    expect(open.realizedGain, Money.zero);

    final closed = service.settle([
      event(TransactionType.investmentContribution, 1000000),
      event(TransactionType.investmentWithdrawal, 1200000),
    ]);
    expect(closed.openCapital, Money.zero);
    expect(closed.realizedGain, const Money(200000));
  });

  test('resgate parcial não vira perda e nomes diferentes não se misturam', () {
    final snapshot = service.settle([
      event(TransactionType.investmentContribution, 1000000, 'CDB'),
      event(TransactionType.investmentWithdrawal, 400000, 'CDB'),
      event(TransactionType.investmentContribution, 500000, 'Ações'),
    ]);
    expect(snapshot.openCapital, const Money(1100000));
    expect(snapshot.realizedGain, Money.zero);
  });

  test('reserva e retirada do mesmo cofrinho se compensam', () {
    final snapshot = service.settle([
      event(
        TransactionType.investmentContribution,
        800000,
        'Dinheiro reservado Emergências',
      ),
      event(
        TransactionType.investmentWithdrawal,
        15000,
        'Dinheiro retirado Emergências',
      ),
      event(
        TransactionType.investmentContribution,
        365000,
        'Cdb Credito Banco Inter Sa',
      ),
      event(
        TransactionType.investmentWithdrawal,
        365309,
        'Cdb Credito Banco Inter S A',
      ),
    ]);
    expect(snapshot.openCapital, const Money(785000));
    expect(snapshot.realizedGain, const Money(309));
  });

  test('vínculo parcial de resgates não infla o total investido', () {
    InvestmentCashEvent cash(
      TransactionType type,
      int cents,
      String name, {
      String? investmentId,
    }) {
      return InvestmentCashEvent(
        description: name,
        type: type,
        amount: Money(cents),
        date: day,
        investmentId: investmentId,
      );
    }

    final events = [
      cash(TransactionType.investmentContribution, 1000000, 'CDB'),
      cash(TransactionType.investmentContribution, 500000, 'CDB'),
      cash(
        TransactionType.investmentWithdrawal,
        960000,
        'CDB',
        investmentId: 'inv-1',
      ),
      cash(
        TransactionType.investmentContribution,
        800000,
        'Dinheiro reservado Emergências',
      ),
    ];

    // Só o resgate vinculado: settle(unlinked) deixaria 1.500 + 800 = 2.300.
    expect(service.settle([
      for (final e in events)
        if (!e.isLinked) e,
    ]).openCapital, const Money(2300000));

    // Fórmula correta: todo o extrato (− vinculados no FIFO) = 540 + 800.
    expect(
      service.totalInvested(registeredValues: const [Money.zero], allCashEvents: events),
      const Money(1340000),
    );
    expect(service.unlinkedOpenCapital(events), const Money(1340000));
  });
}
