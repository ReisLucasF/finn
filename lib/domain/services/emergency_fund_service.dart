import 'package:finan/core/money/money.dart';
import 'package:finan/domain/emergency/emergency_defaults.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';

class EmergencyFundService {
  const EmergencyFundService();

  Money averageMonthly(Iterable<Money> monthlyExpenses) {
    final months = monthlyExpenses.toList();
    if (months.isEmpty) return Money.zero;
    var total = 0;
    for (final month in months) {
      total += month.cents;
    }
    return Money(total ~/ months.length);
  }

  Money target({
    required Money averageEssentialExpenses,
    required int months,
  }) {
    return Money(averageEssentialExpenses.cents * months);
  }

  /// Meses de reserva. Zero quando não há despesa de referência.
  double runway({
    required Money reserve,
    required Money averageEssentialExpenses,
  }) {
    if (averageEssentialExpenses.cents <= 0) return 0;
    return reserve.cents / averageEssentialExpenses.cents;
  }

  /// Categorias salvas, ou o padrão sem lazer, compras e viagens.
  List<String> resolveEssentialCategoryIds({
    required List<String>? saved,
    Iterable<Category> expenseCategories = const [],
  }) {
    final chosen = [
      for (final id in saved ?? const <String>[])
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (chosen.isNotEmpty) return chosen;
    final live = [
      for (final category in expenseCategories)
        if (category.isActive &&
            category.deletedAt == null &&
            (category.type == CategoryType.expense ||
                category.type == CategoryType.both) &&
            !emergencyDiscretionaryCategoryIds.contains(category.id))
          category.id,
    ];
    if (live.isNotEmpty) return live;
    return List<String>.from(emergencyDefaultCategoryIds);
  }
}
