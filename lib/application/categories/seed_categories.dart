import 'package:finan/application/categories/category_seeds.dart';
import 'package:finan/core/time/clock.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/repositories/category_repository.dart';

class SeedCategories {
  const SeedCategories({
    required CategoryRepository categories,
    required Clock clock,
  }) : _categories = categories,
       _clock = clock;

  final CategoryRepository _categories;
  final Clock _clock;

  Future<void> call() async {
    final now = _clock.nowUtc();
    for (final seed in CategorySeeds.all) {
      final existing = await _categories.findById(seed.id);
      if (existing != null) continue;
      await _categories.save(
        Category(
          id: seed.id,
          name: seed.name,
          type: seed.type,
          icon: seed.icon,
          color: seed.color,
          isSystem: true,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }
}
