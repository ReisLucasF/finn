import 'package:finan/app/app_config.dart';
import 'package:finan/application/investments/investment_yield_actions.dart';
import 'package:finan/application/dashboard/dashboard_period.dart';
import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/repositories/user_repository.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/domain/services/card_limit_service.dart';
import 'package:finan/domain/services/dashboard_chart_service.dart';
import 'package:finan/domain/services/emergency_fund_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:finan/domain/services/investment_rate_service.dart';
import 'package:finan/domain/services/net_worth_service.dart';
import 'package:finan/domain/services/projected_balance_service.dart';
import 'package:finan/domain/services/savings_rate_service.dart';

class GetDashboardSummary {
  const GetDashboardSummary({
    required TransactionRepository transactions,
    required AccountRepository accounts,
    required CategoryRepository categories,
    required UserRepository users,
    required BalanceService balanceService,
    required NetWorthService netWorthService,
    required SavingsRateService savingsRateService,
    required FinanceRepository finance,
    required CardLimitService cardLimits,
    required EmergencyFundService emergencyFund,
    required InvestmentRateService investmentRate,
    required InvestmentCategoryService investmentCategories,
    required ProjectedBalanceService projectedBalance,
    required Clock clock,
    GetInvestmentEstimates? investmentEstimates,
  }) : _investmentEstimates = investmentEstimates,
       _transactions = transactions,
       _accounts = accounts,
       _categories = categories,
       _users = users,
       _balanceService = balanceService,
       _netWorthService = netWorthService,
       _savingsRateService = savingsRateService,
       _finance = finance,
       _cardLimits = cardLimits,
       _emergencyFund = emergencyFund,
       _investmentRate = investmentRate,
       _investmentCategories = investmentCategories,
       _projectedBalance = projectedBalance,
       _clock = clock;

  final TransactionRepository _transactions;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final UserRepository _users;
  final BalanceService _balanceService;
  final NetWorthService _netWorthService;
  final SavingsRateService _savingsRateService;
  final FinanceRepository _finance;
  final CardLimitService _cardLimits;
  final EmergencyFundService _emergencyFund;
  final InvestmentRateService _investmentRate;
  final InvestmentCategoryService _investmentCategories;
  final ProjectedBalanceService _projectedBalance;
  final Clock _clock;
  final GetInvestmentEstimates? _investmentEstimates;

  Future<DashboardSummary> call(
    String userId, {
    DashboardPeriodFilter periodFilter = DashboardPeriodFilter.currentMonth,
  }) async {
    final user = await _users.findCurrent();
    final startDay =
        user?.financialMonthStart ?? AppConfig.defaultFinancialMonthStart;
    final today = _clock.today();
    final period = periodFilter.resolve(
      today: today,
      monthStartDay: startDay,
    );
    final parts = await _transactions.balancePartsForUser(userId);
    final balances = [
      for (final part in parts)
        _balanceService.accountBalance(
          initialBalance: part.initialBalance,
          confirmedEntries: part.confirmedEntries,
        ),
    ];
    final totalAccounts = _netWorthService.fromAccountBalances(balances);
    final usages = await _finance.cardUsage(userId);
    var debtCents = 0;
    for (final usage in usages) {
      final used = _cardLimits.used(
        initialUsed: usage.initialUsed,
        confirmedEntries: usage.confirmedEntries,
      );
      if (used.cents > 0) debtCents += used.cents;
    }
    final cardDebt = Money(debtCents);
    final investments = await _finance.listInvestments(userId);
    final allCashEvents = await _transactions.listInvestmentCash(userId);
    final cashInvestments = _investmentCategories.settle(
      allCashEvents,
      gainFromInclusive: period.startInclusive,
      gainToExclusive: period.endExclusive,
    );
    // Indexados ao CDI/prefixados entram pelo valor líquido.
    final yields =
        await _investmentEstimates?.call(userId) ??
        InvestmentYieldOverview.empty;
    final investedWithCash = _investmentCategories.totalInvested(
      registeredValues: [
        for (final investment in investments)
          yields.estimates[investment.id]?.net ?? investment.currentValue,
      ],
      allCashEvents: allCashEvents,
    );
    final income = await _transactions.sumConfirmedAmount(
      userId: userId,
      type: TransactionType.income,
      fromInclusive: period.startInclusive,
      toExclusive: period.endExclusive,
    );
    final expenses = await _transactions.sumConfirmedAmount(
      userId: userId,
      type: TransactionType.expense,
      fromInclusive: period.startInclusive,
      toExclusive: period.endExclusive,
    );
    final emergency = await _finance.findEmergency(userId);
    final expenseCategories = [
      for (final category in await _categories.listByUser(
        userId,
        includeInactive: false,
      ))
        if (category.type == CategoryType.expense ||
            category.type == CategoryType.both)
          category,
    ];
    final essentialIds = _emergencyFund.resolveEssentialCategoryIds(
      saved: emergency?.essentialCategoryIds,
      expenseCategories: expenseCategories,
    );
    final previousExpenses = <Money>[];
    var cursor = period.startInclusive.addDays(-1);
    for (var index = 0; index < 3; index++) {
      final previous = FinancialPeriod.containing(cursor, startDay);
      previousExpenses.add(
        await _transactions.sumConfirmedAmount(
          userId: userId,
          type: TransactionType.expense,
          fromInclusive: previous.startInclusive,
          toExclusive: previous.endExclusive,
          categoryIds: essentialIds,
        ),
      );
      cursor = previous.startInclusive.addDays(-1);
    }
    final average = _emergencyFund.averageMonthly(previousExpenses);
    final reserve = Money(totalAccounts.cents + investedWithCash.cents);
    final targetMonths = emergency?.targetMonths ?? 6;
    final emergencyTarget = emergency?.manualTargetAmount ??
        _emergencyFund.target(
          averageEssentialExpenses: average,
          months: targetMonths,
        );
    final emergencyRunway = _emergencyFund.runway(
      reserve: reserve,
      averageEssentialExpenses: average,
    );
    final contributions = await _finance.movementSum(
      userId: userId,
      type: InvestmentMovementType.contribution,
      fromInclusive: period.startInclusive,
      toExclusive: period.endExclusive,
    );
    final provisionedIncome = await _finance.openProvisionSum(
      userId: userId,
      type: TransactionType.income,
      through: period.endInclusive,
    );
    final provisionedExpenses = await _finance.openProvisionSum(
      userId: userId,
      type: TransactionType.expense,
      through: period.endInclusive,
    );
    final chartAsOf = period.endInclusive <= today
        ? period.endInclusive
        : today;
    final charts = await _charts(
      userId: userId,
      today: chartAsOf,
      monthStartDay: startDay,
      period: period,
      cashEvents: [
        for (final event in allCashEvents)
          if (!event.isLinked) event,
      ],
    );
    return DashboardSummary(
      netWorth: _netWorthService.calculate(
        accounts: totalAccounts,
        investments: investedWithCash,
        cardDebt: cardDebt,
      ),
      totalAccounts: totalAccounts,
      totalInvestments: investedWithCash,
      creditCardDebt: cardDebt,
      monthlyIncome: income,
      monthlyExpenses: expenses,
      monthlySavings: _savingsRateService.savings(
        income: income,
        expenses: expenses,
      ),
      savingsRate: _savingsRateService.rate(income: income, expenses: expenses),
      investmentRate: _investmentRate.rate(
        contributions: contributions,
        income: income,
      ),
      emergencyRunway: emergencyRunway,
      emergency: EmergencyOverview(
        reserve: reserve,
        averageEssential: average,
        targetMonths: targetMonths,
        targetAmount: emergencyTarget,
        runwayMonths: emergencyRunway,
      ),
      projectedBalance: _projectedBalance.project(
        currentBalance: totalAccounts,
        provisionedIncome: provisionedIncome,
        provisionedExpenses: provisionedExpenses,
      ),
      investmentGain: cashInvestments.realizedGain,
      periodStart: period.startInclusive,
      periodEndExclusive: period.endExclusive,
      charts: charts,
      investmentYield: GetInvestmentEstimates.summarize(yields),
    );
  }

  Future<DashboardCharts> _charts({
    required String userId,
    required LocalDate today,
    required int monthStartDay,
    required FinancialPeriod period,
    required List<InvestmentCashEvent> cashEvents,
  }) async {
    var oldest = period.startInclusive;
    var cursor = period.startInclusive.addDays(-1);
    for (var index = 0; index < DashboardChartService.monthCount - 1; index++) {
      final previous = FinancialPeriod.containing(cursor, monthStartDay);
      oldest = previous.startInclusive;
      cursor = previous.startInclusive.addDays(-1);
    }
    final accounts = await _accounts.listByUser(userId);
    final cards = await _finance.listCreditCards(userId);
    return const DashboardChartService().build(
      today: today,
      monthStartDay: monthStartDay,
      accounts: [
        for (final account in accounts)
          OpeningBalance(
            id: account.id,
            initial: account.initialBalance,
            openedOn: LocalDate.fromDateTime(account.createdAt),
          ),
      ],
      accountMovements: await _transactions.confirmedDailyTotals(userId),
      cards: [
        for (final card in cards)
          OpeningBalance(
            id: card.id,
            initial: card.initialUsedLimit,
            openedOn: LocalDate.fromDateTime(card.createdAt),
          ),
      ],
      cardMovements: await _finance.cardDailyTotals(userId),
      investmentMovements: await _finance.investmentMovements(userId),
      cashEvents: cashEvents,
      flows: await _transactions.confirmedFlows(
        userId: userId,
        fromInclusive: oldest,
        toExclusive: period.endExclusive,
      ),
      incomeCategories: await _transactions.categoryTotals(
        userId: userId,
        type: TransactionType.income,
        fromInclusive: period.startInclusive,
        toExclusive: period.endExclusive,
      ),
      expenseCategories: await _transactions.categoryTotals(
        userId: userId,
        type: TransactionType.expense,
        fromInclusive: period.startInclusive,
        toExclusive: period.endExclusive,
      ),
    );
  }
}
