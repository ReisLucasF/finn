import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:finan/domain/services/investment_position_service.dart';
import 'package:finan/domain/services/net_worth_service.dart';

class DashboardChartService {
  const DashboardChartService({
    this.netWorth = const NetWorthService(),
    this.positions = const InvestmentPositionService(),
    this.categories = const InvestmentCategoryService(),
  });

  static const monthCount = 6;

  final NetWorthService netWorth;
  final InvestmentPositionService positions;
  final InvestmentCategoryService categories;

  DashboardCharts build({
    required LocalDate today,
    required int monthStartDay,
    required List<OpeningBalance> accounts,
    required List<DailyAccountTotal> accountMovements,
    required List<OpeningBalance> cards,
    required List<DailyAccountTotal> cardMovements,
    required List<DatedInvestmentMovement> investmentMovements,
    required List<InvestmentCashEvent> cashEvents,
    required List<DatedFlow> flows,
    required List<CategoryAmount> incomeCategories,
    required List<CategoryAmount> expenseCategories,
  }) {
    final periods = _periods(today, monthStartDay);
    final months = [
      for (final period in periods)
        FlowMonth(
          start: period.startInclusive,
          income: _flow(flows, period, TransactionType.income),
          expense: _flow(flows, period, TransactionType.expense),
        ),
    ];
    final worth = <MoneyPoint>[];
    final investments = <InvestmentPoint>[];
    for (var index = 0; index < periods.length; index++) {
      final openEnded = index == periods.length - 1;
      final asOf = openEnded ? today : periods[index].endInclusive;
      final openCapital = categories
          .settle(_eventsUntil(cashEvents, asOf, openEnded))
          .openCapital;
      final position = positions.valueOf([
        for (final movement in investmentMovements)
          if (openEnded || movement.date <= asOf)
            (type: movement.type, amount: movement.amount),
      ]);
      final invested = Money(
        _principal(investmentMovements, asOf, openEnded) + openCapital.cents,
      );
      final current = Money(position.cents + openCapital.cents);
      final accountsTotal = _tracked(
        accounts,
        accountMovements,
        asOf,
        openEnded,
        debt: false,
      );
      final debt = _tracked(
        cards,
        cardMovements,
        asOf,
        openEnded,
        debt: true,
      );
      worth.add(
        MoneyPoint(
          date: asOf,
          amount: netWorth.calculate(
            accounts: accountsTotal,
            investments: current,
            cardDebt: debt,
          ),
        ),
      );
      investments.add(
        InvestmentPoint(date: asOf, invested: invested, current: current),
      );
    }
    return DashboardCharts(
      months: months,
      incomeByCategory: [
        for (final item in incomeCategories)
          CategorySlice(label: item.label, amount: item.amount),
      ],
      expenseByCategory: [
        for (final item in expenseCategories)
          CategorySlice(label: item.label, amount: item.amount),
      ],
      netWorth: worth,
      investments: investments,
    );
  }

  List<FinancialPeriod> _periods(LocalDate today, int monthStartDay) {
    final current = FinancialPeriod.containing(today, monthStartDay);
    final periods = <FinancialPeriod>[current];
    var cursor = current.startInclusive.addDays(-1);
    while (periods.length < monthCount) {
      final previous = FinancialPeriod.containing(cursor, monthStartDay);
      periods.add(previous);
      cursor = previous.startInclusive.addDays(-1);
    }
    return periods.reversed.toList();
  }

  Money _flow(
    List<DatedFlow> flows,
    FinancialPeriod period,
    TransactionType type,
  ) {
    var cents = 0;
    for (final flow in flows) {
      if (flow.type != type) continue;
      if (flow.date < period.startInclusive || flow.date >= period.endExclusive) {
        continue;
      }
      cents += flow.amount.cents;
    }
    return Money(cents);
  }

  Iterable<InvestmentCashEvent> _eventsUntil(
    List<InvestmentCashEvent> events,
    LocalDate asOf,
    bool openEnded,
  ) {
    if (openEnded) return events;
    return events.where((event) => event.date <= asOf);
  }

  int _principal(
    List<DatedInvestmentMovement> movements,
    LocalDate asOf,
    bool openEnded,
  ) {
    var cents = 0;
    for (final movement in movements) {
      if (!openEnded && movement.date > asOf) continue;
      switch (movement.type) {
        case InvestmentMovementType.contribution:
          cents += movement.amount.cents;
        case InvestmentMovementType.withdrawal:
          cents -= movement.amount.cents;
        case InvestmentMovementType.income ||
            InvestmentMovementType.loss ||
            InvestmentMovementType.fee:
          break;
      }
    }
    return cents;
  }

  Money _tracked(
    List<OpeningBalance> openings,
    List<DailyAccountTotal> movements,
    LocalDate asOf,
    bool openEnded, {
    required bool debt,
  }) {
    var cents = 0;
    for (final opening in openings) {
      if (opening.openedOn > asOf) continue;
      var balance = opening.initial.cents;
      for (final movement in movements) {
        if (movement.accountId != opening.id) continue;
        if (!openEnded && movement.date > asOf) continue;
        balance += movement.amount.cents;
      }
      if (debt) {
        if (balance > 0) cents += balance;
      } else {
        cents += balance;
      }
    }
    return Money(cents);
  }
}
