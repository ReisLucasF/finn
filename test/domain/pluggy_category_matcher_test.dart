import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/pluggy_category_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const matcher = PluggyCategoryMatcher();
  final categories = [
    _category('food', 'Alimentação', CategoryType.expense),
    _category('shopping', 'Compras', CategoryType.expense),
    _category('salary', 'Salário', CategoryType.income),
  ];

  test('categoria do Pluggy aponta para a categoria cadastrada do mesmo tipo', () {
    expect(
      matcher.match(
        pluggyCategory: 'Electronics',
        categories: categories,
        type: TransactionType.expense,
      ),
      'shopping',
    );
    expect(
      matcher.match(
        pluggyCategory: 'Alimentação',
        categories: categories,
        type: TransactionType.expense,
      ),
      'food',
    );
    expect(
      matcher.match(
        pluggyCategory: 'Salary',
        categories: categories,
        type: TransactionType.expense,
      ),
      isNull,
    );
    expect(
      matcher.match(
        pluggyCategory: 'Salary',
        categories: categories,
        type: TransactionType.income,
      ),
      'salary',
    );
  });
}

Category _category(String id, String name, CategoryType type) {
  final now = DateTime.utc(2026);
  return Category(
    id: id,
    name: name,
    type: type,
    isSystem: true,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}
