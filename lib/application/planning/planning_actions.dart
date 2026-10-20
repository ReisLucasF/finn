import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/goal_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/transaction_source.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/enums/recurrence_frequency.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/card_limit_service.dart';
import 'package:finan/domain/services/goal_projection_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:finan/domain/services/investment_position_service.dart';
import 'package:finan/domain/services/recurrence_schedule.dart';
import 'package:finan/domain/services/transaction_posting.dart';
import 'package:finan/domain/services/transaction_rules.dart';

class CreateTransfer {
  const CreateTransfer({
    required FinanceRepository finance,
    required AccountRepository accounts,
    required TransactionRules rules,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _accounts = accounts,
       _rules = rules,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final AccountRepository _accounts;
  final TransactionRules _rules;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String sourceAccountId,
    required String destinationAccountId,
    required Money amount,
    required LocalDate date,
    String? description,
  }) async {
    _rules.validateAmount(amount);
    if (sourceAccountId == destinationAccountId) {
      throw const ValidationException(
        'A conta de origem e a de destino precisam ser diferentes.',
      );
    }
    final source = await _accounts.findById(sourceAccountId);
    final destination = await _accounts.findById(destinationAccountId);
    if (source == null || destination == null) {
      throw const ValidationException('Conta inválida.');
    }
    _rules.validateAccountForCreate(source, userId);
    _rules.validateAccountForCreate(destination, userId);
    final now = _clock.nowUtc();
    final transferId = _ids.next();
    final transactionId = _ids.next();
    final transaction = Transaction(
      id: transactionId,
      userId: userId,
      type: TransactionType.transfer,
      amount: amount,
      description: _text(description) ?? 'Transferência',
      transactionDate: date,
      status: TransactionStatus.confirmed,
      accountId: sourceAccountId,
      transferId: transferId,
      source: TransactionSource.manual,
      createdAt: now,
      updatedAt: now,
    );
    await _finance.saveTransfer(
      id: transferId,
      userId: userId,
      sourceAccountId: sourceAccountId,
      destinationAccountId: destinationAccountId,
      amount: amount,
      date: date,
      description: transaction.description,
      status: TransactionStatus.confirmed.value,
      createdAt: now,
      transaction: transaction,
      entries: [
        TransactionEntry(
          id: _ids.next(),
          transactionId: transactionId,
          accountId: sourceAccountId,
          amount: Money(-amount.cents),
          createdAt: now,
        ),
        TransactionEntry(
          id: _ids.next(),
          transactionId: transactionId,
          accountId: destinationAccountId,
          amount: amount,
          createdAt: now,
        ),
      ],
    );
  }
}

class CreateCreditCard {
  const CreateCreditCard({
    required FinanceRepository finance,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final Clock _clock;
  final IdGenerator _ids;

  Future<CreditCard> call({
    required String userId,
    required String name,
    required Money creditLimit,
    Money initialUsedLimit = Money.zero,
    int? closingDay,
    int? dueDay,
    String? issuer,
    String? lastFourDigits,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe o nome do cartão.');
    }
    if (creditLimit.cents < 0 || initialUsedLimit.cents < 0) {
      throw const ValidationException('O limite não pode ser negativo.');
    }
    if (initialUsedLimit.cents > creditLimit.cents) {
      throw const ValidationException(
        'O limite usado não pode ser maior que o limite.',
      );
    }
    _day(closingDay);
    _day(dueDay);
    final digits = lastFourDigits?.replaceAll(RegExp(r'\D'), '');
    if (digits != null && digits.isNotEmpty && digits.length != 4) {
      throw const ValidationException('Informe os 4 últimos dígitos.');
    }
    final now = _clock.nowUtc();
    final card = CreditCard(
      id: _ids.next(),
      userId: userId,
      name: trimmed,
      issuer: _text(issuer),
      lastFourDigits: digits == null || digits.isEmpty ? null : digits,
      creditLimit: creditLimit,
      initialUsedLimit: initialUsedLimit,
      closingDay: closingDay,
      dueDay: dueDay,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    await _finance.saveCreditCard(card);
    return card;
  }

  void _day(int? day) {
    if (day != null && (day < 1 || day > 31)) {
      throw const ValidationException('O dia precisa estar entre 1 e 31.');
    }
  }
}

class CreateCardPurchase {
  const CreateCardPurchase({
    required FinanceRepository finance,
    required CategoryRepository categories,
    required TransactionRules rules,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _categories = categories,
       _rules = rules,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final CategoryRepository _categories;
  final TransactionRules _rules;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String cardId,
    required String categoryId,
    required Money amount,
    required LocalDate date,
    String? description,
  }) async {
    _rules.validateAmount(amount);
    final card = await _requireCard(userId, cardId);
    if (!card.isActive) {
      throw const ValidationException('O cartão está desativado.');
    }
    final category = await _categories.findById(categoryId);
    if (category == null) {
      throw const ValidationException('Categoria não encontrada.');
    }
    _rules.validateCategory(
      category,
      TransactionType.expense,
      allowInactive: false,
    );
    final now = _clock.nowUtc();
    final transactionId = _ids.next();
    await _finance.saveCardPurchase(
      transaction: Transaction(
        id: transactionId,
        userId: userId,
        type: TransactionType.expense,
        amount: amount,
        description: _text(description) ?? 'Compra no cartão',
        transactionDate: date,
        status: TransactionStatus.confirmed,
        categoryId: categoryId,
        creditCardId: cardId,
        source: TransactionSource.manual,
        createdAt: now,
        updatedAt: now,
      ),
      entry: TransactionEntry(
        id: _ids.next(),
        transactionId: transactionId,
        creditCardId: cardId,
        amount: amount,
        createdAt: now,
      ),
    );
  }

  Future<CreditCard> _requireCard(String userId, String cardId) async {
    final card = await _finance.findCreditCard(cardId);
    if (card == null || card.isDeleted || card.userId != userId) {
      throw const ValidationException('Cartão inválido.');
    }
    return card;
  }
}

class PayCreditCard {
  const PayCreditCard({
    required FinanceRepository finance,
    required AccountRepository accounts,
    required TransactionRules rules,
    required CardLimitService limits,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _accounts = accounts,
       _rules = rules,
       _limits = limits,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final AccountRepository _accounts;
  final TransactionRules _rules;
  final CardLimitService _limits;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String cardId,
    required String accountId,
    required Money amount,
    required LocalDate date,
  }) async {
    _rules.validateAmount(amount);
    final card = await _finance.findCreditCard(cardId);
    if (card == null || card.isDeleted || card.userId != userId) {
      throw const ValidationException('Cartão inválido.');
    }
    final account = await _accounts.findById(accountId);
    if (account == null) throw const ValidationException('Conta inválida.');
    _rules.validateAccountForCreate(account, userId);
    final usage = await _finance.cardUsage(userId);
    final match = usage.where((item) => item.cardId == cardId);
    final used = match.isEmpty
        ? card.initialUsedLimit
        : _limits.used(
            initialUsed: match.first.initialUsed,
            confirmedEntries: match.first.confirmedEntries,
          );
    if (amount.cents > used.cents) {
      throw const ValidationException(
        'O pagamento não pode ser maior que a fatura em aberto.',
      );
    }
    final now = _clock.nowUtc();
    final transactionId = _ids.next();
    await _finance.saveCardPayment(
      transaction: Transaction(
        id: transactionId,
        userId: userId,
        type: TransactionType.creditCardPayment,
        amount: amount,
        description: 'Pagamento ${card.name}',
        transactionDate: date,
        status: TransactionStatus.confirmed,
        accountId: accountId,
        creditCardId: cardId,
        source: TransactionSource.manual,
        createdAt: now,
        updatedAt: now,
      ),
      entries: [
        TransactionEntry(
          id: _ids.next(),
          transactionId: transactionId,
          accountId: accountId,
          amount: Money(-amount.cents),
          createdAt: now,
        ),
        TransactionEntry(
          id: _ids.next(),
          transactionId: transactionId,
          creditCardId: cardId,
          amount: Money(-amount.cents),
          createdAt: now,
        ),
      ],
      statementId: _ids.next(),
      referenceMonth:
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}',
      closingDate: date,
      dueDate: date,
      total: amount,
    );
  }
}

class CreateRecurrence {
  const CreateRecurrence({
    required FinanceRepository finance,
    required AccountRepository accounts,
    required CategoryRepository categories,
    required TransactionRules rules,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _accounts = accounts,
       _categories = categories,
       _rules = rules,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final TransactionRules _rules;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String name,
    required TransactionType type,
    required Money amount,
    required String accountId,
    required String categoryId,
    required RecurrenceFrequency frequency,
    required LocalDate startDate,
    int interval = 1,
    LocalDate? endDate,
  }) async {
    if (type != TransactionType.income && type != TransactionType.expense) {
      throw const ValidationException(
        'A recorrência precisa ser receita ou despesa.',
      );
    }
    _rules.validateAmount(amount);
    if (interval < 1) {
      throw const ValidationException('O intervalo precisa ser maior que zero.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe o nome da recorrência.');
    }
    final account = await _accounts.findById(accountId);
    if (account == null) throw const ValidationException('Conta inválida.');
    _rules.validateAccountForCreate(account, userId);
    final category = await _categories.findById(categoryId);
    if (category == null) {
      throw const ValidationException('Categoria não encontrada.');
    }
    _rules.validateCategory(category, type, allowInactive: false);
    if (endDate != null && endDate < startDate) {
      throw const ValidationException(
        'A data final precisa ser posterior ao início.',
      );
    }
    final now = _clock.nowUtc();
    await _finance.saveRecurrence(
      Recurrence(
        id: _ids.next(),
        userId: userId,
        name: trimmed,
        type: type,
        amount: amount,
        categoryId: categoryId,
        accountId: accountId,
        frequency: frequency,
        intervalValue: interval,
        startDate: startDate,
        nextOccurrence: startDate,
        endDate: endDate,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

class GenerateProvisions {
  const GenerateProvisions({
    required FinanceRepository finance,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final Clock _clock;
  final IdGenerator _ids;

  Future<int> call({
    required String userId,
    required String recurrenceId,
    required LocalDate until,
  }) async {
    final recurrence = await _finance.findRecurrence(recurrenceId);
    if (recurrence == null ||
        recurrence.userId != userId ||
        !recurrence.isActive) {
      throw const ValidationException('Recorrência inválida.');
    }
    final now = _clock.nowUtc();
    final today = _clock.today();
    final provisions = <Provision>[];
    var cursor = recurrence.nextOccurrence;
    while (cursor <= until &&
        (recurrence.endDate == null || cursor <= recurrence.endDate!)) {
      provisions.add(
        Provision(
          id: _ids.next(),
          userId: userId,
          recurrenceId: recurrence.id,
          description: recurrence.name,
          amount: recurrence.amount,
          type: recurrence.type,
          dueDate: cursor,
          status: provisionStatusOn(cursor, today),
          createdAt: now,
          updatedAt: now,
        ),
      );
      cursor = advanceOccurrence(
        cursor,
        recurrence.frequency,
        recurrence.intervalValue,
      );
    }
    await _finance.saveProvisions(
      recurrenceId: recurrence.id,
      nextOccurrence: cursor,
      updatedAt: now,
      provisions: provisions,
    );
    return provisions.length;
  }
}

class SettleProvision {
  const SettleProvision({
    required FinanceRepository finance,
    required TransactionPosting posting,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _posting = posting,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final TransactionPosting _posting;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({required String userId, required String provisionId}) async {
    final provision = await _finance.findProvision(provisionId);
    if (provision == null || provision.userId != userId) {
      throw const ValidationException('Provisionamento inválido.');
    }
    if (!provision.status.isOpen) {
      throw const ValidationException('Esse provisionamento já foi tratado.');
    }
    final recurrence = provision.recurrenceId == null
        ? null
        : await _finance.findRecurrence(provision.recurrenceId!);
    final accountId = recurrence?.accountId;
    final categoryId = recurrence?.categoryId;
    if (accountId == null || categoryId == null) {
      throw const ValidationException(
        'A recorrência não tem conta e categoria para liquidar.',
      );
    }
    if (provision.type != TransactionType.income &&
        provision.type != TransactionType.expense) {
      throw const ValidationException(
        'Só receita e despesa podem ser liquidadas.',
      );
    }
    final now = _clock.nowUtc();
    final transactionId = _ids.next();
    await _finance.settleProvision(
      provisionId: provision.id,
      updatedAt: now,
      transaction: Transaction(
        id: transactionId,
        userId: userId,
        type: provision.type,
        amount: provision.amount,
        description: provision.description,
        transactionDate: provision.dueDate,
        status: TransactionStatus.confirmed,
        accountId: accountId,
        categoryId: categoryId,
        recurrenceId: provision.recurrenceId,
        provisionId: provision.id,
        source: TransactionSource.manual,
        createdAt: now,
        updatedAt: now,
      ),
      entries: _posting.forAccount(
        entryId: _ids.next(),
        transactionId: transactionId,
        accountId: accountId,
        type: provision.type,
        amount: provision.amount,
        createdAt: now,
      ),
    );
  }
}

class CreateInvestment {
  const CreateInvestment({
    required FinanceRepository finance,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final Clock _clock;
  final IdGenerator _ids;

  Future<Investment> call({
    required String userId,
    required String name,
    required InvestmentKind kind,
    String? institution,
    String? accountId,
    String currency = 'BRL',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe o nome do investimento.');
    }
    final now = _clock.nowUtc();
    final investment = Investment(
      id: _ids.next(),
      userId: userId,
      name: trimmed,
      institution: _text(institution),
      accountId: _text(accountId),
      kind: kind,
      currency: currency,
      currentValue: Money.zero,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    await _finance.saveInvestment(investment);
    return investment;
  }
}

class MoveInvestment {
  const MoveInvestment({
    required FinanceRepository finance,
    required AccountRepository accounts,
    required TransactionRules rules,
    required InvestmentPositionService positions,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _accounts = accounts,
       _rules = rules,
       _positions = positions,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final AccountRepository _accounts;
  final TransactionRules _rules;
  final InvestmentPositionService _positions;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String investmentId,
    required InvestmentMovementType movement,
    required Money amount,
    required LocalDate date,
    String? accountId,
    String? description,
  }) async {
    _rules.validateAmount(amount);
    final investment = await _finance.findInvestment(investmentId);
    if (investment == null ||
        investment.isDeleted ||
        investment.userId != userId ||
        !investment.isActive) {
      throw const ValidationException('Investimento inválido.');
    }
    final movesAccount =
        movement == InvestmentMovementType.contribution ||
        movement == InvestmentMovementType.withdrawal;
    if (movesAccount && (accountId == null || accountId.isEmpty)) {
      throw const ValidationException('Escolha a conta da movimentação.');
    }
    if (accountId != null) {
      final account = await _accounts.findById(accountId);
      if (account == null) throw const ValidationException('Conta inválida.');
      _rules.validateAccountForCreate(account, userId);
    }
    final current = _positions.valueOf(await _finance.movementsFor(investmentId));
    final reduces =
        movement == InvestmentMovementType.withdrawal ||
        movement == InvestmentMovementType.loss ||
        movement == InvestmentMovementType.fee;
    if (reduces && amount.cents > current.cents) {
      throw const ValidationException(
        'O valor é maior que a posição do investimento.',
      );
    }
    final next = Money(
      current.cents + (reduces ? -amount.cents : amount.cents),
    );
    final now = _clock.nowUtc();
    final transactionId = _ids.next();
    final type = switch (movement) {
      InvestmentMovementType.contribution =>
        TransactionType.investmentContribution,
      InvestmentMovementType.withdrawal => TransactionType.investmentWithdrawal,
      InvestmentMovementType.income => TransactionType.investmentIncome,
      InvestmentMovementType.loss ||
      InvestmentMovementType.fee => TransactionType.investmentLoss,
    };
    final signed = switch (movement) {
      InvestmentMovementType.contribution ||
      InvestmentMovementType.fee => Money(-amount.cents),
      InvestmentMovementType.withdrawal => amount,
      InvestmentMovementType.income || InvestmentMovementType.loss => null,
    };
    await _finance.saveInvestmentMovement(
      movement: InvestmentMovementDraft(
        id: _ids.next(),
        investmentId: investmentId,
        type: movement,
        amount: amount,
        date: date,
        description: _text(description),
        linkedTransactionId: transactionId,
        createdAt: now,
      ),
      currentValue: next,
      updatedAt: now,
      transaction: Transaction(
        id: transactionId,
        userId: userId,
        type: type,
        amount: amount,
        description: _text(description) ?? type.label,
        transactionDate: date,
        status: TransactionStatus.confirmed,
        accountId: movesAccount ? accountId : null,
        investmentId: investmentId,
        source: TransactionSource.manual,
        createdAt: now,
        updatedAt: now,
      ),
      entries: signed == null || accountId == null
          ? const []
          : [
              TransactionEntry(
                id: _ids.next(),
                transactionId: transactionId,
                accountId: accountId,
                amount: signed,
                createdAt: now,
              ),
            ],
    );
  }
}

class LinkInvestmentCash {
  const LinkInvestmentCash({
    required FinanceRepository finance,
    required TransactionRepository transactions,
    required InvestmentPositionService positions,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _transactions = transactions,
       _positions = positions,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final TransactionRepository _transactions;
  final InvestmentPositionService _positions;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String investmentId,
    required String transactionId,
  }) async {
    final investment = await _finance.findInvestment(investmentId);
    if (investment == null ||
        investment.isDeleted ||
        investment.userId != userId ||
        !investment.isActive) {
      throw const ValidationException('Investimento inválido.');
    }
    final transaction = await _transactions.findById(transactionId);
    if (transaction == null ||
        transaction.isDeleted ||
        transaction.userId != userId ||
        transaction.investmentId != null) {
      throw const ValidationException('Lançamento inválido ou já vinculado.');
    }
    if (transaction.type != TransactionType.investmentContribution &&
        transaction.type != TransactionType.investmentWithdrawal) {
      throw const ValidationException(
        'Só é possível vincular aporte ou resgate de investimento.',
      );
    }
    final movementType =
        transaction.type == TransactionType.investmentContribution
        ? InvestmentMovementType.contribution
        : InvestmentMovementType.withdrawal;
    final existing = await _finance.movementsFor(investmentId);
    final nextRaw = _positions.valueOf([
      ...existing,
      (type: movementType, amount: transaction.amount),
    ]);
    final next = Money(nextRaw.cents < 0 ? 0 : nextRaw.cents);
    final now = _clock.nowUtc();
    await _finance.linkInvestmentCash(
      transactionId: transactionId,
      movement: InvestmentMovementDraft(
        id: _ids.next(),
        investmentId: investmentId,
        type: movementType,
        amount: transaction.amount,
        date: transaction.transactionDate,
        description: transaction.description,
        linkedTransactionId: transactionId,
        createdAt: now,
      ),
      currentValue: next,
      updatedAt: now,
    );
  }
}

class UnlinkInvestmentCash {
  const UnlinkInvestmentCash({
    required FinanceRepository finance,
    required TransactionRepository transactions,
    required InvestmentPositionService positions,
    required Clock clock,
  }) : _finance = finance,
       _transactions = transactions,
       _positions = positions,
       _clock = clock;

  final FinanceRepository _finance;
  final TransactionRepository _transactions;
  final InvestmentPositionService _positions;
  final Clock _clock;

  Future<void> call({
    required String userId,
    required String transactionId,
  }) async {
    final transaction = await _transactions.findById(transactionId);
    if (transaction == null ||
        transaction.isDeleted ||
        transaction.userId != userId) {
      throw const ValidationException('Lançamento inválido.');
    }
    final investmentId = transaction.investmentId;
    if (investmentId == null) {
      throw const ValidationException('Este lançamento não está vinculado.');
    }
    final investment = await _finance.findInvestment(investmentId);
    if (investment == null ||
        investment.isDeleted ||
        investment.userId != userId) {
      throw const ValidationException('Investimento inválido.');
    }
    if (transaction.type != TransactionType.investmentContribution &&
        transaction.type != TransactionType.investmentWithdrawal) {
      throw const ValidationException(
        'Só é possível desvincular aporte ou resgate de investimento.',
      );
    }
    final current = _positions.valueOf(await _finance.movementsFor(investmentId));
    final reversed = transaction.type == TransactionType.investmentContribution
        ? -transaction.amount.cents
        : transaction.amount.cents;
    final nextCents = current.cents + reversed;
    final now = _clock.nowUtc();
    await _finance.unlinkInvestmentCash(
      transactionId: transactionId,
      investmentId: investmentId,
      currentValue: Money(nextCents < 0 ? 0 : nextCents),
      updatedAt: now,
    );
  }
}

/// Cria um investimento avulso e vincula todos os lançamentos de um produto.
class AdoptInvestmentProduct {
  const AdoptInvestmentProduct({
    required CreateInvestment createInvestment,
    required LinkInvestmentCash linkCash,
    required InvestmentCategoryService categories,
  }) : _createInvestment = createInvestment,
       _linkCash = linkCash,
       _categories = categories;

  final CreateInvestment _createInvestment;
  final LinkInvestmentCash _linkCash;
  final InvestmentCategoryService _categories;

  Future<Investment> call({
    required String userId,
    required String productKey,
    required List<InvestmentCashEvent> events,
    String? name,
    InvestmentKind kind = InvestmentKind.fixedIncome,
  }) async {
    final snapshot = _categories.settle(events);
    InvestmentProductBucket? product;
    for (final item in snapshot.products) {
      if (item.key == productKey) {
        product = item;
        break;
      }
    }
    if (product == null || product.events.isEmpty) {
      throw const ValidationException('Produto de investimento não encontrado.');
    }
    final investment = await _createInvestment(
      userId: userId,
      name: (name ?? product.label).trim(),
      kind: kind,
    );
    for (final event in product.events) {
      final id = event.transactionId;
      if (id == null) continue;
      await _linkCash(
        userId: userId,
        investmentId: investment.id,
        transactionId: id,
      );
    }
    return investment;
  }
}

class CreateFinancialGoal {
  const CreateFinancialGoal({
    required FinanceRepository finance,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String name,
    required Money targetAmount,
    required Money currentAmount,
    required Money expectedMonthlySavings,
    required double monthlyRate,
    GoalType goalType = GoalType.netWorth,
    LocalDate? targetDate,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe o nome da meta.');
    }
    if (targetAmount.cents <= 0) {
      throw const ValidationException('A meta precisa ser maior que zero.');
    }
    if (monthlyRate < 0) {
      throw const ValidationException('A rentabilidade não pode ser negativa.');
    }
    final now = _clock.nowUtc();
    await _finance.saveGoal(
      FinancialGoal(
        id: _ids.next(),
        userId: userId,
        name: trimmed,
        targetAmount: targetAmount,
        currentAmount: currentAmount,
        expectedMonthlySavings: expectedMonthlySavings,
        expectedMonthlyReturnRate: monthlyRate,
        goalType: goalType,
        targetDate: targetDate,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

class CalculateGoalProjection {
  const CalculateGoalProjection({required GoalProjectionService projections})
    : _projections = projections;

  final GoalProjectionService _projections;

  GoalProjection call({
    required Money present,
    required Money monthlyContribution,
    required double monthlyRate,
    required int months,
    required Money target,
  }) {
    final rate = (monthlyRate * 1000000).round();
    return GoalProjection(
      futureValue: _projections.futureValue(
        present: present,
        monthlyContribution: monthlyContribution,
        ratePerMillion: rate,
        months: months,
      ),
      monthsToTarget: _projections.monthsToTarget(
        present: present,
        monthlyContribution: monthlyContribution,
        ratePerMillion: rate,
        target: target,
      ),
      requiredMonthlySavings: _projections.requiredMonthlySavings(
        present: present,
        ratePerMillion: rate,
        months: months,
        target: target,
      ),
    );
  }
}

class ConfigureEmergencyFund {
  const ConfigureEmergencyFund({
    required FinanceRepository finance,
    required Clock clock,
    required IdGenerator ids,
  }) : _finance = finance,
       _clock = clock,
       _ids = ids;

  final FinanceRepository _finance;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required int targetMonths,
    Money? manualTarget,
    bool automatic = true,
    List<String> essentialCategoryIds = const [],
  }) async {
    if (targetMonths < 1) {
      throw const ValidationException('Informe ao menos 1 mês de reserva.');
    }
    final categories = [
      for (final id in essentialCategoryIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (categories.isEmpty) {
      throw const ValidationException(
        'Escolha ao menos uma categoria essencial para a reserva.',
      );
    }
    final existing = await _finance.findEmergency(userId);
    final now = _clock.nowUtc();
    await _finance.saveEmergency(
      EmergencySettings(
        id: existing?.id ?? _ids.next(),
        userId: userId,
        targetMonths: targetMonths,
        manualTargetAmount: manualTarget,
        useAutomaticCalculation: automatic,
        essentialCategoryIds: categories,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }
}

String? _text(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
