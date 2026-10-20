import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/domain/services/net_worth_service.dart';
import 'package:finan/domain/services/savings_rate_service.dart';
import 'package:finan/domain/services/transaction_posting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const balance = BalanceService();
  const savings = SavingsRateService();
  const netWorth = NetWorthService();
  const posting = TransactionPosting();
  final now = DateTime.utc(2026, 10, 6);

  test('saldo soma saldo inicial e entries confirmadas', () {
    final result = balance.accountBalance(
      initialBalance: const Money(10000),
      confirmedEntries: const Money(2500),
    );
    expect(result.cents, 12500);
  });

  test('despesa reduz o saldo pelo valor lançado na entry', () {
    final result = balance.accountBalance(
      initialBalance: const Money(10000),
      confirmedEntries: const Money(-2500),
    );
    expect(result.cents, 7500);
  });

  test('saldo do dia inclui o próprio dia e ignora o dia seguinte', () {
    final movements = [
      DailyAccountTotal(
        accountId: 'a1',
        date: const LocalDate(2026, 10, 5),
        amount: const Money(5000),
      ),
      DailyAccountTotal(
        accountId: 'a1',
        date: const LocalDate(2026, 10, 6),
        amount: const Money(-2000),
      ),
      DailyAccountTotal(
        accountId: 'a2',
        date: const LocalDate(2026, 10, 5),
        amount: const Money(9000),
      ),
    ];
    expect(
      balance.balanceAt(
        initialBalance: const Money(10000),
        movements: movements.where((item) => item.accountId == 'a1'),
        date: const LocalDate(2026, 10, 5),
      ),
      const Money(15000),
    );
    expect(
      balance.balanceAt(
        initialBalance: const Money(10000),
        movements: movements.where((item) => item.accountId == 'a1'),
        date: const LocalDate(2026, 10, 6),
      ),
      const Money(13000),
    );
  });

  test('receita entra positiva e despesa entra negativa', () {
    final income = posting.forAccount(
      entryId: 'e1',
      transactionId: 't1',
      accountId: 'a1',
      type: TransactionType.income,
      amount: const Money(5000),
      createdAt: now,
    );
    final expense = posting.forAccount(
      entryId: 'e2',
      transactionId: 't2',
      accountId: 'a1',
      type: TransactionType.expense,
      amount: const Money(2000),
      createdAt: now,
    );
    expect(income.single.amount.cents, 5000);
    expect(expense.single.amount.cents, -2000);
  });

  test('valor zero não gera entry', () {
    expect(
      () => posting.forAccount(
        entryId: 'e',
        transactionId: 't',
        accountId: 'a',
        type: TransactionType.expense,
        amount: const Money(0),
        createdAt: now,
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('economia é receita menos despesa', () {
    final result = savings.savings(
      income: const Money(10000),
      expenses: const Money(6310),
    );
    expect(result.cents, 3690);
    expect(
      savings.rate(income: const Money(10000), expenses: const Money(6310)),
      closeTo(0.369, 0.0000001),
    );
  });

  test('taxa de economia é zero sem receita', () {
    expect(savings.rate(income: Money.zero, expenses: const Money(1000)), 0);
  });

  test('patrimônio soma os saldos das contas', () {
    final result = netWorth.fromAccountBalances(const [
      Money(15000),
      Money(5000),
      Money(-2000),
    ]);
    expect(result.cents, 18000);
  });

  test('período financeiro segue o dia de início do mês', () {
    final october = FinancialPeriod.containing(const LocalDate(2026, 10, 6), 1);
    expect(october.startInclusive, const LocalDate(2026, 10, 1));
    expect(october.endExclusive, const LocalDate(2026, 11, 1));

    final beforeAnchor = FinancialPeriod.containing(
      const LocalDate(2026, 10, 6),
      15,
    );
    expect(beforeAnchor.startInclusive, const LocalDate(2026, 9, 15));
    expect(beforeAnchor.endExclusive, const LocalDate(2026, 10, 15));

    final afterAnchor = FinancialPeriod.containing(
      const LocalDate(2026, 10, 20),
      15,
    );
    expect(afterAnchor.startInclusive, const LocalDate(2026, 10, 15));
    expect(afterAnchor.endExclusive, const LocalDate(2026, 11, 15));
  });
}
