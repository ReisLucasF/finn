import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/id/id_generator.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/repositories/category_repository.dart';

class CreateCategory {
  const CreateCategory({
    required CategoryRepository categories,
    required Clock clock,
    required IdGenerator ids,
  }) : _categories = categories,
       _clock = clock,
       _ids = ids;

  final CategoryRepository _categories;
  final Clock _clock;
  final IdGenerator _ids;

  Future<Category> call({
    required String userId,
    required String name,
    required CategoryType type,
    String? icon,
    String? color,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ValidationException('Informe o nome da categoria.');
    }
    if (userId.isEmpty) {
      throw const ValidationException('Usuário inválido.');
    }
    final now = _clock.nowUtc();
    final category = Category(
      id: _ids.next(),
      userId: userId,
      name: trimmed,
      type: type,
      icon: _blankToNull(icon),
      color: _blankToNull(color),
      isSystem: false,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    await _categories.save(category);
    return category;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}
