import 'package:finan/app/app_config.dart';
import 'package:finan/core/date/financial_period.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/budget.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/repositories/budget_repository.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/repositories/user_repository.dart';
import 'package:finan/domain/services/budget_service.dart';

/// Tudo que a tela de orçamentos precisa de uma vez.
class BudgetPlanning {
  const BudgetPlanning({
    required this.overview,
    required this.categories,
    required this.suggestions,
  });

  final BudgetOverview overview;

  /// Categorias de despesa que aceitam orçamento, por nome.
  final List<Category> categories;

  /// Sugestão de limite por categoria (média dos últimos meses).
  final Map<String, Money> suggestions;
}

class GetBudgetPlanning {
  const GetBudgetPlanning({
    required BudgetRepository budgets,
    required CategoryRepository categories,
    required TransactionRepository transactions,
    required UserRepository users,
    required Clock clock,
    BudgetService service = const BudgetService(),
  }) : _budgets = budgets,
       _categories = categories,
       _transactions = transactions,
       _users = users,
       _clock = clock,
       _service = service;

  static const historyMonths = 3;

  final BudgetRepository _budgets;
  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final UserRepository _users;
  final Clock _clock;
  final BudgetService _service;

  Future<BudgetPlanning> call(String userId) async {
    final user = await _users.findCurrent();
    final monthStart =
        user?.financialMonthStart ?? AppConfig.defaultFinancialMonthStart;
    final today = _clock.today();
    final period = FinancialPeriod.containing(today, monthStart);
    final historyStart = FinancialPeriod.containing(
      period.startInclusive.addMonths(-historyMonths),
      monthStart,
    ).startInclusive;

    final budgets = await _budgets.listByUser(userId);
    final categories = await _categories.listByUser(userId);
    final spent = await _transactions.expenseByCategoryId(
      userId: userId,
      fromInclusive: period.startInclusive,
      toExclusive: period.endExclusive,
    );
    final history = await _transactions.expenseByCategoryId(
      userId: userId,
      fromInclusive: historyStart,
      toExclusive: period.startInclusive,
    );

    final budgetable = [
      for (final category in categories)
        if (BudgetService.isBudgetable(category)) category,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final suggestions = <String, Money>{};
    for (final category in budgetable) {
      final suggestion = _service.suggestLimit(
        _service.rollUp(category.id, categories, history),
        historyMonths,
      );
      if (suggestion != null) suggestions[category.id] = suggestion;
    }

    return BudgetPlanning(
      overview: _service.evaluate(
        budgets: budgets,
        categories: categories,
        spentByCategory: spent,
        period: period,
        today: today,
      ),
      categories: budgetable,
      suggestions: suggestions,
    );
  }
}

class SaveBudget {
  const SaveBudget({
    required BudgetRepository budgets,
    required CategoryRepository categories,
    required Clock clock,
    required IdGenerator ids,
  }) : _budgets = budgets,
       _categories = categories,
       _clock = clock,
       _ids = ids;

  final BudgetRepository _budgets;
  final CategoryRepository _categories;
  final Clock _clock;
  final IdGenerator _ids;

  Future<void> call({
    required String userId,
    required String categoryId,
    required Money monthlyLimit,
  }) async {
    if (monthlyLimit.cents <= 0) {
      throw const ValidationException('O limite precisa ser maior que zero.');
    }
    final category = await _categories.findById(categoryId);
    if (category == null || !BudgetService.isBudgetable(category)) {
      throw const ValidationException(
        'Escolha uma categoria de despesa ativa.',
      );
    }
    final now = _clock.nowUtc();
    await _budgets.save(
      Budget(
        id: _ids.next(),
        userId: userId,
        categoryId: categoryId,
        monthlyLimit: monthlyLimit,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

class DeleteBudget {
  const DeleteBudget({required BudgetRepository budgets}) : _budgets = budgets;

  final BudgetRepository _budgets;

  Future<void> call(String budgetId) => _budgets.delete(budgetId);
}
