class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.currency,
    required this.locale,
    required this.timezone,
    required this.financialMonthStart,
    required this.createdAt,
    required this.updatedAt,
    this.email,
  });

  final String id;
  final String name;
  final String? email;
  final String currency;
  final String locale;
  final String timezone;
  final int financialMonthStart;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get needsOnboarding => name.trim().isEmpty;

  AppUser copyWith({
    String? name,
    String? currency,
    String? locale,
    String? timezone,
    int? financialMonthStart,
    DateTime? updatedAt,
    String? email,
  }) {
    return AppUser(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      currency: currency ?? this.currency,
      locale: locale ?? this.locale,
      timezone: timezone ?? this.timezone,
      financialMonthStart: financialMonthStart ?? this.financialMonthStart,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
