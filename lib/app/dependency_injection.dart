import 'package:finan/application/accounts/calculate_account_balance.dart';
import 'package:finan/application/accounts/create_account.dart';
import 'package:finan/application/accounts/deactivate_account.dart';
import 'package:finan/application/accounts/delete_account.dart';
import 'package:finan/application/accounts/list_accounts.dart';
import 'package:finan/application/accounts/update_account.dart';
import 'package:finan/application/budgets/budget_actions.dart';
import 'package:finan/application/investments/investment_management.dart';
import 'package:finan/application/investments/investment_yield_actions.dart';
import 'package:finan/application/categories/create_category.dart';
import 'package:finan/application/categories/list_categories.dart';
import 'package:finan/application/categories/seed_categories.dart';
import 'package:finan/application/categories/update_category.dart';
import 'package:finan/application/backup/backup_actions.dart';
import 'package:finan/application/dashboard/get_dashboard_summary.dart';
import 'package:finan/application/ofx/analyze_ofx.dart';
import 'package:finan/application/ofx/import_ofx.dart';
import 'package:finan/application/pluggy/pluggy_sync.dart';
import 'package:finan/application/planning/planning_actions.dart';
import 'package:finan/application/transfers/transfer_pairs.dart';
import 'package:finan/application/transactions/confirm_transaction.dart';
import 'package:finan/application/transactions/create_transaction.dart';
import 'package:finan/application/transactions/delete_transaction.dart';
import 'package:finan/application/transactions/expense_investment_funding.dart';
import 'package:finan/application/transactions/list_transactions.dart';
import 'package:finan/application/transactions/recategorize_transactions.dart';
import 'package:finan/application/transactions/update_transaction.dart';
import 'package:finan/application/users/bootstrap_app.dart';
import 'package:finan/application/users/update_user_profile.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/user.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/budget_repository.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/repositories/user_repository.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/services/balance_service.dart';
import 'package:finan/domain/services/card_limit_service.dart';
import 'package:finan/domain/services/emergency_fund_service.dart';
import 'package:finan/domain/services/goal_projection_service.dart';
import 'package:finan/domain/services/investment_position_service.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:finan/domain/services/investment_rate_service.dart';
import 'package:finan/domain/services/projected_balance_service.dart';
import 'package:finan/domain/services/category_suggestion_service.dart';
import 'package:finan/domain/services/duplicate_detection_service.dart';
import 'package:finan/domain/services/transfer_detection_service.dart';
import 'package:finan/domain/services/net_worth_service.dart';
import 'package:finan/domain/services/savings_rate_service.dart';
import 'package:finan/domain/services/transaction_posting.dart';
import 'package:finan/domain/services/transaction_rules.dart';
import 'package:finan/infrastructure/backup/sqlite_backup_store.dart';
import 'package:finan/infrastructure/database/sqlite/app_database.dart';
import 'package:finan/infrastructure/database/sqlite/reset_database.dart';
import 'package:finan/infrastructure/ofx/ofx_statement_parser.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_account_repository.dart';
import 'package:finan/infrastructure/pluggy/pluggy_browser_connect.dart';
import 'package:finan/infrastructure/pluggy/pluggy_http_gateway.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_finance_repository.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_ofx_repository.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_pluggy_repository.dart';
import 'package:finan/infrastructure/market/bcb_market_data_gateway.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_budget_repository.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_investment_yield_repository.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_category_repository.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_transaction_repository.dart';
import 'package:finan/infrastructure/repositories/sqlite/sqlite_user_repository.dart';

class AppGraph {
  AppGraph._({
    required this.clock,
    required this.ids,
    required this.database,
    required this.users,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.bootstrap,
    required this.updateUserProfile,
    required this.createAccount,
    required this.updateAccount,
    required this.deactivateAccount,
    required this.deleteAccount,
    required this.listAccounts,
    required this.calculateAccountBalance,
    required this.createCategory,
    required this.updateCategory,
    required this.listCategories,
    required this.createTransaction,
    required this.updateTransaction,
    required this.deleteTransaction,
    required this.confirmTransaction,
    required this.listTransactions,
    required this.recategorizeTransactions,
    required this.getDashboardSummary,
    required this.analyzeOfx,
    required this.importOfx,
    required this.transferPairs,
    required this.finance,
    required this.createTransfer,
    required this.createCreditCard,
    required this.createCardPurchase,
    required this.payCreditCard,
    required this.createRecurrence,
    required this.generateProvisions,
    required this.settleProvision,
    required this.createInvestment,
    required this.moveInvestment,
    required this.linkInvestmentCash,
    required this.unlinkInvestmentCash,
    required this.adoptInvestmentProduct,
    required this.createFinancialGoal,
    required this.calculateGoalProjection,
    required this.configureEmergencyFund,
    required this.createBackup,
    required this.restoreBackup,
    required this.pluggySync,
    required this.budgets,
    required this.getBudgetPlanning,
    required this.saveBudget,
    required this.deleteBudget,
    required this.investmentYields,
    required this.getInvestmentEstimates,
    required this.syncMarketData,
    required this.saveInvestmentYield,
    required this.removeInvestmentYield,
    required this.updateInvestment,
    required this.deleteInvestment,
    required this.removeOrphanMovements,
    required this.redeemInvestment,
  });

  factory AppGraph.production() {
    return AppGraph.assemble(database: AppDatabase(), clock: Clock());
  }

  factory AppGraph.assemble({
    required AppDatabase database,
    required Clock clock,
    IdGenerator? ids,
    MarketDataGateway? marketGateway,
  }) {
    final generator = ids ?? UuidGenerator();
    final users = SqliteUserRepository(database);
    final accounts = SqliteAccountRepository(database);
    final categories = SqliteCategoryRepository(database);
    final transactions = SqliteTransactionRepository(database);
    final ofx = SqliteOfxRepository(database);
    final finance = SqliteFinanceRepository(database);
    final backups = SqliteBackupStore(database);
    final budgets = SqliteBudgetRepository(database);
    final investmentYields = SqliteInvestmentYieldRepository(database);
    final market = SqliteMarketDataRepository(database);
    final investmentEstimates = GetInvestmentEstimates(
      yields: investmentYields,
      finance: finance,
      market: market,
      clock: clock,
    );
    const balanceService = BalanceService();
    const netWorthService = NetWorthService();
    const savingsRateService = SavingsRateService();
    const rules = TransactionRules();
    const posting = TransactionPosting();
    const cardLimits = CardLimitService();
    const emergencyFund = EmergencyFundService();
    const investmentPositions = InvestmentPositionService();
    const investmentCategories = InvestmentCategoryService();
    final seedCategories = SeedCategories(categories: categories, clock: clock);
    final createInvestment = CreateInvestment(
      finance: finance,
      clock: clock,
      ids: generator,
    );
    final linkInvestmentCash = LinkInvestmentCash(
      finance: finance,
      transactions: transactions,
      positions: investmentPositions,
      clock: clock,
      ids: generator,
    );
    final unlinkInvestmentCash = UnlinkInvestmentCash(
      finance: finance,
      transactions: transactions,
      positions: investmentPositions,
      clock: clock,
    );
    final moveInvestment = MoveInvestment(
      finance: finance,
      accounts: accounts,
      rules: rules,
      positions: investmentPositions,
      clock: clock,
      ids: generator,
    );
    final expenseInvestmentFunding = ExpenseInvestmentFunding(
      transactions: transactions,
      clock: clock,
      ids: generator,
      link: linkInvestmentCash,
      unlink: unlinkInvestmentCash,
    );

    return AppGraph._(
      clock: clock,
      ids: generator,
      database: database,
      users: users,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      bootstrap: BootstrapApp(
        users: users,
        seedCategories: seedCategories,
        clock: clock,
        ids: generator,
      ),
      updateUserProfile: UpdateUserProfile(
        users: users,
        clock: clock,
        ids: generator,
      ),
      createAccount: CreateAccount(
        accounts: accounts,
        clock: clock,
        ids: generator,
      ),
      updateAccount: UpdateAccount(accounts: accounts, clock: clock),
      deactivateAccount: DeactivateAccount(accounts: accounts, clock: clock),
      deleteAccount: DeleteAccount(accounts: accounts, clock: clock),
      listAccounts: ListAccounts(
        accounts: accounts,
        transactions: transactions,
        balanceService: balanceService,
      ),
      calculateAccountBalance: CalculateAccountBalance(
        accounts: accounts,
        transactions: transactions,
        balanceService: balanceService,
      ),
      createCategory: CreateCategory(
        categories: categories,
        clock: clock,
        ids: generator,
      ),
      updateCategory: UpdateCategory(
        categories: categories,
        transactions: transactions,
        clock: clock,
      ),
      listCategories: ListCategories(categories: categories),
      createTransaction: CreateTransaction(
        transactions: transactions,
        accounts: accounts,
        categories: categories,
        rules: rules,
        posting: posting,
        investmentFunding: expenseInvestmentFunding,
        linkInvestmentCash: linkInvestmentCash,
        clock: clock,
        ids: generator,
      ),
      updateTransaction: UpdateTransaction(
        transactions: transactions,
        accounts: accounts,
        categories: categories,
        rules: rules,
        posting: posting,
        investmentFunding: expenseInvestmentFunding,
        linkInvestmentCash: linkInvestmentCash,
        unlinkInvestmentCash: unlinkInvestmentCash,
        clock: clock,
        ids: generator,
      ),
      deleteTransaction: DeleteTransaction(
        transactions: transactions,
        investmentFunding: expenseInvestmentFunding,
        clock: clock,
        unlinkInvestmentCash: unlinkInvestmentCash,
      ),
      confirmTransaction: ConfirmTransaction(
        transactions: transactions,
        clock: clock,
      ),
      listTransactions: ListTransactions(
        transactions: transactions,
        users: users,
        clock: clock,
      ),
      recategorizeTransactions: RecategorizeTransactions(
        transactions: transactions,
        categories: categories,
        users: users,
        clock: clock,
      ),
      getDashboardSummary: GetDashboardSummary(
        transactions: transactions,
        accounts: accounts,
        categories: categories,
        users: users,
        balanceService: balanceService,
        netWorthService: netWorthService,
        savingsRateService: savingsRateService,
        finance: finance,
        cardLimits: cardLimits,
        emergencyFund: emergencyFund,
        investmentRate: const InvestmentRateService(),
        investmentCategories: const InvestmentCategoryService(),
        projectedBalance: const ProjectedBalanceService(),
        clock: clock,
        investmentEstimates: investmentEstimates,
      ),
      analyzeOfx: AnalyzeOfx(
        parser: const OfxStatementParser(),
        accounts: accounts,
        categories: categories,
        transactions: transactions,
        ofx: ofx,
        finance: finance,
        duplicates: const DuplicateDetectionService(),
        transfers: const TransferDetectionService(),
        suggestions: const CategorySuggestionService(),
        ids: generator,
      ),
      importOfx: ImportOfx(
        ofx: ofx,
        accounts: accounts,
        categories: categories,
        transactions: transactions,
        rules: rules,
        posting: posting,
        clock: clock,
        ids: generator,
      ),
      transferPairs: TransferPairs(
        finance: finance,
        ids: generator,
        clock: clock,
      ),
      finance: finance,
      createTransfer: CreateTransfer(
        finance: finance,
        accounts: accounts,
        rules: rules,
        clock: clock,
        ids: generator,
      ),
      createCreditCard: CreateCreditCard(
        finance: finance,
        clock: clock,
        ids: generator,
      ),
      createCardPurchase: CreateCardPurchase(
        finance: finance,
        categories: categories,
        rules: rules,
        clock: clock,
        ids: generator,
      ),
      payCreditCard: PayCreditCard(
        finance: finance,
        accounts: accounts,
        rules: rules,
        limits: cardLimits,
        clock: clock,
        ids: generator,
      ),
      createRecurrence: CreateRecurrence(
        finance: finance,
        accounts: accounts,
        categories: categories,
        rules: rules,
        clock: clock,
        ids: generator,
      ),
      generateProvisions: GenerateProvisions(
        finance: finance,
        clock: clock,
        ids: generator,
      ),
      settleProvision: SettleProvision(
        finance: finance,
        posting: posting,
        clock: clock,
        ids: generator,
      ),
      createInvestment: createInvestment,
      moveInvestment: moveInvestment,
      linkInvestmentCash: linkInvestmentCash,
      unlinkInvestmentCash: unlinkInvestmentCash,
      adoptInvestmentProduct: AdoptInvestmentProduct(
        createInvestment: createInvestment,
        linkCash: linkInvestmentCash,
        categories: investmentCategories,
      ),
      createFinancialGoal: CreateFinancialGoal(
        finance: finance,
        clock: clock,
        ids: generator,
      ),
      calculateGoalProjection: const CalculateGoalProjection(
        projections: GoalProjectionService(),
      ),
      configureEmergencyFund: ConfigureEmergencyFund(
        finance: finance,
        clock: clock,
        ids: generator,
      ),
      createBackup: CreateBackup(store: backups),
      restoreBackup: RestoreBackup(store: backups),
      pluggySync: PluggySync(
        gateway: const PluggyHttpGateway(),
        connect: PluggyBrowserConnect(),
        pluggy: SqlitePluggyRepository(database),
        accounts: accounts,
        finance: finance,
        categories: categories,
        transactions: transactions,
        posting: posting,
        clock: clock,
        ids: generator,
      ),
      budgets: budgets,
      getBudgetPlanning: GetBudgetPlanning(
        budgets: budgets,
        categories: categories,
        transactions: transactions,
        users: users,
        clock: clock,
      ),
      saveBudget: SaveBudget(
        budgets: budgets,
        categories: categories,
        clock: clock,
        ids: generator,
      ),
      deleteBudget: DeleteBudget(budgets: budgets),
      investmentYields: investmentYields,
      getInvestmentEstimates: investmentEstimates,
      syncMarketData: SyncMarketData(
        gateway: marketGateway ?? BcbMarketDataGateway(),
        market: market,
        yields: investmentYields,
        finance: finance,
        clock: clock,
      ),
      saveInvestmentYield: SaveInvestmentYield(
        yields: investmentYields,
        finance: finance,
        clock: clock,
      ),
      removeInvestmentYield: RemoveInvestmentYield(yields: investmentYields),
      updateInvestment: UpdateInvestment(finance: finance, clock: clock),
      deleteInvestment: DeleteInvestment(
        finance: finance,
        transactions: transactions,
        yields: investmentYields,
        unlink: unlinkInvestmentCash,
        clock: clock,
      ),
      removeOrphanMovements: RemoveOrphanMovements(
        finance: finance,
        clock: clock,
      ),
      redeemInvestment: RedeemInvestment(
        finance: finance,
        move: moveInvestment,
      ),
    );
  }

  final Clock clock;
  final IdGenerator ids;
  final AppDatabase database;
  final UserRepository users;
  final AccountRepository accounts;
  final CategoryRepository categories;
  final TransactionRepository transactions;
  final BootstrapApp bootstrap;
  final UpdateUserProfile updateUserProfile;
  final CreateAccount createAccount;
  final UpdateAccount updateAccount;
  final DeactivateAccount deactivateAccount;
  final DeleteAccount deleteAccount;
  final ListAccounts listAccounts;
  final CalculateAccountBalance calculateAccountBalance;
  final CreateCategory createCategory;
  final UpdateCategory updateCategory;
  final ListCategories listCategories;
  final CreateTransaction createTransaction;
  final UpdateTransaction updateTransaction;
  final DeleteTransaction deleteTransaction;
  final ConfirmTransaction confirmTransaction;
  final ListTransactions listTransactions;
  final RecategorizeTransactions recategorizeTransactions;
  final GetDashboardSummary getDashboardSummary;
  final AnalyzeOfx analyzeOfx;
  final ImportOfx importOfx;
  final TransferPairs transferPairs;
  final FinanceRepository finance;
  final CreateTransfer createTransfer;
  final CreateCreditCard createCreditCard;
  final CreateCardPurchase createCardPurchase;
  final PayCreditCard payCreditCard;
  final CreateRecurrence createRecurrence;
  final GenerateProvisions generateProvisions;
  final SettleProvision settleProvision;
  final CreateInvestment createInvestment;
  final MoveInvestment moveInvestment;
  final LinkInvestmentCash linkInvestmentCash;
  final UnlinkInvestmentCash unlinkInvestmentCash;
  final AdoptInvestmentProduct adoptInvestmentProduct;
  final CreateFinancialGoal createFinancialGoal;
  final CalculateGoalProjection calculateGoalProjection;
  final ConfigureEmergencyFund configureEmergencyFund;
  final CreateBackup createBackup;
  final RestoreBackup restoreBackup;
  final PluggySync pluggySync;
  final BudgetRepository budgets;
  final GetBudgetPlanning getBudgetPlanning;
  final SaveBudget saveBudget;
  final DeleteBudget deleteBudget;
  final InvestmentYieldRepository investmentYields;
  final GetInvestmentEstimates getInvestmentEstimates;
  final SyncMarketData syncMarketData;
  final SaveInvestmentYield saveInvestmentYield;
  final RemoveInvestmentYield removeInvestmentYield;
  final UpdateInvestment updateInvestment;
  final DeleteInvestment deleteInvestment;
  final RemoveOrphanMovements removeOrphanMovements;
  final RedeemInvestment redeemInvestment;

  Future<AppUser> open() => bootstrap();

  Future<AppUser> reset() async {
    await wipeDatabase(database);
    return bootstrap();
  }
}
