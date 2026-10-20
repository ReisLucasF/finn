import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/repositories/category_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';

class UpdateCategory {
  const UpdateCategory({
    required CategoryRepository categories,
    required TransactionRepository transactions,
    required Clock clock,
  }) : _categories = categories,
       _transactions = transactions,
       _clock = clock;

  final CategoryRepository _categories;
  final TransactionRepository _transactions;
  final Clock _clock;

  Future<Category> call({
    required String id,
    required String name,
    required CategoryType type,
    required bool isActive,
    String? icon,
    String? color,
  }) async {
    final current = await _categories.findById(id);
    if (current == null || current.deletedAt != null) {
      throw const ValidationException('Categoria não encontrada.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe o nome da categoria.');
    }
    if (type != current.type && await _transactions.existsByCategory(id)) {
      throw const ValidationException(
        'Não é possível mudar o tipo de uma categoria que já possui lançamentos.',
      );
    }
    final updated = current.copyWith(
      name: trimmed,
      type: type,
      isActive: isActive,
      icon: _blankToNull(icon),
      clearIcon: _blankToNull(icon) == null,
      color: _blankToNull(color),
      clearColor: _blankToNull(color) == null,
      updatedAt: _clock.nowUtc(),
    );
    await _categories.save(updated);
    return updated;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
