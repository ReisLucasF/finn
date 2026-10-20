import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';

class DatedFlow {
  const DatedFlow({
    required this.date,
    required this.type,
    required this.amount,
  });

  final LocalDate date;
  final TransactionType type;
  final Money amount;
}

class CategoryAmount {
  const CategoryAmount({required this.label, required this.amount});

  final String label;
  final Money amount;
}

class DatedInvestmentMovement {
  const DatedInvestmentMovement({
    required this.date,
    required this.type,
    required this.amount,
  });

  final LocalDate date;
  final InvestmentMovementType type;
  final Money amount;
}

class OpeningBalance {
  const OpeningBalance({
    required this.id,
    required this.initial,
    required this.openedOn,
  });

  final String id;
  final Money initial;
  final LocalDate openedOn;
}

class FlowMonth {
  const FlowMonth({
    required this.start,
    required this.income,
    required this.expense,
  });

  final LocalDate start;
  final Money income;
  final Money expense;

  Money get savings => Money(income.cents - expense.cents);
}

class CategorySlice {
  const CategorySlice({required this.label, required this.amount});

  final String label;
  final Money amount;
}

class MoneyPoint {
  const MoneyPoint({required this.date, required this.amount});

  final LocalDate date;
  final Money amount;
}

class InvestmentPoint {
  const InvestmentPoint({
    required this.date,
    required this.invested,
    required this.current,
  });

  final LocalDate date;
  final Money invested;
  final Money current;
}

class DashboardCharts {
  const DashboardCharts({
    required this.months,
    required this.incomeByCategory,
    required this.expenseByCategory,
    required this.netWorth,
    required this.investments,
  });

  final List<FlowMonth> months;
  final List<CategorySlice> incomeByCategory;
  final List<CategorySlice> expenseByCategory;
  final List<MoneyPoint> netWorth;
  final List<InvestmentPoint> investments;
}

class EmergencyOverview {
  const EmergencyOverview({
    required this.reserve,
    required this.averageEssential,
    required this.targetMonths,
    required this.targetAmount,
    required this.runwayMonths,
  });

  final Money reserve;
  final Money averageEssential;
  final int targetMonths;
  final Money targetAmount;
  final double runwayMonths;

  /// 0–1+ em relação à meta de reserva.
  double get coverage {
    if (targetAmount.cents <= 0) return 0;
    return reserve.cents / targetAmount.cents;
  }

  Money get gap {
    final missing = targetAmount.cents - reserve.cents;
    return Money(missing < 0 ? 0 : missing);
  }

  bool get onTarget =>
      averageEssential.cents > 0 && runwayMonths + 0.05 >= targetMonths;
}

class DashboardSummary {
  const DashboardSummary({
    required this.netWorth,
    required this.totalAccounts,
    required this.totalInvestments,
    required this.creditCardDebt,
    required this.monthlyIncome,
    required this.monthlyExpenses,
    required this.monthlySavings,
    required this.savingsRate,
    required this.investmentRate,
    required this.emergencyRunway,
    required this.emergency,
    required this.projectedBalance,
    required this.investmentGain,
    required this.periodStart,
    required this.periodEndExclusive,
    required this.charts,
    this.investmentYield,
  });

  final Money netWorth;
  final Money totalAccounts;
  final Money totalInvestments;
  final Money creditCardDebt;
  final Money monthlyIncome;
  final Money monthlyExpenses;
  final Money monthlySavings;
  final double savingsRate;
  final double investmentRate;
  final double emergencyRunway;
  final EmergencyOverview emergency;
  final Money projectedBalance;
  final Money investmentGain;
  final LocalDate periodStart;
  final LocalDate periodEndExclusive;
  final DashboardCharts charts;

  /// Rendimento e impostos estimados dos investimentos com indexador.
  /// Quando presente, [totalInvestments] já usa o valor líquido estimado.
  final YieldSummary? investmentYield;

  LocalDate get periodEndInclusive => periodEndExclusive.addDays(-1);
}
