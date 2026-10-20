import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';

class PluggyCategoryMatcher {
  const PluggyCategoryMatcher();

  static const aliases = <String, String>{
    'groceries': 'Alimentação',
    'food and drinks': 'Alimentação',
    'eating out': 'Alimentação',
    'restaurants': 'Alimentação',
    'houseware': 'Moradia',
    'rent': 'Moradia',
    'electricity': 'Moradia',
    'gas': 'Moradia',
    'water': 'Moradia',
    'telecommunications': 'Moradia',
    'school': 'Educação',
    'education': 'Educação',
    'bookstore': 'Educação',
    'pet supplies and vet': 'Saúde',
    'pharmacy': 'Saúde',
    'hospital clinics and labs': 'Saúde',
    'electronics': 'Compras',
    'clothing': 'Compras',
    'online shopping': 'Compras',
    'shopping': 'Compras',
    'digital services': 'Assinaturas',
    'services': 'Serviços',
    'taxi and ride hailing': 'Transporte',
    'public transportation': 'Transporte',
    'gas stations': 'Transporte',
    'travel': 'Viagens',
    'salary': 'Salário',
    'taxes': 'Impostos',
    'leisure': 'Lazer',
  };

  String? match({
    required String pluggyCategory,
    required List<Category> categories,
    required TransactionType type,
  }) {
    final normalized = normalizeDescription(pluggyCategory);
    if (normalized.isEmpty) return null;
    final alias = aliases[normalized];
    final target = alias == null ? normalized : normalizeDescription(alias);
    for (final category in categories) {
      if (!category.isActive || category.deletedAt != null) continue;
      if (normalizeDescription(category.name) != target) continue;
      if (!_accepts(category, type)) continue;
      return category.id;
    }
    return null;
  }

  bool _accepts(Category category, TransactionType type) {
    if (category.type == CategoryType.investmentApplication ||
        category.type == CategoryType.investmentRedemption ||
        category.type == CategoryType.internalTransfer) {
      return false;
    }
    return category.type.accepts(type);
  }
}
