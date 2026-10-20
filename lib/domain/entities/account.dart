import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/account_type.dart';

class Account {
  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.currency,
    required this.initialBalance,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.institutionName,
    this.institutionCode,
    this.deletedAt,
  });

  final String id;
  final String userId;
  final String name;
  final String? institutionName;
  final String? institutionCode;
  final AccountType type;
  final String currency;
  final Money initialBalance;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Account copyWith({
    String? name,
    String? institutionName,
    bool clearInstitutionName = false,
    String? institutionCode,
    bool clearInstitutionCode = false,
    AccountType? type,
    String? currency,
    Money? initialBalance,
    bool? isActive,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return Account(
      id: id,
      userId: userId,
      name: name ?? this.name,
      institutionName: clearInstitutionName
          ? null
          : institutionName ?? this.institutionName,
      institutionCode: clearInstitutionCode
          ? null
          : institutionCode ?? this.institutionCode,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      initialBalance: initialBalance ?? this.initialBalance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }
}
