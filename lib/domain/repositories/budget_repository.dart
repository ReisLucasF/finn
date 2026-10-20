import 'package:finan/domain/entities/budget.dart';

abstract class BudgetRepository {
  /// Insere ou atualiza (um orçamento por categoria).
  Future<void> save(Budget budget);

  Future<void> delete(String id);

  Future<List<Budget>> listByUser(String userId);
}
