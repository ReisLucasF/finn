import 'dart:convert';
import 'dart:typed_data';

import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_graph.dart';

void main() {
  test(
    'salvar de novo uma despesa paga com investimento credita a conta',
    () async {
      final graph = await openTestGraph();
      final user = await graph.bootstrap();
      final account = await graph.createAccount(
        userId: user.id,
        name: 'Mercado Pago',
        type: AccountType.checking,
      );
      final categories = await graph.listCategories(user.id);
      final education = categories.firstWhere((c) => c.name == 'Educação');
      final expense = await graph.createTransaction(
        userId: user.id,
        type: TransactionType.expense,
        amount: const Money(16717),
        transactionDate: const LocalDate(2026, 10, 10),
        accountId: account.id,
        categoryId: education.id,
        description: 'Faculdade',
        fundFromInvestment: true,
        investmentProductLabel: 'Reserva ML',
      );
      // Despesa paga com investimento não mexe no saldo da conta.
      expect(await graph.calculateAccountBalance(account.id), Money.zero);

      // Simula um par criado pela versão anterior: resgate sem crédito.
      final db = await graph.database.open();
      final pairId = (await graph.transactions.findById(expense.id))!
          .pairedTransactionId!;
      await db.delete(
        'transaction_entries',
        where: 'transaction_id = ?',
        whereArgs: [pairId],
      );
      expect(
        await graph.calculateAccountBalance(account.id),
        const Money(-16717),
      );

      // Abrir e salvar a despesa recria o crédito do resgate.
      await graph.updateTransaction(
        id: expense.id,
        type: TransactionType.expense,
        amount: const Money(16717),
        transactionDate: const LocalDate(2026, 10, 10),
        accountId: account.id,
        categoryId: education.id,
        status: TransactionStatus.confirmed,
        description: 'Faculdade',
        fundFromInvestment: true,
      );
      expect(await graph.calculateAccountBalance(account.id), Money.zero);

      // Extrato com o resgate do banco: reconhecido como a retirada pareada,
      // não entra de novo (senão creditaria em dobro).
      final analysis = await graph.analyzeOfx(
        userId: user.id,
        accountId: account.id,
        bytes: Uint8List.fromList(
          utf8.encode('''
OFXHEADER:100
<OFX>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261010
<TRNAMT>167.17
<FITID>mp-1
<NAME>Dinheiro retirado Reserva ML
</STMTTRN>
</OFX>
'''),
        ),
        fileName: 'mercadopago.ofx',
      );
      final line = analysis.lines.single;
      expect(line.duplicateBand, DuplicateBand.veryLikely);
      expect(line.importByDefault, isFalse);
    },
  );
}
