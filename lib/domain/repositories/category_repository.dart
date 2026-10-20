import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';

abstract class CategoryRepository {
  Future<void> save(Category category);

  Future<Category?> findById(String id);

  Future<List<Category>> listByUser(
    String userId, {
    CategoryType? type,
    bool includeInactive = true,
  });
}
