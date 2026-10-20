// Gera um backup com dados fictícios para demonstração (vídeo, prints).
//
// Uso:
//   flutter test tool/demo_backup_test.dart
//
// Saída: demo/Finn-demo.financebackup — importe em Mais → Backup → Restaurar.
// Os dados vão de maio até a data de hoje definida abaixo.
import 'dart:io';
import 'dart:math';

import 'package:finan/app/dependency_injection.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/goal_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/recurrence_frequency.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/test_graph.dart';

const _today = LocalDate(2026, 10, 20);
const _months = [5, 6, 7, 8, 9, 10];

Money r$(num reais) => Money((reais * 100).round());

void main() {
  test('gera demo/Finn-demo.financebackup', () async {
    final graph = await openTestGraph(today: _today);
    final seed = _Seeder(graph, Random(42));
    await seed.run();

    final bytes = await graph.createBackup();
    final file = File('demo/Finn-demo.financebackup');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);

    final summary = await graph.getDashboardSummary(seed.userId);
    // ignore: avoid_print
    print(
      'Backup: ${file.path} (${bytes.length ~/ 1024} KB)\n'
      'Patrimônio ${summary.netWorth.cents / 100} · '
      'contas ${summary.totalAccounts.cents / 100} · '
      'investimentos ${summary.totalInvestments.cents / 100} · '
      'cartão ${summary.creditCardDebt.cents / 100}\n'
      'Outubro: receitas ${summary.monthlyIncome.cents / 100} · '
      'despesas ${summary.monthlyExpenses.cents / 100}',
    );
    for (final account in await graph.listAccounts(seed.userId)) {
      // ignore: avoid_print
      print('  ${account.account.name}: ${account.balance.cents / 100}');
    }
    expect(summary.netWorth.cents, greaterThan(0));
  });
}

class _Seeder {
  _Seeder(this.graph, this.random);

  final AppGraph graph;
  final Random random;
  late String userId;
  late Map<String, Category> _categories;

  /// Compras no cartão até o fechamento de 03/10 (fatura a pagar em 10/10).
  int _billed = 0;

  String cat(String name) => _categories[name]!.id;

  /// Valor com variação de ±[spread] (0,1 = 10%), em centavos redondos.
  Money vary(num reais, [double spread = 0.12]) {
    final factor = 1 + (random.nextDouble() * 2 - 1) * spread;
    return r$((reais * factor * 100).round() / 100);
  }

  bool past(LocalDate date) => date <= _today;

  Future<void> expense(
    String account,
    String category,
    Money amount,
    LocalDate date,
    String description, {
    TransactionStatus status = TransactionStatus.confirmed,
  }) async {
    if (!past(date)) return;
    await graph.createTransaction(
      userId: userId,
      type: TransactionType.expense,
      amount: amount,
      transactionDate: date,
      accountId: account,
      categoryId: cat(category),
      description: description,
      status: status,
    );
  }

  Future<void> income(
    String account,
    String category,
    Money amount,
    LocalDate date,
    String description,
  ) async {
    if (!past(date)) return;
    await graph.createTransaction(
      userId: userId,
      type: TransactionType.income,
      amount: amount,
      transactionDate: date,
      accountId: account,
      categoryId: cat(category),
      description: description,
    );
  }

  Future<void> run() async {
    final user = await graph.bootstrap();
    userId = user.id;
    await graph.updateUserProfile(name: 'Lucas');
    _categories = {
      for (final category in await graph.listCategories(userId))
        // Nomes repetidos (Outros) ficam com o primeiro.
        if (!{'Outros'}.contains(category.name) ||
            category.type.value == 'expense')
          category.name: category,
    };

    // ── Contas ──
    final nubank = (await graph.createAccount(
      userId: userId,
      name: 'Nubank',
      type: AccountType.checking,
      initialBalance: r$(2350),
      institutionName: 'Nu Pagamentos',
    )).id;
    final inter = (await graph.createAccount(
      userId: userId,
      name: 'Inter',
      type: AccountType.checking,
      initialBalance: r$(9200),
      institutionName: 'Banco Inter',
    )).id;
    final wallet = (await graph.createAccount(
      userId: userId,
      name: 'Carteira',
      type: AccountType.cash,
      initialBalance: r$(180),
    )).id;
    final savings = (await graph.createAccount(
      userId: userId,
      name: 'Poupança Caixa',
      type: AccountType.savings,
      initialBalance: r$(3200),
      institutionName: 'Caixa',
    )).id;

    // ── Cartão ──
    final card = await graph.createCreditCard(
      userId: userId,
      name: 'Nubank Ultravioleta',
      creditLimit: r$(8000),
      closingDay: 3,
      dueDay: 10,
      issuer: 'Mastercard',
      lastFourDigits: '4821',
    );

    // O relógio do teste é fixo; abre contas e cartão antes do histórico,
    // senão o gráfico de patrimônio só conta os saldos iniciais em outubro.
    final db = await graph.database.open();
    for (final table in ['accounts', 'credit_cards', 'investments']) {
      await db.update(table, {'created_at': '2026-04-30T12:00:00.000Z'});
    }

    // ── Investimentos ──
    Future<String> invest(
      String name,
      InvestmentKind kind,
      String account, {
      String? institution,
    }) async => (await graph.createInvestment(
      userId: userId,
      name: name,
      kind: kind,
      institution: institution,
      accountId: account,
    )).id;
    final cdb = await invest(
      'CDB Nubank 102%',
      InvestmentKind.fixedIncome,
      nubank,
      institution: 'Nubank',
    );
    final selic = await invest(
      'Tesouro Selic 2029',
      InvestmentKind.fixedIncome,
      inter,
      institution: 'Tesouro Direto',
    );
    final lci = await invest(
      'LCI Inter 92%',
      InvestmentKind.fixedIncome,
      inter,
      institution: 'Banco Inter',
    );
    final etf = await invest(
      'BOVA11',
      InvestmentKind.etf,
      inter,
      institution: 'Inter Invest',
    );

    Future<void> move(
      String investment,
      InvestmentMovementType type,
      num reais,
      LocalDate date, {
      String? account,
    }) => graph.moveInvestment(
      userId: userId,
      investmentId: investment,
      movement: type,
      amount: r$(reais),
      date: date,
      accountId: account,
    );

    await move(
      selic,
      InvestmentMovementType.contribution,
      5000,
      const LocalDate(2026, 5, 8),
      account: inter,
    );
    await move(
      lci,
      InvestmentMovementType.contribution,
      3000,
      const LocalDate(2026, 6, 12),
      account: inter,
    );
    await move(
      etf,
      InvestmentMovementType.contribution,
      1500,
      const LocalDate(2026, 6, 20),
      account: inter,
    );
    await move(
      etf,
      InvestmentMovementType.contribution,
      600,
      const LocalDate(2026, 9, 18),
      account: inter,
    );
    await move(
      etf,
      InvestmentMovementType.income,
      186.40,
      const LocalDate(2026, 10, 15),
    );

    // ── Mês a mês ──
    for (final month in _months) {
      LocalDate d(int day) => LocalDate(2026, month, day);

      await income(
        nubank,
        'Salário',
        r$(6850),
        d(5),
        'Salário Acme Tecnologia',
      );
      if (month.isOdd) {
        await income(
          inter,
          'Freelance',
          vary(1400, 0.3),
          d(18),
          'Freela site Padaria Doce Lar',
        );
      }
      await income(nubank, 'Juros', vary(3.2, 0.3), d(1), 'Rendimento conta');

      // Fixas
      await expense(nubank, 'Moradia', r$(1650), d(10), 'Aluguel apartamento');
      await expense(
        nubank,
        'Moradia',
        vary(214, 0.18),
        d(12),
        'Conta de luz Cemig',
      );
      await expense(
        nubank,
        'Serviços',
        r$(109.90),
        d(25),
        'Internet Vivo Fibra',
      );
      await expense(
        nubank,
        'Educação',
        r$(489),
        d(8),
        'Mensalidade pós-graduação',
      );
      await expense(nubank, 'Saúde', r$(99.90), d(6), 'Academia SmartFit');
      await expense(nubank, 'Assinaturas', r$(55.90), d(14), 'Netflix');
      await expense(nubank, 'Assinaturas', r$(21.90), d(16), 'Spotify');
      await expense(nubank, 'Assinaturas', r$(19.90), d(21), 'iCloud 200 GB');

      // Variáveis
      for (final day in [3, 10, 17, 24]) {
        await expense(
          nubank,
          'Alimentação',
          vary(235, 0.3),
          d(day),
          [
            'Supermercado BH',
            'Verdemar',
            'Sacolão Central',
            'Supermercado BH',
          ][day ~/ 8],
        );
      }
      for (final day in [7, 19, 27]) {
        await expense(
          wallet,
          'Alimentação',
          vary(48, 0.4),
          d(day),
          ['Padaria Pão Quente', 'Feira de domingo', 'Lanchonete do Zé'][day ~/
              10],
        );
      }
      for (final day in [4, 11, 20, 26]) {
        await expense(
          nubank,
          'Transporte',
          vary(62, 0.45),
          d(day),
          day.isEven ? 'Uber' : 'Posto Ipiranga',
        );
      }
      await expense(inter, 'Lazer', vary(140, 0.35), d(13), 'Cinema e jantar');
      await expense(inter, 'Saúde', vary(85, 0.4), d(22), 'Farmácia Araujo');

      // Cartão: compras do mês e pagamento da fatura anterior
      final purchases = <(String, num, int, String)>[
        ('Alimentação', 92, 2, 'iFood'),
        ('Alimentação', 68, 15, 'iFood'),
        ('Compras', 240, 9, 'Amazon'),
        ('Lazer', 120, 23, 'Ingresso.com'),
        if (month == 7) ('Viagens', 1380, 11, 'Latam — passagens Floripa'),
        if (month == 10) ('Compras', 389, 12, 'Renner'),
      ];
      for (final (category, reais, day, description) in purchases) {
        if (!past(d(day))) continue;
        final amount = vary(reais, 0.2);
        await graph.createCardPurchase(
          userId: userId,
          cardId: card.id,
          categoryId: cat(category),
          amount: amount,
          date: d(day),
          description: description,
        );
        if (d(day) <= const LocalDate(2026, 10, 3)) _billed += amount.cents;
      }

      // Investimento mensal no CDB
      if (past(d(6))) {
        await move(
          cdb,
          InvestmentMovementType.contribution,
          month == 5 ? 2000 : 800,
          d(6),
          account: nubank,
        );
      }
      // Saque para a carteira
      if (past(d(2))) {
        await graph.createTransfer(
          userId: userId,
          sourceAccountId: nubank,
          destinationAccountId: wallet,
          amount: r$(150),
          date: d(2),
          description: 'Saque',
        );
      }
      // Guardar na poupança
      if (past(d(28))) {
        await graph.createTransfer(
          userId: userId,
          sourceAccountId: nubank,
          destinationAccountId: savings,
          amount: r$(300),
          date: d(28),
          description: 'Reserva mensal',
        );
      }
    }

    // Fatura: paga tudo até o fechamento de 03/10; outubro fica em aberto.
    await graph.payCreditCard(
      userId: userId,
      cardId: card.id,
      accountId: nubank,
      amount: Money(_billed),
      date: const LocalDate(2026, 10, 10),
    );

    // ── Rentabilidade (indexadores) ──
    await graph.saveInvestmentYield(
      investmentId: cdb,
      indexer: YieldIndexer.cdiPercent,
      rate: 102,
      taxRegime: TaxRegime.regressive,
    );
    await graph.saveInvestmentYield(
      investmentId: selic,
      indexer: YieldIndexer.cdiPlus,
      rate: 0.08,
      taxRegime: TaxRegime.regressive,
    );
    await graph.saveInvestmentYield(
      investmentId: lci,
      indexer: YieldIndexer.cdiPercent,
      rate: 92,
      taxRegime: TaxRegime.exempt,
    );

    // ── Metas ──
    await graph.createFinancialGoal(
      userId: userId,
      name: 'Primeiros 100 mil',
      targetAmount: r$(100000),
      currentAmount: Money.zero,
      expectedMonthlySavings: r$(1500),
      monthlyRate: 0,
      goalType: GoalType.netWorth,
    );
    await graph.createFinancialGoal(
      userId: userId,
      name: 'Viagem para o Chile',
      targetAmount: r$(12000),
      currentAmount: r$(4300),
      expectedMonthlySavings: r$(900),
      monthlyRate: 0,
      goalType: GoalType.purchase,
      targetDate: const LocalDate(2027, 7, 1),
    );
    await graph.createFinancialGoal(
      userId: userId,
      name: 'Notebook novo',
      targetAmount: r$(7500),
      currentAmount: r$(5900),
      expectedMonthlySavings: r$(500),
      monthlyRate: 0,
      goalType: GoalType.purchase,
      targetDate: const LocalDate(2027, 1, 31),
    );

    // ── Reserva de emergência ──
    await graph.configureEmergencyFund(
      userId: userId,
      targetMonths: 6,
      essentialCategoryIds: [
        for (final name in [
          'Moradia',
          'Alimentação',
          'Transporte',
          'Saúde',
          'Educação',
          'Serviços',
        ])
          cat(name),
      ],
    );

    // ── Orçamentos (alguns perto do limite, para mostrar os alertas) ──
    for (final (name, limit) in [
      ('Alimentação', 1600),
      ('Transporte', 220),
      ('Lazer', 160),
      ('Compras', 550),
      ('Assinaturas', 130),
    ]) {
      await graph.saveBudget(
        userId: userId,
        categoryId: cat(name),
        monthlyLimit: r$(limit),
      );
    }

    // ── Recorrências e próximos vencimentos ──
    Future<void> recurring(
      String name,
      String category,
      num reais,
      LocalDate start,
    ) async {
      await graph.createRecurrence(
        userId: userId,
        name: name,
        type: TransactionType.expense,
        amount: r$(reais),
        accountId: nubank,
        categoryId: cat(category),
        frequency: RecurrenceFrequency.monthly,
        startDate: start,
      );
    }

    await recurring(
      'Internet Vivo Fibra',
      'Serviços',
      109.90,
      _today.addDays(5),
    );
    await recurring(
      'Aluguel apartamento',
      'Moradia',
      1650,
      const LocalDate(2026, 11, 10),
    );
    await recurring(
      'Mensalidade pós-graduação',
      'Educação',
      489,
      const LocalDate(2026, 11, 8),
    );
    for (final recurrence in await graph.finance.listRecurrences(userId)) {
      await graph.generateProvisions(
        userId: userId,
        recurrenceId: recurrence.id,
        until: _today.addDays(30),
      );
    }
  }
}
