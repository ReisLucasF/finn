import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';
import 'package:finan/domain/services/pluggy_category_matcher.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/pluggy/pluggy_item_id.dart';
import 'package:finan/domain/pluggy/pluggy_models.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/repositories/pluggy_connect.dart';
import 'package:finan/domain/repositories/pluggy_gateway.dart';
import 'package:finan/domain/repositories/pluggy_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/pluggy_classifier.dart';
import 'package:finan/domain/services/transaction_posting.dart';

class PluggySync {
  const PluggySync({
    required PluggyGateway gateway,
    required PluggyRepository pluggy,
    required AccountRepository accounts,
    required FinanceRepository finance,
    required CategoryRepository categories,
    required TransactionRepository transactions,
    required TransactionPosting posting,
    required Clock clock,
    required IdGenerator ids,
    PluggyConnect connect = const IdlePluggyConnect(),
    this.classifier = const PluggyClassifier(),
    this.matcher = const PluggyCategoryMatcher(),
    this.lookbackDays = 90,
  }) : _gateway = gateway,
       _pluggy = pluggy,
       _accounts = accounts,
       _finance = finance,
       _categories = categories,
       _transactions = transactions,
       _posting = posting,
       _clock = clock,
       _ids = ids,
       _connect = connect;

  final PluggyGateway _gateway;
  final PluggyRepository _pluggy;
  final AccountRepository _accounts;
  final FinanceRepository _finance;
  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final TransactionPosting _posting;
  final Clock _clock;
  final IdGenerator _ids;
  final PluggyConnect _connect;
  final PluggyClassifier classifier;
  final PluggyCategoryMatcher matcher;
  final int lookbackDays;

  Future<PluggyConnection?> connection(String userId) => _pluggy.find(userId);

  Future<void> save(PluggyConnection connection) async {
    _requireCredentials(connection);
    await _pluggy.purgeInvalidItems(connection.userId);
    final current = await _pluggy.find(connection.userId);
    final candidate = connection.itemId.trim().isNotEmpty
        ? connection.itemId.trim()
        : (current?.itemId.trim() ?? '');
    final kept = isPluggyItemId(candidate) ? candidate : '';
    if (kept.isNotEmpty) {
      await _pluggy.rememberItem(
        PluggyItem(id: kept, connectorName: 'Conexão'),
        connection.userId,
        _clock.nowUtc(),
      );
    }
    await _pluggy.save(
      PluggyConnection(
        userId: connection.userId,
        clientId: connection.clientId.trim(),
        clientSecret: connection.clientSecret.trim(),
        itemId: kept,
      ),
      _clock.nowUtc(),
    );
  }

  /// Liga um banco no Pluggy Connect. No Meu Pluggy, cada banco precisa de
  /// uma autorização. Devolve aviso quando o banco já existia.
  Future<String?> connectBank(String userId) async {
    final connection = await _require(userId);
    final token = await _gateway.connectToken(
      clientId: connection.clientId,
      clientSecret: connection.clientSecret,
      clientUserId: userId,
    );
    final before = {for (final item in await _pluggy.items(userId)) item.id};
    final items = await _connect.open(connectToken: token);
    if (items.isEmpty) {
      throw const ValidationException(
        'A conexão não foi concluída. Se o banco já existia no painel, use '
        '«Informar itens do painel» com os item ids. No Meu Pluggy, cada banco '
        'precisa de uma autorização separada na aplicação.',
      );
    }
    final now = _clock.nowUtc();
    for (final item in items) {
      await _pluggy.rememberItem(item, userId, now);
    }
    final added = items.any((item) => !before.contains(item.id));
    if (!added) {
      return 'Esse banco já estava na aplicação. As contas dele podem ser '
          'buscadas. Para os outros bancos do Meu Pluggy, conecte de novo e '
          'escolha outro banco depois do Continuar.';
    }
    return null;
  }

  /// Reaproveita itens que já existem no Dashboard (Connected Items).
  Future<int> rememberItemIds(
    String userId,
    Iterable<String> rawIds, {
    String connectorName = 'MeuPluggy',
  }) async {
    await _require(userId);
    final ids = <String>{
      for (final raw in rawIds)
        for (final part in raw.split(RegExp(r'[\s,;]+')))
          if (isPluggyItemId(part)) part.trim(),
    };
    if (ids.isEmpty) {
      throw const ValidationException(
        'Informe ao menos um item id válido (UUID do painel do Pluggy).',
      );
    }
    final now = _clock.nowUtc();
    for (final id in ids) {
      await _pluggy.rememberItem(
        PluggyItem(id: id, connectorName: connectorName),
        userId,
        now,
      );
    }
    return ids.length;
  }

  void cancelConnect() => _connect.cancel();

  Future<List<PluggyBankConnection>> bankConnections(String userId) async {
    await _pluggy.purgeInvalidItems(userId);
    final items = await _pluggy.items(userId);
    final links = await _pluggy.links(userId);
    final orphans = [
      for (final link in links)
        if (link.itemId == null && link.isLinked) link,
    ];
    return [
      for (final item in items)
        PluggyBankConnection(
          item: item,
          links: [
            for (final link in links)
              if (link.itemId == item.id) link,
            if (items.length == 1) ...orphans,
          ],
        ),
    ];
  }

  /// Remove a sincronização Open Finance. Conta, cartão e lançamentos locais ficam.
  Future<void> disconnectItem(String userId, String itemId) async {
    if (!isPluggyItemId(itemId)) {
      throw const ValidationException('Conexão inválida.');
    }
    final connection = await _require(userId);
    final remoteIds = <String>{};
    try {
      final accounts = await _gateway.accounts(
        clientId: connection.clientId,
        clientSecret: connection.clientSecret,
        itemId: itemId,
      );
      for (final account in accounts) {
        remoteIds.add(account.id);
      }
    } catch (_) {}
    await _pluggy.deleteLinksForItem(itemId, userId);
    for (final link in await _pluggy.links(userId)) {
      if (remoteIds.contains(link.pluggyAccountId)) {
        await _pluggy.deleteLink(link.pluggyAccountId, userId);
      }
    }
    await _pluggy.forgetItem(itemId, userId);
  }

  Future<void> unlinkAccount(String userId, String pluggyAccountId) async {
    final id = pluggyAccountId.trim();
    if (id.isEmpty) {
      throw const ValidationException('Conta remota inválida.');
    }
    await _pluggy.deleteLink(id, userId);
  }

  Future<List<PluggyRemoteAccount>> fetchAccounts(String userId) async {
    final connection = await _require(userId);
    await _pluggy.purgeInvalidItems(userId);
    final listing = await _gateway.listItems(
      clientId: connection.clientId,
      clientSecret: connection.clientSecret,
    );
    final now = _clock.nowUtc();
    for (final item in listing.items) {
      await _pluggy.rememberItem(item, userId, now);
    }
    final known = await _pluggy.items(userId);
    if (known.isEmpty) {
      throw const ValidationException(
        'Nenhuma conexão bancária. Use Conectar banco e, no Meu Pluggy, autorize cada banco uma vez.',
      );
    }
    final accounts = <PluggyRemoteAccount>[];
    Object? failure;
    for (final item in known) {
      try {
        accounts.addAll(
          await _gateway.accounts(
            clientId: connection.clientId,
            clientSecret: connection.clientSecret,
            itemId: item.id,
          ),
        );
      } catch (error) {
        failure = error;
      }
    }
    if (accounts.isEmpty && failure != null) throw failure;
    final existing = {
      for (final link in await _pluggy.links(userId)) link.pluggyAccountId: link,
    };
    for (final account in accounts) {
      final link = existing[account.id];
      if (link == null || link.itemId == account.itemId) continue;
      await _pluggy.saveLink(
        PluggyAccountLink(
          pluggyAccountId: link.pluggyAccountId,
          userId: link.userId,
          name: link.name,
          kind: link.kind,
          itemId: account.itemId,
          accountId: link.accountId,
          creditCardId: link.creditCardId,
        ),
      );
    }
    return accounts;
  }

  Future<void> rememberLink(PluggyAccountLink link) => _pluggy.saveLink(link);

  Future<void> saveCategoryLink({
    required String userId,
    required String pluggyCategory,
    required String? categoryId,
  }) {
    final name = pluggyCategory.trim();
    if (name.isEmpty) {
      throw const ValidationException('Informe a categoria do Pluggy.');
    }
    return _pluggy.saveCategoryLink(
      userId: userId,
      pluggyCategory: name,
      categoryId: categoryId,
    );
  }

  /// Grava o vínculo e, no cartão, o limite vindo do Pluggy.
  /// Devolve falso quando o limite do Pluggy é menor que o uso inicial.
  Future<bool> saveAccountLink({
    required String userId,
    required PluggyAccountLink link,
    PluggyRemoteAccount? remote,
  }) async {
    final itemId = link.itemId ?? remote?.itemId;
    await _pluggy.saveLink(
      PluggyAccountLink(
        pluggyAccountId: link.pluggyAccountId,
        userId: link.userId,
        name: link.name,
        kind: link.kind,
        itemId: itemId,
        accountId: link.accountId,
        creditCardId: link.creditCardId,
      ),
    );
    final limit = remote?.creditLimit;
    final cardId = link.creditCardId;
    if (limit == null || cardId == null) return true;
    final card = await _finance.findCreditCard(cardId);
    if (card == null || card.userId != userId || card.isDeleted) {
      throw const ValidationException('Cartão inválido.');
    }
    if (limit.cents < card.initialUsedLimit.cents) return false;
    await _finance.applyCreditCardProfile(
      userId: userId,
      cardId: cardId,
      creditLimit: limit,
      updatedAt: _clock.nowUtc(),
      brand: remote?.brand,
      lastFourDigits: remote?.lastFourDigits,
      closingDay: remote?.closingDay,
      dueDay: remote?.dueDay,
    );
    return true;
  }

  Future<List<PluggyAccountLink>> links(String userId) => _pluggy.links(userId);

  Future<List<PluggyReviewLine>> preview({
    required String userId,
    required List<PluggyAccountLink> links,
  }) async {
    final connection = await _require(userId);
    final today = _clock.today();
    final from = today.addDays(-lookbackDays);
    final categories = await _categories.listByUser(
      userId,
      includeInactive: false,
    );
    final savedLinks = await _pluggy.categoryLinks(userId);
    final batch = <({PluggyAccountLink link, PluggyRemoteTransaction item, bool known})>[];
    for (final link in links) {
      if (link.accountId == null && link.creditCardId == null) continue;
      final remote = await _gateway.transactions(
        clientId: connection.clientId,
        clientSecret: connection.clientSecret,
        accountId: link.pluggyAccountId,
        from: DateTime.utc(from.year, from.month, from.day),
        to: DateTime.utc(today.year, today.month, today.day),
      );
      final known = await _transactions.existingExternalIds(
        userId,
        [for (final item in remote) item.externalId],
      );
      for (final item in remote) {
        batch.add((
          link: link,
          item: item,
          known: known.contains(item.externalId),
        ));
      }
    }
    batch.sort((a, b) => b.item.date.compareTo(a.item.date));
    final used = <String>{};
    final lines = <PluggyReviewLine>[];
    for (final row in batch) {
      final item = row.item;
      final link = row.link;
      final posting = classifier.classify(
        accountKind: link.kind,
        movementType: item.type,
        amount: item.amount,
        status: item.status,
        operationType: item.operationType,
      );
      final match = row.known
          ? null
          : await _match(
              userId: userId,
              link: link,
              item: item,
              posting: posting,
              used: used,
            );
      if (match != null) used.add(match.transaction.id);
      lines.add(
        PluggyReviewLine(
          remoteId: item.id,
          externalId: item.externalId,
          description: item.description,
          date: item.date,
          absoluteAmount: Money(item.amount.cents.abs()),
          posting: posting,
          alreadyImported: row.known,
          pluggyAccountId: link.pluggyAccountId,
          accountId: link.accountId,
          creditCardId: link.creditCardId,
          pluggyCategory: item.category,
          categoryId: _categoryId(
            posting: posting,
            pluggyCategory: item.category,
            categories: categories,
            saved: savedLinks,
          ),
          matchTransactionId: match?.transaction.id,
          matchDescription: match?.transaction.description,
          namesSimilar: match?.namesSimilar ?? false,
        ),
      );
    }
    return lines;
  }

  Future<PluggyImportResult> import({
    required String userId,
    required List<PluggyReviewLine> lines,
    Set<String> reconcileIds = const {},
  }) async {
    final selected = [
      for (final line in lines)
        if (line.canImport) line,
    ];
    if (selected.isEmpty) {
      return const PluggyImportResult(imported: 0, reconciled: 0);
    }
    final known = await _transactions.existingExternalIds(
      userId,
      [for (final line in selected) line.externalId],
    );
    final now = _clock.nowUtc();
    final transactions = <Transaction>[];
    final entries = <TransactionEntry>[];
    var reconciled = 0;
    for (final line in selected) {
      if (known.contains(line.externalId)) continue;
      if (reconcileIds.contains(line.remoteId) && line.matchTransactionId != null) {
        final linked = await _reconcile(userId, line, now);
        if (linked) {
          reconciled++;
          known.add(line.externalId);
        }
        continue;
      }
      final shaped = await _shape(userId, line);
      final id = _ids.next();
      transactions.add(
        Transaction(
          id: id,
          userId: userId,
          type: shaped.type,
          amount: line.absoluteAmount,
          description: line.description,
          transactionDate: line.date,
          competenceDate: line.date,
          status: TransactionStatus.confirmed,
          accountId: shaped.accountId,
          creditCardId: shaped.creditCardId,
          categoryId: shaped.categoryId,
          source: TransactionSource.pluggy,
          externalId: line.externalId,
          reconciledAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
      entries.add(shaped.entry(id, now, _ids.next(), line.absoluteAmount));
      known.add(line.externalId);
    }
    if (transactions.isNotEmpty) {
      await _transactions.insertMany(transactions, entries);
    }
    return PluggyImportResult(
      imported: transactions.length,
      reconciled: reconciled,
    );
  }

  Future<PluggyConnection> _require(String userId) async {
    final connection = await _pluggy.find(userId);
    if (connection == null) {
      throw const ValidationException('Informe a conexão do Meu Pluggy.');
    }
    _requireCredentials(connection);
    return connection;
  }

  void _requireCredentials(PluggyConnection connection) {
    if (connection.clientId.trim().isEmpty ||
        connection.clientSecret.trim().isEmpty) {
      throw const ValidationException('Preencha o client id e o client secret.');
    }
  }

  String? _categoryId({
    required PluggyPosting posting,
    required String? pluggyCategory,
    required List<Category> categories,
    required Map<String, String?> saved,
  }) {
    final name = pluggyCategory?.trim();
    if (name == null || name.isEmpty) return null;
    final type = switch (posting) {
      PluggyPosting.bankIncome => TransactionType.income,
      PluggyPosting.bankExpense ||
      PluggyPosting.cardExpense => TransactionType.expense,
      _ => null,
    };
    if (type == null) return null;
    if (saved.containsKey(name)) {
      final savedId = saved[name];
      if (savedId == null) return null;
      for (final category in categories) {
        if (category.id == savedId && category.type.accepts(type)) {
          return savedId;
        }
      }
      return null;
    }
    return matcher.match(
      pluggyCategory: name,
      categories: categories,
      type: type,
    );
  }

  Future<_Match?> _match({
    required String userId,
    required PluggyAccountLink link,
    required PluggyRemoteTransaction item,
    required PluggyPosting posting,
    required Set<String> used,
  }) async {
    if (posting == PluggyPosting.cardBill ||
        posting == PluggyPosting.pending ||
        posting == PluggyPosting.ignored) {
      return null;
    }
    final candidates = await _transactions.findReconciliationCandidates(
      userId: userId,
      accountId: link.accountId ?? '',
      absoluteAmount: Money(item.amount.cents.abs()),
      date: item.date,
      externalId: item.externalId,
    );
    final incoming = normalizeDescription(item.description);
    Transaction? best;
    var bestSimilar = false;
    var bestDistance = 1 << 30;
    for (final candidate in candidates) {
      if (used.contains(candidate.id)) continue;
      if (candidate.externalId != null) continue;
      if (candidate.status != TransactionStatus.confirmed) continue;
      if (candidate.deletedAt != null) continue;
      if (!_samePlace(candidate, link)) continue;
      if (!_typeFits(candidate, posting)) continue;
      final similar = descriptionsAreSimilar(
        incoming,
        normalizeDescription(candidate.description ?? ''),
      );
      final distance = _days(candidate.transactionDate, item.date);
      final better =
          best == null ||
          (similar && !bestSimilar) ||
          (similar == bestSimilar && distance < bestDistance);
      if (!better) continue;
      best = candidate;
      bestSimilar = similar;
      bestDistance = distance;
    }
    if (best == null) return null;
    return _Match(best, namesSimilar: bestSimilar);
  }

  bool _samePlace(Transaction candidate, PluggyAccountLink link) {
    final cardId = link.creditCardId;
    if (cardId != null) return candidate.creditCardId == cardId;
    return candidate.accountId == link.accountId && candidate.creditCardId == null;
  }

  bool _typeFits(Transaction candidate, PluggyPosting posting) {
    return switch (posting) {
      PluggyPosting.bankIncome => candidate.type == TransactionType.income,
      PluggyPosting.bankExpense => candidate.type == TransactionType.expense,
      PluggyPosting.cardExpense => candidate.type == TransactionType.expense,
      PluggyPosting.investmentApplication =>
        candidate.type == TransactionType.investmentContribution ||
            candidate.type == TransactionType.expense,
      PluggyPosting.investmentRedemption =>
        candidate.type == TransactionType.investmentWithdrawal ||
            candidate.type == TransactionType.income,
      _ => false,
    };
  }

  int _days(LocalDate left, LocalDate right) {
    final start = DateTime.utc(left.year, left.month, left.day);
    final end = DateTime.utc(right.year, right.month, right.day);
    return start.difference(end).inDays.abs();
  }

  Future<bool> _reconcile(
    String userId,
    PluggyReviewLine line,
    DateTime now,
  ) async {
    final existing = await _transactions.findById(line.matchTransactionId!);
    if (existing == null || existing.userId != userId || existing.isDeleted) {
      return false;
    }
    final category = existing.categoryId == null
        ? await _acceptedCategory(
            userId,
            line,
            existing.type,
            card: existing.creditCardId != null,
          )
        : null;
    return _transactions.linkExternalId(
      userId: userId,
      transactionId: existing.id,
      externalId: line.externalId,
      reconciledAt: now,
      categoryId: category?.id,
    );
  }

  Future<Category?> _acceptedCategory(
    String userId,
    PluggyReviewLine line,
    TransactionType type, {
    required bool card,
  }) async {
    final id = line.categoryId;
    if (id == null || id.isEmpty) return null;
    final category = await _categories.findById(id);
    if (category == null || category.deletedAt != null || !category.isActive) {
      return null;
    }
    if (category.userId != null && category.userId != userId) return null;
    if (card &&
        (category.type == CategoryType.investmentApplication ||
            category.type == CategoryType.investmentRedemption)) {
      return null;
    }
    if (!category.type.accepts(type)) return null;
    return category;
  }

  Future<_Shaped> _shape(String userId, PluggyReviewLine line) async {
    final accountId = line.accountId;
    final cardId = line.creditCardId;
    if (line.posting == PluggyPosting.cardExpense) {
      final card = cardId == null ? null : await _finance.findCreditCard(cardId);
      if (card == null || card.isDeleted || card.userId != userId) {
        throw const ValidationException('Cartão inválido.');
      }
      return _Shaped.card(
        cardId!,
        categoryId: (await _acceptedCategory(
          userId,
          line,
          TransactionType.expense,
          card: true,
        ))?.id,
      );
    }
    final account = accountId == null
        ? null
        : await _accounts.findById(accountId);
    if (account == null || account.isDeleted || account.userId != userId) {
      throw const ValidationException('Conta inválida.');
    }
    if (!account.isActive) {
      throw const ValidationException('A conta está desativada.');
    }
    final investment = switch (line.posting) {
      PluggyPosting.investmentApplication => CategoryType.investmentApplication,
      PluggyPosting.investmentRedemption => CategoryType.investmentRedemption,
      _ => null,
    };
    if (investment != null) {
      final categoryId = investment == CategoryType.investmentApplication
          ? _applicationCategory
          : _redemptionCategory;
      final category = await _categories.findById(categoryId);
      if (category != null && category.type == investment) {
        final stored = category.type.storedType(
          investment == CategoryType.investmentApplication
              ? TransactionType.expense
              : TransactionType.income,
        );
        final entryType = stored == TransactionType.investmentContribution
            ? TransactionType.expense
            : TransactionType.income;
        return _Shaped.account(
          accountId: account.id,
          type: stored,
          categoryId: category.id,
          entryType: entryType,
          posting: _posting,
        );
      }
    }
    final income = line.posting == PluggyPosting.bankIncome;
    final requested = income ? TransactionType.income : TransactionType.expense;
    final category = await _acceptedCategory(
      userId,
      line,
      requested,
      card: false,
    );
    if (category != null &&
        (category.type == CategoryType.investmentApplication ||
            category.type == CategoryType.investmentRedemption)) {
      final stored = category.type.storedType(requested);
      final entryType = stored == TransactionType.investmentContribution
          ? TransactionType.expense
          : TransactionType.income;
      return _Shaped.account(
        accountId: account.id,
        type: stored,
        categoryId: category.id,
        entryType: entryType,
        posting: _posting,
      );
    }
    return _Shaped.account(
      accountId: account.id,
      type: requested,
      categoryId: category?.id,
      entryType: requested,
      posting: _posting,
    );
  }
}

class _Match {
  const _Match(this.transaction, {required this.namesSimilar});

  final Transaction transaction;
  final bool namesSimilar;
}

const _applicationCategory = '019a0000-0000-7000-8000-000000000013';
const _redemptionCategory = '019a0000-0000-7000-8000-000000000014';

class _Shaped {
  _Shaped.account({
    required this.accountId,
    required this.type,
    required this.entryType,
    required TransactionPosting posting,
    this.categoryId,
  }) : creditCardId = null,
       _posting = posting,
       _card = false;

  _Shaped.card(String cardId, {this.categoryId})
    : accountId = null,
      creditCardId = cardId,
      type = TransactionType.expense,
      entryType = TransactionType.expense,
      _posting = null,
      _card = true;

  final String? accountId;
  final String? creditCardId;
  final TransactionType type;
  final String? categoryId;
  final TransactionType entryType;
  final TransactionPosting? _posting;
  final bool _card;

  TransactionEntry entry(
    String transactionId,
    DateTime createdAt,
    String entryId,
    Money amount,
  ) {
    if (_card) {
      return TransactionEntry(
        id: entryId,
        transactionId: transactionId,
        creditCardId: creditCardId,
        amount: amount,
        createdAt: createdAt,
      );
    }
    return _posting!
        .forAccount(
          entryId: entryId,
          transactionId: transactionId,
          accountId: accountId!,
          type: entryType,
          amount: amount,
          createdAt: createdAt,
        )
        .single;
  }
}
