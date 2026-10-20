import 'package:finan/core/money/money.dart';

/// Limite mensal de gasto para uma categoria de despesa.
class Budget {
  const Budget({
    required this.id,
    required this.userId,
    required this.categoryId,
    required this.monthlyLimit,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String categoryId;
  final Money monthlyLimit;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Budget copyWith({Money? monthlyLimit, bool? isActive, DateTime? updatedAt}) {
    return Budget(
      id: id,
      userId: userId,
      categoryId: categoryId,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
