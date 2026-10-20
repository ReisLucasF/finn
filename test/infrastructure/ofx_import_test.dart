import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/database_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/ofx_repository.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/apply_migrations.dart';
import 'package:finan/infrastructure/database/sqlite/migrations/migration_001_initial.dart';
import 'package:finan/infrastructure/ofx/ofx_statement_parser.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_ofx_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide DatabaseException, Transaction;

import '../support/test_graph.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = OfxStatementParser();

  test('parser lê SGML, preserva o dia e ignora valor zero', () {
    final items = parser.parse('''
OFXHEADER:100
<OFX>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261006120000[-3:BRT]
<TRNAMT>-25.50
<FITID>abc-1
<NAME>UBER *TRIP
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261005
<TRNAMT>0.00
<FITID>zero
<NAME>NADA
</STMTTRN>
<CCSTMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261005
<TRNAMT>1500,00
<FITID>abc-2
<NAME>PIX TRANSF.  JOAO DA SILVA
</CCSTMTTRN>
</OFX>
''');
    expect(items, hasLength(2));
    expect(items.first.postedDate, const LocalDate(2026, 10, 6));
    expect(items.first.signedAmount.cents, -2550);
    expect(items.last.postedDate, const LocalDate(2026, 10, 5));
    expect(items.last.signedAmount.cents, 150000);
  });

  test('importação altera o saldo e a segunda leitura não duplica', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final checking = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(10000),
    );
    final savings = await graph.createAccount(
      userId: user.id,
      name: 'Poupança',
      type: AccountType.savings,
    );
    final transport = await _category(graph, user.id, 'Transporte');
    final salary = await _category(graph, user.id, 'Salário');
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(2550),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: savings.id,
      categoryId: transport.id,
      description: 'UBER TRIP',
    );
    final bytes = utf8.encode(_statement);

    final analysis = await graph.analyzeOfx(
      userId: user.id,
      accountId: checking.id,
      bytes: Uint8List.fromList(bytes),
      fileName: 'extrato.ofx',
    );
    expect(analysis.lines, hasLength(2));
    final uber = analysis.lines.first;
    final pix = analysis.lines.last;
    expect(uber.type, TransactionType.expense);
    expect(uber.suggestion?.categoryId, transport.id);
    expect(uber.possibleTransfer?.accountId, savings.id);
    expect(uber.importByDefault, isTrue);
    expect(pix.normalizedDescription, 'pix transf joao da silva');

    final imported = await graph.importOfx(
      userId: user.id,
      analysis: analysis,
      decisions: [
        OfxImportDecision(
          lineId: uber.id,
          import: true,
          categoryId: transport.id,
        ),
        OfxImportDecision(
          lineId: pix.id,
          import: true,
          categoryId: salary.id,
        ),
      ],
    );
    expect(imported.imported, 2);
    expect(
      await graph.calculateAccountBalance(checking.id),
      const Money(10000 - 2550 + 150000),
    );
    final page = await graph.listTransactions(userId: user.id);
    final ofxRows = page.items.where(
      (item) => item.source == TransactionSource.ofx,
    );
    expect(ofxRows, hasLength(2));
    expect(ofxRows.every((item) => item.status == TransactionStatus.confirmed), isTrue);

    final again = await graph.analyzeOfx(
      userId: user.id,
      accountId: checking.id,
      bytes: Uint8List.fromList(bytes),
      fileName: 'extrato.ofx',
    );
    expect(again.lines.every((line) => line.duplicateScore >= 0.95), isTrue);
    expect(again.lines.every((line) => line.importByDefault), isFalse);

    final skipped = await graph.importOfx(
      userId: user.id,
      analysis: again,
      decisions: [
        for (final line in again.lines)
          OfxImportDecision(lineId: line.id, import: line.importByDefault),
      ],
    );
    expect(skipped.imported, 0);
    expect(
      await graph.calculateAccountBalance(checking.id),
      const Money(10000 - 2550 + 150000),
    );
    final after = await graph.listTransactions(userId: user.id);
    expect(
      after.items.where((item) => item.source == TransactionSource.ofx),
      hasLength(2),
    );
  });

  test('FITID repetido no mesmo arquivo entra uma vez', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final transport = await _category(graph, user.id, 'Transporte');
    final bytes = utf8.encode('''
OFXHEADER:100
<OFX>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261006
<TRNAMT>-10.00
<FITID>same
<NAME>UBER
</STMTTRN>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261006
<TRNAMT>-10.00
<FITID>same
<NAME>UBER
</STMTTRN>
</OFX>
''');
    final analysis = await graph.analyzeOfx(
      userId: user.id,
      accountId: account.id,
      bytes: Uint8List.fromList(bytes),
    );
    expect(analysis.lines.first.importByDefault, isTrue);
    expect(analysis.lines.last.importByDefault, isFalse);
    expect(analysis.lines.last.duplicateScore, greaterThanOrEqualTo(0.95));

    final result = await graph.importOfx(
      userId: user.id,
      analysis: analysis,
      decisions: [
        for (final line in analysis.lines)
          OfxImportDecision(
            lineId: line.id,
            import: true,
            categoryId: transport.id,
          ),
      ],
    );
    expect(result.imported, 1);
    expect(await graph.calculateAccountBalance(account.id), const Money(-1000));
  });

  test('importa lançamento sem categoria', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final bytes = utf8.encode('''
OFXHEADER:100
<OFX>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261006
<TRNAMT>10.00
<FITID>sem-cat
<NAME>PIX
</STMTTRN>
</OFX>
''');
    final analysis = await graph.analyzeOfx(
      userId: user.id,
      accountId: account.id,
      bytes: Uint8List.fromList(bytes),
    );
    final result = await graph.importOfx(
      userId: user.id,
      analysis: analysis,
      decisions: [
        OfxImportDecision(lineId: analysis.lines.single.id, import: true),
      ],
    );
    expect(result.imported, 1);
    expect(await graph.calculateAccountBalance(account.id), const Money(1000));
    final page = await graph.listTransactions(userId: user.id);
    expect(page.items.single.categoryId, isNull);
  });

  test('transferência no OFX ignora o outro lado', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final checking = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(50000),
    );
    final savings = await graph.createAccount(
      userId: user.id,
      name: 'Poupança',
      type: AccountType.savings,
      initialBalance: const Money(20000),
    );
    final salary = await _category(graph, user.id, 'Salário');
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(10000),
      transactionDate: const LocalDate(2026, 10, 6),
      accountId: savings.id,
      categoryId: salary.id,
      description: 'TED',
    );
    final outgoing = utf8.encode('''
OFXHEADER:100
<OFX>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261006
<TRNAMT>-100.00
<FITID>ted-out
<NAME>TED
</STMTTRN>
</OFX>
''');
    final analysis = await graph.analyzeOfx(
      userId: user.id,
      accountId: checking.id,
      bytes: Uint8List.fromList(outgoing),
    );
    final line = analysis.lines.single;
    expect(line.possibleTransfer?.accountId, savings.id);
    await graph.importOfx(
      userId: user.id,
      analysis: analysis,
      decisions: [
        OfxImportDecision(
          lineId: line.id,
          import: true,
          transferAccountId: savings.id,
          linkTransactionId: line.possibleTransfer?.transactionId,
        ),
      ],
    );
    expect(await graph.calculateAccountBalance(checking.id), const Money(40000));
    expect(await graph.calculateAccountBalance(savings.id), const Money(30000));
    expect(await _sum(graph, user.id, TransactionType.income), Money.zero);
    expect(await _sum(graph, user.id, TransactionType.expense), Money.zero);

    final incoming = utf8.encode('''
OFXHEADER:100
<OFX>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261007
<TRNAMT>100.00
<FITID>ted-in
<NAME>TED
</STMTTRN>
</OFX>
''');
    final other = await graph.analyzeOfx(
      userId: user.id,
      accountId: savings.id,
      bytes: Uint8List.fromList(incoming),
    );
    expect(other.lines.single.coveredByExistingTransfer, isTrue);
    expect(other.lines.single.importByDefault, isFalse);
    await graph.importOfx(
      userId: user.id,
      analysis: other,
      decisions: [
        OfxImportDecision(
          lineId: other.lines.single.id,
          import: other.lines.single.importByDefault,
        ),
      ],
    );
    expect(await graph.calculateAccountBalance(checking.id), const Money(40000));
    expect(await graph.calculateAccountBalance(savings.id), const Money(30000));
  });

  test('converte par do mesmo dia e não sugere de novo', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final checking = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
      initialBalance: const Money(50000),
    );
    final savings = await graph.createAccount(
      userId: user.id,
      name: 'Poupança',
      type: AccountType.savings,
    );
    final transport = await _category(graph, user.id, 'Transporte');
    final salary = await _category(graph, user.id, 'Salário');
    const day = LocalDate(2026, 10, 6);
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(8000),
      transactionDate: day,
      accountId: checking.id,
      categoryId: transport.id,
      description: 'Saída',
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(8000),
      transactionDate: day,
      accountId: savings.id,
      categoryId: salary.id,
      description: 'Entrada',
    );
    final pair = await graph.transferPairs.find(user.id);
    expect(pair, isNotNull);
    await graph.transferPairs.convert(user.id, pair!);
    expect(await graph.calculateAccountBalance(checking.id), const Money(42000));
    expect(await graph.calculateAccountBalance(savings.id), const Money(8000));
    expect(await _sum(graph, user.id, TransactionType.income), Money.zero);
    expect(await _sum(graph, user.id, TransactionType.expense), Money.zero);
    expect(await graph.transferPairs.find(user.id), isNull);
  });

  test('recusa do par não volta a ser sugerida', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final checking = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final savings = await graph.createAccount(
      userId: user.id,
      name: 'Poupança',
      type: AccountType.savings,
    );
    final transport = await _category(graph, user.id, 'Transporte');
    final salary = await _category(graph, user.id, 'Salário');
    const day = LocalDate(2026, 10, 6);
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.expense,
      amount: const Money(1500),
      transactionDate: day,
      accountId: checking.id,
      categoryId: transport.id,
    );
    await graph.createTransaction(
      userId: user.id,
      type: TransactionType.income,
      amount: const Money(1500),
      transactionDate: day,
      accountId: savings.id,
      categoryId: salary.id,
    );
    final pair = await graph.transferPairs.find(user.id);
    expect(pair, isNotNull);
    await graph.transferPairs.dismiss(user.id, pair!);
    expect(await graph.transferPairs.find(user.id), isNull);
    expect(await _sum(graph, user.id, TransactionType.expense), const Money(1500));
    expect(await _sum(graph, user.id, TransactionType.income), const Money(1500));
  });

  test('falha no meio da gravação desfaz o lote', () async {
    final graph = await openTestGraph();
    final user = await graph.bootstrap();
    final account = await graph.createAccount(
      userId: user.id,
      name: 'Corrente',
      type: AccountType.checking,
    );
    final now = DateTime.utc(2026, 10, 6);
    final repo = SqliteOfxRepository(graph.database);
    await expectLater(
      repo.save(
        OfxImportBundle(
          header: OfxImportHeader(
            id: 'import-1',
            userId: user.id,
            accountId: account.id,
            importedAt: now,
            totalRecords: 1,
            importedRecords: 1,
            duplicateRecords: 0,
            ignoredRecords: 0,
          ),
          lines: [
            OfxImportLineRecord(
              id: 'line-1',
              importId: 'import-1',
              amountCents: -1000,
              duplicateScore: 0,
              duplicateStatus: 'none',
              reconciliationStatus: 'reconciled',
              createdAt: now,
            ),
          ],
          transactions: [
            Transaction(
              id: 'tx-1',
              userId: user.id,
              type: TransactionType.expense,
              amount: const Money(1000),
              transactionDate: const LocalDate(2026, 10, 6),
              status: TransactionStatus.confirmed,
              accountId: 'conta-inexistente',
              source: TransactionSource.ofx,
              createdAt: now,
              updatedAt: now,
            ),
          ],
          entries: [
            TransactionEntry(
              id: 'entry-1',
              transactionId: 'tx-1',
              accountId: account.id,
              amount: const Money(-1000),
              createdAt: now,
            ),
          ],
        ),
      ),
      throwsA(isA<DatabaseException>()),
    );
    final database = await graph.database.open();
    expect(await database.query('ofx_imports'), isEmpty);
    expect(await database.query('transactions'), isEmpty);
  });

  test('atualização da versão 1 para 2 preserva os dados', () async {
    await openTestGraph();
    final filePath = path.join(
      Directory.systemTemp.path,
      'finan_upgrade_${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final created = await databaseFactory.openDatabase(
      filePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: configureDatabase,
        onCreate: (db, version) => Migration001.up(db),
      ),
    );
    await created.insert('users', {
      'id': 'u1',
      'name': 'Ana',
      'currency': 'BRL',
      'locale': 'pt_BR',
      'timezone': 'America/Sao_Paulo',
      'financial_month_start': 1,
      'created_at': '2026-10-06T00:00:00.000Z',
      'updated_at': '2026-10-06T00:00:00.000Z',
    });
    await created.close();

    final upgraded = await databaseFactory.openDatabase(
      filePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: configureDatabase,
        onUpgrade: (db, from, to) => applyMigrations(db, from, to),
      ),
    );
    final users = await upgraded.query('users');
    final tables = await upgraded.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ofx_imports'",
    );
    expect(users.single['name'], 'Ana');
    expect(tables, isNotEmpty);
    await upgraded.close();
    File(filePath).deleteSync();
  });
}

const _statement = '''
OFXHEADER:100
<OFX>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261006120000[-3:BRT]
<TRNAMT>-25.50
<FITID>abc-1
<NAME>UBER *TRIP
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261005
<TRNAMT>1500.00
<FITID>abc-2
<NAME>PIX TRANSF.  JOAO DA SILVA
</STMTTRN>
</OFX>
''';

Future<dynamic> _category(dynamic graph, String userId, String name) async {
  final categories = await graph.listCategories(userId);
  return categories.firstWhere((category) => category.name == name);
}

Future<Money> _sum(dynamic graph, String userId, TransactionType type) {
  return graph.transactions.sumConfirmedAmount(
    userId: userId,
    type: type,
    fromInclusive: const LocalDate(2026, 1, 1),
    toExclusive: const LocalDate(2027, 1, 1),
  );
}

