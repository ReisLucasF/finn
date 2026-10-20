import 'package:finan/app/app_scope.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:flutter/material.dart';

class TransferPairPrompt {
  const TransferPairPrompt._();

  static bool _showing = false;

  static Future<bool> maybeShow(BuildContext context) async {
    if (_showing || !context.mounted) return false;
    _showing = true;
    var changed = false;
    try {
      while (true) {
        if (!context.mounted) return changed;
        final scope = AppScope.of(context);
        final userId = scope.session.user.id;
        final pair = await scope.graph.transferPairs.find(userId);
        if (pair == null || !context.mounted) return changed;
        final accounts = await scope.graph.accounts.listByUser(userId);
        if (!context.mounted) return changed;
        final answer = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Possível transferência'),
            content: _PairComparison(pair: pair, accounts: accounts),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Não'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 48),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sim'),
              ),
            ],
          ),
        );
        if (!context.mounted || answer == null) return changed;
        if (answer) {
          await scope.graph.transferPairs.convert(userId, pair);
          changed = true;
          if (context.mounted) {
            showSuccess(context, 'Convertido em transferência.');
          }
        } else {
          await scope.graph.transferPairs.dismiss(userId, pair);
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      _showing = false;
    }
    return changed;
  }
}

class _PairComparison extends StatelessWidget {
  const _PairComparison({required this.pair, required this.accounts});

  final TransferPairSuggestion pair;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String accountName(String id) {
      for (final account in accounts) {
        if (account.id == id) return account.name;
      }
      return 'Conta';
    }

    return SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatMoney(pair.amount)} em ${formatLocalDate(pair.date)}, '
            'em contas diferentes. Compare os nomes antes de converter.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          _Side(
            role: 'Saiu de',
            account: accountName(pair.expenseAccountId),
            description: pair.expenseDescription,
            amount: '−${formatMoney(pair.amount)}',
            color: scheme.error,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Side(
            role: 'Entrou em',
            account: accountName(pair.incomeAccountId),
            description: pair.incomeDescription,
            amount: '+${formatMoney(pair.amount)}',
            color: scheme.primary,
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.role,
    required this.account,
    required this.description,
    required this.amount,
    required this.color,
  });

  final String role;
  final String account;
  final String description;
  final String amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$role $account',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              amount,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
