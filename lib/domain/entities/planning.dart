import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/goal_type.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/provision_status.dart';
import 'package:finan/domain/enums/recurrence_frequency.dart';
import 'package:finan/domain/enums/transaction_type.dart';

class CreditCard {
  const CreditCard({
    required this.id,
    required this.userId,
    required this.name,
    required this.creditLimit,
    required this.initialUsedLimit,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.issuer,
    this.brand,
    this.lastFourDigits,
    this.closingDay,
    this.dueDay,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? issuer;
  final String? brand;
  final String? lastFourDigits;
  final Money creditLimit;
  final Money initialUsedLimit;
  final int? closingDay;
  final int? dueDay;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}

class Recurrence {
  const Recurrence({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.amount,
    required this.frequency,
    required this.intervalValue,
    required this.startDate,
    required this.nextOccurrence,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.accountId,
    this.creditCardId,
    this.endDate,
  });

  final String id;
  final String userId;
  final String name;
  final TransactionType type;
  final Money amount;
  final String? categoryId;
  final String? accountId;
  final String? creditCardId;
  final RecurrenceFrequency frequency;
  final int intervalValue;
  final LocalDate startDate;
  final LocalDate? endDate;
  final LocalDate nextOccurrence;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class Provision {
  const Provision({
    required this.id,
    required this.userId,
    required this.description,
    required this.amount,
    required this.type,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.recurrenceId,
    this.transactionId,
  });

  final String id;
  final String userId;
  final String? recurrenceId;
  final String description;
  final Money amount;
  final TransactionType type;
  final LocalDate dueDate;
  final ProvisionStatus status;
  final String? transactionId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class Investment {
  const Investment({
    required this.id,
    required this.userId,
    required this.name,
    required this.kind,
    required this.currency,
    required this.currentValue,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.institution,
    this.accountId,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? institution;

  /// Conta padrão dos aportes e resgates.
  final String? accountId;
  final InvestmentKind kind;
  final String currency;
  final Money currentValue;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}

class FinancialGoal {
  const FinancialGoal({
    required this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.goalType,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.targetDate,
    this.expectedMonthlyReturnRate = 0,
    this.expectedMonthlySavings = Money.zero,
  });

  final String id;
  final String userId;
  final String name;
  final Money targetAmount;
  final Money currentAmount;
  final LocalDate? targetDate;
  final double expectedMonthlyReturnRate;
  final Money expectedMonthlySavings;
  final GoalType goalType;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class EmergencySettings {
  const EmergencySettings({
    required this.id,
    required this.userId,
    required this.targetMonths,
    required this.useAutomaticCalculation,
    required this.createdAt,
    required this.updatedAt,
    this.manualTargetAmount,
    this.essentialCategoryIds = const [],
  });

  final String id;
  final String userId;
  final int targetMonths;
  final Money? manualTargetAmount;
  final bool useAutomaticCalculation;
  final List<String> essentialCategoryIds;
  final DateTime createdAt;
  final DateTime updatedAt;
}
