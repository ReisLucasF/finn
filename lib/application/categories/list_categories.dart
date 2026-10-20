import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/repositories/category_repository.dart';

class ListCategories {
  const ListCategories({required CategoryRepository categories})
    : _categories = categories;

  final CategoryRepository _categories;

  Future<List<Category>> call(
    String userId, {
    CategoryType? type,
    bool includeInactive = true,
  }) {
    return _categories.listByUser(
      userId,
      type: type,
      includeInactive: includeInactive,
    );
  }
}
