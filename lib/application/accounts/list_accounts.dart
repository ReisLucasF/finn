import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/repositories/account_repository.dart';
import 'package:finan/domain/repositories/transaction_repository.dart';
import 'package:finan/domain/services/balance_service.dart';

class AccountWithBalance {
  const AccountWithBalance({required this.account, required this.balance});

  final Account account;
  final Money balance;
}

class ListAccounts {
  const ListAccounts({
    required AccountRepository accounts,
    required TransactionRepository transactions,
    required BalanceService balanceService,
  }) : _accounts = accounts,
       _transactions = transactions,
       _balanceService = balanceService;

  final AccountRepository _accounts;
  final TransactionRepository _transactions;
  final BalanceService _balanceService;

  Future<List<AccountWithBalance>> call(String userId) async {
    final accounts = await _accounts.listByUser(userId);
    final parts = await _transactions.balancePartsForUser(userId);
    final byId = {for (final part in parts) part.accountId: part};
    return [
      for (final account in accounts)
        AccountWithBalance(
          account: account,
          balance: _balanceService.accountBalance(
            initialBalance: account.initialBalance,
            confirmedEntries: byId[account.id]?.confirmedEntries ?? Money.zero,
          ),
        ),
    ];
  }
}
