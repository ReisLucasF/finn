import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/services/balance_service.dart';

/// Dias em que o grupo já está completo na lista carregada.
/// A data seguinte vem do próximo item ou do item fora da página.
Set<(String, LocalDate)> closingPoints({
  required List<Transaction> items,
  required LocalDate? nextDate,
  String? accountId,
}) {
  final points = <(String, LocalDate)>{};
  for (var index = 0; index < items.length; index++) {
    final date = items[index].transactionDate;
    final following = index + 1 < items.length
        ? items[index + 1].transactionDate
        : nextDate;
    if (following == date) continue;
    if (accountId != null) {
      points.add((accountId, date));
      continue;
    }
    for (final item in items) {
      if (item.transactionDate != date) continue;
      final id = item.accountId;
      if (id != null) points.add((id, date));
    }
  }
  return points;
}

Map<(String, LocalDate), Money> closingBalances({
  required List<Account> accounts,
  required List<DailyAccountTotal> totals,
  required Set<(String, LocalDate)> points,
}) {
  const service = BalanceService();
  final byAccount = <String, List<DailyAccountTotal>>{};
  for (final total in totals) {
    (byAccount[total.accountId] ??= []).add(total);
  }
  final initial = {for (final account in accounts) account.id: account.initialBalance};
  final result = <(String, LocalDate), Money>{};
  for (final point in points) {
    final opening = initial[point.$1];
    if (opening == null) continue;
    result[point] = service.balanceAt(
      initialBalance: opening,
      movements: byAccount[point.$1] ?? const [],
      date: point.$2,
    );
  }
  return result;
}
