import 'package:finan/app/router.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/presentation/accounts/accounts_screen.dart';
import 'package:finan/presentation/budgets/budgets_screen.dart';
import 'package:finan/presentation/cards/cards_screen.dart';
import 'package:finan/presentation/dashboard/dashboard_screen.dart';
import 'package:finan/presentation/emergency/emergency_screen.dart';
import 'package:finan/presentation/goals/goals_screen.dart';
import 'package:finan/presentation/investments/investments_screen.dart';
import 'package:finan/presentation/more/more_screen.dart';
import 'package:finan/presentation/shell/finan_sidebar.dart';
import 'package:finan/presentation/shell/finan_tab_bar.dart';
import 'package:finan/presentation/transactions/transactions_screen.dart';
import 'package:finan/presentation/transfers/transfer_pair_prompt.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _refresh = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final changed = await TransferPairPrompt.maybeShow(context);
      if (changed && mounted) _bump();
    });
  }

  void _bump() => setState(() => _refresh++);

  Future<void> _create(TransactionType type) async {
    final saved = await AppRouter.openTransactionForm(context, type: type);
    if (saved == true) {
      _bump();
      if (!mounted) return;
      final changed = await TransferPairPrompt.maybeShow(context);
      if (changed && mounted) _bump();
    }
  }

  Future<void> _openSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Novo lançamento',
                  style: AppTypography.headline(scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.md),
                _SheetAction(
                  icon: CupertinoIcons.arrow_down_circle,
                  color: scheme.primary,
                  title: 'Receita',
                  onTap: () => Navigator.pop(context, 'income'),
                ),
                _SheetAction(
                  icon: CupertinoIcons.arrow_up_circle,
                  color: scheme.error,
                  title: 'Despesa',
                  onTap: () => Navigator.pop(context, 'expense'),
                ),
                _SheetAction(
                  icon: CupertinoIcons.arrow_right_arrow_left_circle,
                  color: scheme.onSurface,
                  title: 'Transferência',
                  onTap: () => Navigator.pop(context, 'transfer'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    if (action == 'transfer') {
      final saved = await AppRouter.openTransferForm(context);
      if (saved == true) _bump();
      return;
    }
    await _create(
      action == 'income' ? TransactionType.income : TransactionType.expense,
    );
  }

  /// No desktop troca de aba; no celular (sem a aba) abre por cima.
  void _showBudgets(bool wide) {
    if (wide) {
      _selectTab(3);
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()))
        .then((_) {
          if (mounted) _bump();
        });
  }

  void _selectTab(int index) {
    setState(() {
      _index = index;
      _refresh++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final pages = IndexedStack(
      index: _index,
      children: [
        DashboardScreen(
          refreshTick: _refresh,
          onShowTransactions: () => setState(() => _index = 2),
          onShowBudgets: () => _showBudgets(wide),
        ),
        AccountsScreen(refreshTick: _refresh),
        TransactionsScreen(refreshTick: _refresh),
        BudgetsScreen(refreshTick: _refresh),
        const InvestmentsScreen(),
        const GoalsScreen(),
        const EmergencyScreen(),
        const CardsScreen(),
        MoreScreen(includeSidebarDestinations: !wide),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FinanSidebar(
                  index: _index,
                  items: FinanTabBar.sidebarItems,
                  onChanged: _selectTab,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: pages),
                      FinanComposeFooter(
                        visible: _index == 0 || _index == 2,
                        onPressed: _openSheet,
                      ),
                    ],
                  ),
                ),
              ],
            )
          : pages,
      bottomNavigationBar: wide
          ? null
          : FinanTabBar(
              index: FinanTabBar.mobileIndexes.indexOf(_index),
              items: FinanTabBar.itemsDefault,
              onCompose: _openSheet,
              onChanged: (slot) => _selectTab(FinanTabBar.mobileIndexes[slot]),
            ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: color, size: 28),
        title: Text(title, style: AppTypography.headline(
          Theme.of(context).colorScheme.onSurface,
        ).copyWith(fontSize: 18)),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
    );
  }
}
