import 'package:finan/application/pluggy/pluggy_sync.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/pluggy/pluggy_models.dart';
import 'package:finan/domain/repositories/pluggy_gateway.dart';
import 'package:finan/domain/services/transaction_posting.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_pluggy_repository.dart';

import '../support/test_graph.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('importação do Meu Pluggy respeita fatura, aporte e duplicata', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final card = await graph.createCreditCard(
      userId: user.id,
      name: 'Visa',
      creditLimit: const Money(500000),
    );
    final sync = PluggySync(
      gateway: _Gateway(),
      pluggy: SqlitePluggyRepository(graph.database),
      accounts: graph.accounts,
      finance: graph.finance,
      categories: graph.categories,
      transactions: graph.transactions,
      posting: const TransactionPosting(),
      clock: graph.clock,
      ids: graph.ids,
    );
    await sync.save(
      PluggyConnection(
        userId: user.id,
        clientId: 'client',
        clientSecret: 'secret',
        itemId: 'item',
      ),
    );
    final lines = await sync.preview(
      userId: user.id,
      links: [
        PluggyAccountLink(
          pluggyAccountId: 'bank',
          userId: user.id,
          name: 'Corrente',
          kind: 'BANK',
          accountId: account.id,
        ),
        PluggyAccountLink(
          pluggyAccountId: 'card',
          userId: user.id,
          name: 'Visa',
          kind: 'CREDIT',
          creditCardId: card.id,
        ),
      ],
    );
    expect(
      lines.where((line) => line.posting == PluggyPosting.cardBill).single.canImport,
      isFalse,
    );
    final imported = await sync.import(
      userId: user.id,
      lines: [for (final line in lines) if (line.selectedByDefault) line],
    );
    expect(imported.imported, 4);
    expect(imported.reconciled, 0);
    expect(await graph.calculateAccountBalance(account.id), const Money(12000));
    expect(
      await graph.transactions.sumConfirmedAmount(
        userId: user.id,
        type: TransactionType.expense,
        fromInclusive: const LocalDate(2026, 10, 1),
        toExclusive: const LocalDate(2026, 11, 1),
      ),
      const Money(5000),
    );
    expect(
      await graph.transactions.sumConfirmedAmount(
        userId: user.id,
        type: TransactionType.income,
        fromInclusive: const LocalDate(2026, 10, 1),
        toExclusive: const LocalDate(2026, 11, 1),
      ),
      const Money(5000),
    );
    final summary = await graph.getDashboardSummary(user.id);
    expect(summary.creditCardDebt, const Money(3000));
    expect(summary.totalInvestments, const Money(1000));
    expect(summary.netWorth, const Money(10000));
    expect(
      (await sync.import(
        userId: user.id,
        lines: [for (final line in lines) if (line.selectedByDefault) line],
      )).imported,
      0,
    );
  });

  test('concilia lançamento manual e relaciona categoria do Pluggy', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final categories = await graph.categories.listByUser(user.id);
    final food = categories.singleWhere((category) => category.name == 'Alimentação');
    final manual = await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(2000),
      transactionDate: const LocalDate(2026, 10, 1),
      accountId: account.id,
      description: 'Padaria',
    );
    final sync = PluggySync(
      gateway: _CategorizedGateway(),
      pluggy: SqlitePluggyRepository(graph.database),
      accounts: graph.accounts,
      finance: graph.finance,
      categories: graph.categories,
      transactions: graph.transactions,
      posting: const TransactionPosting(),
      clock: graph.clock,
      ids: graph.ids,
    );
    await sync.save(
      PluggyConnection(
        userId: user.id,
        clientId: 'client',
        clientSecret: 'secret',
        itemId: 'item',
      ),
    );
    final lines = await sync.preview(
      userId: user.id,
      links: [
        PluggyAccountLink(
          pluggyAccountId: 'bank',
          userId: user.id,
          name: 'Corrente',
          kind: 'BANK',
          accountId: account.id,
        ),
      ],
    );
    final padaria = lines.singleWhere((line) => line.description == 'Padaria');
    final feira = lines.singleWhere((line) => line.description == 'Hortifruti');
    expect(padaria.suggestReconcile, isTrue);
    expect(padaria.matchTransactionId, manual.id);
    expect(feira.categoryId, food.id);
    expect(feira.selectedByDefault, isTrue);
    final result = await sync.import(
      userId: user.id,
      lines: [padaria, feira],
      reconcileIds: {padaria.remoteId},
    );
    expect(result.imported, 1);
    expect(result.reconciled, 1);
    expect(await graph.calculateAccountBalance(account.id), const Money(6500));
    final linked = await graph.transactions.findById(manual.id);
    expect(linked!.externalId, 'pluggy:mercado');
    final created = lines.isEmpty
        ? null
        : (await graph.transactions.findReconciliationCandidates(
            userId: user.id,
            accountId: account.id,
            absoluteAmount: const Money(1500),
            date: const LocalDate(2026, 10, 2),
          )).single;
    expect(created!.categoryId, food.id);
    expect(created.externalId, 'pluggy:feira');
  });

  test('atualiza o limite do cartão vinculado e preserva uso inicial maior', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final card = await graph.createCreditCard(
      userId: user.id,
      name: 'Visa',
      creditLimit: const Money(100000),
    );
    final tight = await graph.createCreditCard(
      userId: user.id,
      name: 'Apertado',
      creditLimit: const Money(5000),
      initialUsedLimit: const Money(4000),
    );
    final sync = PluggySync(
      gateway: _Gateway(),
      pluggy: SqlitePluggyRepository(graph.database),
      accounts: graph.accounts,
      finance: graph.finance,
      categories: graph.categories,
      transactions: graph.transactions,
      posting: const TransactionPosting(),
      clock: graph.clock,
      ids: graph.ids,
    );
    final applied = await sync.saveAccountLink(
      userId: user.id,
      link: PluggyAccountLink(
        pluggyAccountId: 'card',
        userId: user.id,
        name: 'Visa',
        kind: 'CREDIT',
        creditCardId: card.id,
      ),
      remote: const PluggyRemoteAccount(
        id: 'card',
        name: 'Visa',
        kind: 'CREDIT',
        creditLimit: Money(988000),
        brand: 'VISA',
        lastFourDigits: '4321',
        closingDay: 3,
        dueDay: 10,
      ),
    );
    expect(applied, isTrue);
    final updated = await graph.finance.findCreditCard(card.id);
    expect(updated!.creditLimit, const Money(988000));
    expect(updated.brand, 'VISA');
    expect(updated.lastFourDigits, '4321');
    expect(updated.closingDay, 3);
    expect(updated.dueDay, 10);
    final kept = await sync.saveAccountLink(
      userId: user.id,
      link: PluggyAccountLink(
        pluggyAccountId: 'tight',
        userId: user.id,
        name: 'Apertado',
        kind: 'CREDIT',
        creditCardId: tight.id,
      ),
      remote: const PluggyRemoteAccount(
        id: 'tight',
        name: 'Apertado',
        kind: 'CREDIT',
        creditLimit: Money(1000),
      ),
    );
    expect(kept, isFalse);
    expect(
      (await graph.finance.findCreditCard(tight.id))!.creditLimit,
      const Money(5000),
    );
  });

  test('busca contas pelos items da aplicação, sem item id', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final gateway = _ItemGateway();
    final sync = PluggySync(
      gateway: gateway,
      pluggy: SqlitePluggyRepository(graph.database),
      accounts: graph.accounts,
      finance: graph.finance,
      categories: graph.categories,
      transactions: graph.transactions,
      posting: const TransactionPosting(),
      clock: graph.clock,
      ids: graph.ids,
    );
    await sync.save(
      PluggyConnection(
        userId: user.id,
        clientId: 'client',
        clientSecret: 'secret',
      ),
    );
    final accounts = await sync.fetchAccounts(user.id);
    expect(accounts.single.name, 'Itaú');
    expect(accounts.single.itemId, '11111111-1111-4111-8111-111111111111');
    expect(gateway.requestedItemId, '11111111-1111-4111-8111-111111111111');
  });

  test('reaproveita item ids do painel sem novo Connect', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    const itemId = '22222222-2222-4222-8222-222222222222';
    final gateway = _ItemGateway()..fixedItemId = itemId;
    final sync = PluggySync(
      gateway: gateway,
      pluggy: SqlitePluggyRepository(graph.database),
      accounts: graph.accounts,
      finance: graph.finance,
      categories: graph.categories,
      transactions: graph.transactions,
      posting: const TransactionPosting(),
      clock: graph.clock,
      ids: graph.ids,
    );
    await sync.save(
      PluggyConnection(
        userId: user.id,
        clientId: 'client',
        clientSecret: 'secret',
      ),
    );
    expect(
      await sync.rememberItemIds(user.id, [
        itemId,
        'nao-e-uuid',
        '  $itemId  ',
      ]),
      1,
    );
    final accounts = await sync.fetchAccounts(user.id);
    expect(accounts.single.name, 'Itaú');
    expect(gateway.requestedItemId, itemId);
  });

  test('desliga Open Finance e mantém a conta local', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    const itemId = '11111111-1111-4111-8111-111111111111';
    final pluggy = SqlitePluggyRepository(graph.database);
    final sync = PluggySync(
      gateway: _ItemGateway(),
      pluggy: pluggy,
      accounts: graph.accounts,
      finance: graph.finance,
      categories: graph.categories,
      transactions: graph.transactions,
      posting: const TransactionPosting(),
      clock: graph.clock,
      ids: graph.ids,
    );
    await sync.save(
      PluggyConnection(
        userId: user.id,
        clientId: 'client',
        clientSecret: 'secret',
        itemId: itemId,
      ),
    );
    await sync.saveAccountLink(
      userId: user.id,
      link: PluggyAccountLink(
        pluggyAccountId: 'acc',
        userId: user.id,
        name: 'Itaú',
        kind: 'BANK',
        itemId: itemId,
        accountId: account.id,
      ),
    );
    await pluggy.rememberItem(
      const PluggyItem(id: 'not-a-uuid', connectorName: 'Lixo'),
      user.id,
      DateTime.utc(2026, 10, 6),
    );
    expect((await sync.bankConnections(user.id)).single.links.single.isLinked, isTrue);
    await sync.disconnectItem(user.id, itemId);
    expect(await sync.bankConnections(user.id), isEmpty);
    expect(await sync.links(user.id), isEmpty);
    expect((await graph.accounts.findById(account.id))?.name, 'Corrente');
  });
}

class _Gateway implements PluggyGateway {
  @override
  Future<PluggyItemListing> listItems({
    required String clientId,
    required String clientSecret,
  }) async {
    return const PluggyItemListing(items: [], listingEnabled: true);
  }

  @override
  Future<String> connectToken({
    required String clientId,
    required String clientSecret,
    required String clientUserId,
  }) async {
    return 'token';
  }

  @override
  Future<List<PluggyRemoteAccount>> accounts({
    required String clientId,
    required String clientSecret,
    required String itemId,
  }) async {
    return const [];
  }

  @override
  Future<List<PluggyRemoteTransaction>> transactions({
    required String clientId,
    required String clientSecret,
    required String accountId,
    required DateTime from,
    required DateTime to,
  }) async {
    if (accountId == 'card') {
      return const [
        PluggyRemoteTransaction(
          id: 'compra',
          accountId: 'card',
          description: 'Mercado',
          date: LocalDate(2026, 10, 2),
          amount: Money(3000),
          type: 'DEBIT',
          status: 'POSTED',
        ),
        PluggyRemoteTransaction(
          id: 'fatura',
          accountId: 'card',
          description: 'Pagamento',
          date: LocalDate(2026, 10, 3),
          amount: Money(-4000),
          type: 'CREDIT',
          status: 'POSTED',
        ),
      ];
    }
    return const [
      PluggyRemoteTransaction(
        id: 'mercado',
        accountId: 'bank',
        description: 'Padaria',
        date: LocalDate(2026, 10, 1),
        amount: Money(-2000),
        type: 'DEBIT',
        status: 'POSTED',
      ),
      PluggyRemoteTransaction(
        id: 'salario',
        accountId: 'bank',
        description: 'Salário',
        date: LocalDate(2026, 10, 4),
        amount: Money(5000),
        type: 'CREDIT',
        status: 'POSTED',
      ),
      PluggyRemoteTransaction(
        id: 'aporte',
        accountId: 'bank',
        description: 'CDB',
        date: LocalDate(2026, 10, 5),
        amount: Money(-1000),
        type: 'DEBIT',
        status: 'POSTED',
        operationType: 'APLICACAO',
      ),
    ];
  }
}

class _ItemGateway implements PluggyGateway {
  String? requestedItemId;
  String? fixedItemId;
  var _list = true;

  @override
  Future<PluggyItemListing> listItems({
    required String clientId,
    required String clientSecret,
  }) async {
    if (fixedItemId != null) {
      return const PluggyItemListing(items: [], listingEnabled: false);
    }
    if (!_list) return const PluggyItemListing(items: [], listingEnabled: true);
    _list = false;
    return const PluggyItemListing(
      items: [
        PluggyItem(
          id: '11111111-1111-4111-8111-111111111111',
          connectorName: 'Itaú',
          status: 'UPDATED',
        ),
      ],
      listingEnabled: true,
    );
  }

  @override
  Future<String> connectToken({
    required String clientId,
    required String clientSecret,
    required String clientUserId,
  }) async {
    return 'token';
  }

  @override
  Future<List<PluggyRemoteAccount>> accounts({
    required String clientId,
    required String clientSecret,
    required String itemId,
  }) async {
    requestedItemId = itemId;
    return [
      PluggyRemoteAccount(
        id: 'acc',
        name: 'Itaú',
        kind: 'BANK',
        itemId: itemId,
      ),
    ];
  }

  @override
  Future<List<PluggyRemoteTransaction>> transactions({
    required String clientId,
    required String clientSecret,
    required String accountId,
    required DateTime from,
    required DateTime to,
  }) async {
    return const [];
  }
}

class _CategorizedGateway implements PluggyGateway {
  @override
  Future<PluggyItemListing> listItems({
    required String clientId,
    required String clientSecret,
  }) async {
    return const PluggyItemListing(items: [], listingEnabled: true);
  }

  @override
  Future<String> connectToken({
    required String clientId,
    required String clientSecret,
    required String clientUserId,
  }) async {
    return 'token';
  }

  @override
  Future<List<PluggyRemoteAccount>> accounts({
    required String clientId,
    required String clientSecret,
    required String itemId,
  }) async {
    return const [];
  }

  @override
  Future<List<PluggyRemoteTransaction>> transactions({
    required String clientId,
    required String clientSecret,
    required String accountId,
    required DateTime from,
    required DateTime to,
  }) async {
    return const [
      PluggyRemoteTransaction(
        id: 'mercado',
        accountId: 'bank',
        description: 'Padaria',
        date: LocalDate(2026, 10, 1),
        amount: Money(-2000),
        type: 'DEBIT',
        status: 'POSTED',
      ),
      PluggyRemoteTransaction(
        id: 'feira',
        accountId: 'bank',
        description: 'Hortifruti',
        date: LocalDate(2026, 10, 2),
        amount: Money(-1500),
        type: 'DEBIT',
        status: 'POSTED',
        category: 'Groceries',
      ),
    ];
  }
}
