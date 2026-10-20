import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/entities/transaction_entry.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/balance_service.dart';

class CardUsage {
  const CardUsage({
    required this.cardId,
    required this.initialUsed,
    required this.confirmedEntries,
  });

  final String cardId;
  final Money initialUsed;
  final Money confirmedEntries;
}

class InvestmentMovementDraft {
  const InvestmentMovementDraft({
    required this.id,
    required this.investmentId,
    required this.type,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.description,
    this.linkedTransactionId,
  });

  final String id;
  final String investmentId;
  final InvestmentMovementType type;
  final Money amount;
  final LocalDate date;
  final String? description;
  final String? linkedTransactionId;
  final DateTime createdAt;
}

abstract class FinanceRepository {
  Future<void> saveTransfer({
    required String id,
    required String userId,
    required String sourceAccountId,
    required String destinationAccountId,
    required Money amount,
    required LocalDate date,
    required String? description,
    required String status,
    required DateTime createdAt,
    required Transaction transaction,
    required List<TransactionEntry> entries,
  });

  Future<void> saveCreditCard(CreditCard card);

  Future<CreditCard?> findCreditCard(String id);

  Future<void> applyCreditCardProfile({
    required String userId,
    required String cardId,
    required Money creditLimit,
    required DateTime updatedAt,
    String? brand,
    String? lastFourDigits,
    int? closingDay,
    int? dueDay,
  });

  Future<List<CreditCard>> listCreditCards(String userId);

  Future<List<CardUsage>> cardUsage(String userId);

  Future<void> saveCardPurchase({
    required Transaction transaction,
    required TransactionEntry entry,
  });

  Future<void> saveCardPayment({
    required Transaction transaction,
    required List<TransactionEntry> entries,
    required String statementId,
    required String referenceMonth,
    required LocalDate closingDate,
    required LocalDate dueDate,
    required Money total,
  });

  Future<void> saveRecurrence(Recurrence recurrence);

  Future<Recurrence?> findRecurrence(String id);

  Future<List<Recurrence>> listRecurrences(String userId);

  Future<void> saveProvisions({
    required String recurrenceId,
    required LocalDate nextOccurrence,
    required DateTime updatedAt,
    required List<Provision> provisions,
  });

  Future<Provision?> findProvision(String id);

  Future<List<Provision>> listProvisions(String userId);

  Future<void> settleProvision({
    required String provisionId,
    required DateTime updatedAt,
    required Transaction transaction,
    required List<TransactionEntry> entries,
  });

  Future<Money> openProvisionSum({
    required String userId,
    required TransactionType type,
    required LocalDate through,
  });

  Future<void> saveInvestment(Investment investment);

  Future<Investment?> findInvestment(String id);

  /// Atualiza nome, tipo, instituição, status e exclusão do investimento.
  Future<void> updateInvestment(Investment investment);

  /// Movimentações sem lançamento visível (lançamento excluído ou ausente).
  Future<List<OrphanInvestmentMovement>> orphanMovements(String investmentId);

  Future<void> removeInvestmentMovements({
    required String investmentId,
    required List<String> movementIds,
    required Money currentValue,
    required DateTime updatedAt,
  });

  Future<List<Investment>> listInvestments(String userId);

  Future<List<({InvestmentMovementType type, Money amount})>> movementsFor(
    String investmentId,
  );

  Future<void> saveInvestmentMovement({
    required InvestmentMovementDraft movement,
    required Money currentValue,
    required DateTime updatedAt,
    required Transaction transaction,
    required List<TransactionEntry> entries,
  });

  /// Associa um lançamento já existente (sem criar novo movimento na conta).
  Future<void> linkInvestmentCash({
    required String transactionId,
    required InvestmentMovementDraft movement,
    required Money currentValue,
    required DateTime updatedAt,
  });

  /// Remove o vínculo do lançamento com o investimento e recalcula a posição.
  Future<void> unlinkInvestmentCash({
    required String transactionId,
    required String investmentId,
    required Money currentValue,
    required DateTime updatedAt,
  });

  Future<Money> movementSum({
    required String userId,
    required InvestmentMovementType type,
    required LocalDate fromInclusive,
    required LocalDate toExclusive,
  });

  Future<List<DatedInvestmentMovement>> investmentMovements(String userId);

  /// Movimentações com data, agrupadas por investimento.
  Future<Map<String, List<DatedInvestmentMovement>>> movementsByInvestment(
    String userId,
  );

  Future<List<DailyAccountTotal>> cardDailyTotals(String userId);

  Future<void> saveGoal(FinancialGoal goal);

  Future<List<FinancialGoal>> listGoals(String userId);

  Future<void> saveEmergency(EmergencySettings settings);

  Future<EmergencySettings?> findEmergency(String userId);

  Future<List<RecordedTransferMatch>> findCoveringTransfers({
    required String userId,
    required String accountId,
    required Money amount,
    required LocalDate date,
  });

  Future<TransferPairSuggestion?> findTransferPair(String userId);

  Future<void> dismissTransferPair({
    required String id,
    required String userId,
    required String firstTransactionId,
    required String secondTransactionId,
    required DateTime createdAt,
  });

  Future<void> convertPairToTransfer({
    required String userId,
    required String expenseTransactionId,
    required String incomeTransactionId,
    required String sourceAccountId,
    required String destinationAccountId,
    required Money amount,
    required LocalDate date,
    required String description,
    required DateTime now,
    required String transferId,
    required String transactionId,
    required String sourceEntryId,
    required String destinationEntryId,
  });
}

class OrphanInvestmentMovement {
  const OrphanInvestmentMovement({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.description,
  });

  final String id;
  final InvestmentMovementType type;
  final Money amount;
  final LocalDate date;
  final String? description;
}

class RecordedTransferMatch {
  const RecordedTransferMatch({
    required this.transactionId,
    required this.sourceAccountId,
    required this.destinationAccountId,
  });

  final String transactionId;
  final String sourceAccountId;
  final String destinationAccountId;
}

class TransferPairSuggestion {
  const TransferPairSuggestion({
    required this.expenseTransactionId,
    required this.incomeTransactionId,
    required this.expenseAccountId,
    required this.incomeAccountId,
    required this.amount,
    required this.date,
    required this.expenseDescription,
    required this.incomeDescription,
  });

  final String expenseTransactionId;
  final String incomeTransactionId;
  final String expenseAccountId;
  final String incomeAccountId;
  final Money amount;
  final LocalDate date;
  final String expenseDescription;
  final String incomeDescription;
}
