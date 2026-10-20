import 'package:finan/domain/enums/category_type.dart';

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.isSystem,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.parentId,
    this.icon,
    this.color,
    this.deletedAt,
  });

  final String id;
  final String? userId;
  final String name;
  final CategoryType type;
  final String? parentId;
  final String? icon;
  final String? color;
  final bool isSystem;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Category copyWith({
    String? name,
    CategoryType? type,
    String? icon,
    bool clearIcon = false,
    String? color,
    bool clearColor = false,
    bool? isActive,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return Category(
      id: id,
      userId: userId,
      name: name ?? this.name,
      type: type ?? this.type,
      parentId: parentId,
      icon: clearIcon ? null : icon ?? this.icon,
      color: clearColor ? null : color ?? this.color,
      isSystem: isSystem,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}
