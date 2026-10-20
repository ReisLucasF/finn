import 'package:finan/app/dependency_injection.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_graph.dart';

void main() {
  Future<
    ({
      AppGraph graph,
      String userId,
      String accountId,
      String investmentId,
      String expenseCategoryId,
    })
  >
  setup() async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(1000000),
    );
    final investment = await graph.createInvestment(
      userId: user.id,
      name: 'CDB',
      kind: InvestmentKind.fixedIncome,
    );
    await graph.moveInvestment(
      userId: user.id,
      investmentId: investment.id,
      movement: InvestmentMovementType.contribution,
      amount: const Money(500000),
      date: const LocalDate(2026, 10, 1),
      accountId: account.id,
    );
    final categories = await graph.listCategories(user.id);
    final food = categories.firstWhere((c) => c.name == 'Alimentação');
    return (
      graph: graph,
      userId: user.id,
      accountId: account.id,
      investmentId: investment.id,
      expenseCategoryId: food.id,
    );
  }

  Future<Money> position(AppGraph graph, String investmentId) async =>
      (await graph.finance.findInvestment(investmentId))!.currentValue;

  test(
    'despesa paga com investimento cadastrado desconta da posição',
    () async {
      final s = await setup();
      final graph = s.graph;
      expect(await position(graph, s.investmentId), const Money(500000));

      final expense = await graph.createTransaction(
        userId: s.userId,
        type: TransactionType.expense,
        amount: const Money(16717),
        transactionDate: const LocalDate(2026, 10, 5),
        accountId: s.accountId,
        categoryId: s.expenseCategoryId,
        description: 'Mercado',
        fundFromInvestment: true,
        investmentProductLabel: 'CDB',
        fundingInvestmentId: s.investmentId,
      );
      expect(await position(graph, s.investmentId), const Money(483283));
      // O resgate credita a conta: a despesa não muda o saldo.
      expect(
        await graph.calculateAccountBalance(s.accountId),
        const Money(500000),
      );

      // Editar o valor da despesa acompanha na posição.
      await graph.updateTransaction(
        id: expense.id,
        type: TransactionType.expense,
        amount: const Money(20000),
        transactionDate: const LocalDate(2026, 10, 5),
        accountId: s.accountId,
        categoryId: s.expenseCategoryId,
        status: TransactionStatus.confirmed,
        fundFromInvestment: true,
      );
      expect(await position(graph, s.investmentId), const Money(480000));
      expect(
        await graph.calculateAccountBalance(s.accountId),
        const Money(500000),
      );

      // Excluir a despesa devolve o valor ao investimento.
      await graph.deleteTransaction(expense.id);
      expect(await position(graph, s.investmentId), const Money(500000));
    },
  );

  test('excluir lançamento vinculado desfaz a movimentação', () async {
    final s = await setup();
    final graph = s.graph;
    final linked = await graph.listTransactions(
      userId: s.userId,
      investmentId: s.investmentId,
      limit: 10,
    );
    await graph.deleteTransaction(linked.items.single.id);
    expect(await position(graph, s.investmentId), Money.zero);
    expect(await graph.removeOrphanMovements.list(s.investmentId), isEmpty);
  });

  test(
    'editar e excluir investimento; lançamentos voltam ao extrato',
    () async {
      final s = await setup();
      final graph = s.graph;
      await graph.updateInvestment(
        userId: s.userId,
        investmentId: s.investmentId,
        name: 'CDB BTG 110%',
        kind: InvestmentKind.fixedIncome,
        institution: 'BTG',
      );
      final edited = await graph.finance.findInvestment(s.investmentId);
      expect(edited!.name, 'CDB BTG 110%');
      expect(edited.institution, 'BTG');
      expect(edited.currentValue, const Money(500000));

      final unlinked = await graph.deleteInvestment(
        userId: s.userId,
        investmentId: s.investmentId,
      );
      expect(unlinked, 1);
      final list = await graph.finance.listInvestments(s.userId);
      expect(list.where((i) => !i.isDeleted), isEmpty);
      // O aporte continua no extrato, agora não vinculado.
      final cash = await graph.transactions.listUnlinkedInvestmentCash(
        s.userId,
      );
      expect(cash, hasLength(1));
    },
  );
}
