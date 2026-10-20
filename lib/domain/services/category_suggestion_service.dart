import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';

class CategorySuggestionService {
  const CategorySuggestionService();

  static const _rules = <(String, List<String>)>[
    ('Transporte', ['uber', '99app', '99 pop', 'cabify']),
    ('Alimentação', ['ifood', 'rappi', 'restaurante']),
    ('Assinaturas', ['netflix', 'spotify', 'disney']),
    ('Saúde', ['farmacia', 'drogaria', 'drogasil']),
    ('Moradia', ['aluguel', 'condominio']),
    ('Salário', ['salario']),
    ('Juros', ['rendimentos', 'rendimento']),
    (
      'Transferências internas',
      ['transferencia entre contas', 'transf entre contas'],
    ),
  ];

  CategorySuggestion? suggest({
    required String normalizedDescription,
    required List<Category> categories,
    required List<ClassifiedDescription> history,
  }) {
    if (normalizedDescription.isEmpty) return null;
    for (final item in history) {
      if (normalizeDescription(item.description) != normalizedDescription) {
        continue;
      }
      return CategorySuggestion(
        categoryId: item.categoryId,
        confidence: 0.97,
        reason: 'classificação anterior',
      );
    }
    for (final rule in _rules) {
      final matched = rule.$2.any(
        (token) => _containsToken(normalizedDescription, token),
      );
      if (!matched) continue;
      final category = _findByName(categories, rule.$1);
      if (category == null) continue;
      return CategorySuggestion(
        categoryId: category.id,
        confidence: 0.94,
        reason: 'palavra-chave',
      );
    }
    if (_containsToken(normalizedDescription, '99')) {
      final category = _findByName(categories, 'Transporte');
      if (category != null) {
        return CategorySuggestion(
          categoryId: category.id,
          confidence: 0.94,
          reason: 'palavra-chave',
        );
      }
    }
    return null;
  }

  Category? _findByName(List<Category> categories, String name) {
    final target = normalizeDescription(name);
    for (final category in categories) {
      if (!category.isActive || category.deletedAt != null) continue;
      if (normalizeDescription(category.name) == target) return category;
    }
    return null;
  }

  bool _containsToken(String text, String token) {
    final normalized = normalizeDescription(token);
    if (normalized.length <= 2) {
      return RegExp('\\b${RegExp.escape(normalized)}\\b').hasMatch(text);
    }
    return text.contains(normalized);
  }
}
