import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/balance_service.dart';

class CalculateAccountBalance {
  const CalculateAccountBalance({
    required AccountRepository accounts,
    required TransactionRepository transactions,
    required BalanceService balanceService,
  }) : _accounts = accounts,
       _transactions = transactions,
       _balanceService = balanceService;

  final AccountRepository _accounts;
  final TransactionRepository _transactions;
  final BalanceService _balanceService;

  Future<Money> call(String accountId) async {
    final account = await _accounts.findById(accountId);
    if (account == null || account.isDeleted) {
      throw const ValidationException('Conta não encontrada.');
    }
    final parts = await _transactions.balancePartsForUser(account.userId);
    final match = parts.where((part) => part.accountId == accountId);
    final entries = match.isEmpty ? Money.zero : match.first.confirmedEntries;
    return _balanceService.accountBalance(
      initialBalance: account.initialBalance,
      confirmedEntries: entries,
    );
  }
}
