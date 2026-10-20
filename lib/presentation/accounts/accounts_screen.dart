import 'package:finan/app/app_scope.dart';
import 'package:finan/app/router.dart';
import 'package:finan/application/accounts/list_accounts.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/finan_widgets.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({required this.refreshTick, super.key});

  final int refreshTick;

  @override
  State<AccountsScreen> createState() => AccountsScreenState();
}

class AccountsScreenState extends State<AccountsScreen> {
  List<AccountWithBalance> _accounts = const [];
  Object? _error;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant AccountsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _load(silent: _accounts.isNotEmpty || _error == null && !_loading);
    }
  }

  Future<void> _load({bool silent = false}) async {
    final request = ++_request;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final scope = AppScope.of(context);
      final accounts = await scope.graph.listAccounts(scope.session.user.id);
      if (!mounted || request != _request) return;
      setState(() {
        _accounts = accounts;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openForm({AccountWithBalance? item}) async {
    final saved = await AppRouter.openAccountForm(
      context,
      account: item?.account,
    );
    if (saved == true) await _load(silent: true);
  }

  Future<void> _deactivate(AccountWithBalance item) async {
    try {
      await AppScope.of(context).graph.deactivateAccount(item.account.id);
      if (!mounted) return;
      showSuccess(context, 'Conta desativada');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _activate(AccountWithBalance item) async {
    final account = item.account;
    try {
      await AppScope.of(context).graph.updateAccount(
        id: account.id,
        name: account.name,
        type: account.type,
        initialBalance: account.initialBalance,
        isActive: true,
        institutionName: account.institutionName,
        institutionCode: account.institutionCode,
      );
      if (!mounted) return;
      showSuccess(context, 'Conta reativada');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _delete(AccountWithBalance item) async {
    final confirmed = await confirmAction(
      context,
      title: 'Excluir conta',
      message: 'A conta deixa de aparecer e o saldo sai do patrimônio. O histórico dos lançamentos é mantido.',
      confirmLabel: 'Excluir',
    );
    if (!confirmed || !mounted) return;
    try {
      await AppScope.of(context).graph.deleteAccount(item.account.id);
      if (!mounted) return;
      showSuccess(context, 'Conta excluída');
      await _load(silent: true);
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Contas',
      subtitle: 'Saldos e movimentação',
      trailing: IconButton.filledTonal(
        tooltip: 'Nova conta',
        onPressed: () => _openForm(),
        icon: const Icon(CupertinoIcons.add),
      ),
      body: _loading
          ? const LoadingSkeleton()
          : _error != null
          ? ErrorView(
              message: 'Não foi possível carregar suas contas.',
              onRetry: _load,
            )
          : _accounts.isEmpty
          ? EmptyView(
              icon: CupertinoIcons.creditcard,
              message: 'Você ainda não possui contas.',
              detail:
                  'Cadastre sua conta corrente, poupança ou carteira para '
                  'acompanhar os saldos.',
              actionLabel: 'Criar conta',
              onAction: _openForm,
            )
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _content(context, constraints.maxWidth),
              ),
            ),
    );
  }

  Widget _content(BuildContext context, double width) {
    final active = [
      for (final item in _accounts)
        if (item.account.isActive) item,
    ]..sort((a, b) => b.balance.cents.compareTo(a.balance.cents));
    final inactive = [
      for (final item in _accounts)
        if (!item.account.isActive) item,
    ];
    final total = active.fold(Money.zero, (sum, item) => sum + item.balance);
    final positive = active.fold(
      0,
      (sum, item) => sum + (item.balance.cents > 0 ? item.balance.cents : 0),
    );
    final negative = active.where((item) => item.balance.cents < 0).length;
    final negativeCents = active.fold(
      0,
      (sum, item) => sum + (item.balance.cents < 0 ? item.balance.cents : 0),
    );
    final columns = gridColumns(width);
    var order = 0;
    Widget step(Widget child) => FadeSlideIn(index: order++, child: child);

    _AccountCard card(AccountWithBalance item) => _AccountCard(
      item: item,
      share: positive <= 0 || item.balance.cents <= 0
          ? 0
          : item.balance.cents / positive,
      onTap: () => _openForm(item: item),
      onAction: (action) => switch (action) {
        _AccountAction.edit => _openForm(item: item),
        _AccountAction.toggle =>
          item.account.isActive ? _deactivate(item) : _activate(item),
        _AccountAction.delete => _delete(item),
      },
    );

    return ListView(
      padding: screenPadding(context),
      children: [
        step(
          FinanHero(
            icon: CupertinoIcons.creditcard_fill,
            label: 'Saldo em contas',
            value: total,
            caption:
                '${active.length} ${active.length == 1 ? 'conta ativa' : 'contas ativas'}',
            badge: negative > 0
                ? DeltaChip(
                    label: '$negative no negativo',
                    color: Colors.white,
                    icon: CupertinoIcons.exclamationmark_circle,
                  )
                : null,
            stats: [
              HeroStat(
                icon: CupertinoIcons.arrow_up_circle,
                label: 'Saldos positivos',
                money: Money(positive),
              ),
              HeroStat(
                icon: CupertinoIcons.arrow_down_circle,
                label: 'Saldos negativos',
                money: Money(negativeCents),
              ),
              if (active.isNotEmpty)
                HeroStat(
                  icon: _typeIcon(active.first.account.type),
                  label: 'Maior: ${active.first.account.name}',
                  money: active.first.balance,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (active.isNotEmpty) ...[
          step(
            SectionHeader(
              title: 'Ativas',
              subtitle: 'Ordenadas por saldo',
              action: 'Nova conta',
              onAction: () => _openForm(),
            ),
          ),
          step(TileGrid(columns: columns, children: active.map(card).toList())),
        ],
        if (inactive.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          step(
            const SectionHeader(
              title: 'Inativas',
              subtitle: 'Não entram no patrimônio',
            ),
          ),
          step(
            Opacity(
              opacity: 0.6,
              child: TileGrid(
                columns: columns,
                children: inactive.map(card).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _AccountAction { edit, toggle, delete }

IconData _typeIcon(AccountType type) => switch (type) {
  AccountType.checking => CupertinoIcons.building_2_fill,
  AccountType.savings => CupertinoIcons.tray_arrow_down_fill,
  AccountType.cash => CupertinoIcons.money_dollar_circle_fill,
  AccountType.digitalWallet => CupertinoIcons.device_phone_portrait,
  AccountType.other => CupertinoIcons.creditcard_fill,
};

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.item,
    required this.share,
    required this.onTap,
    required this.onAction,
  });

  final AccountWithBalance item;

  /// Fração do saldo positivo total que esta conta representa (0–1).
  final double share;
  final VoidCallback onTap;
  final ValueChanged<_AccountAction> onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final account = item.account;
    final negative = item.balance.cents < 0;
    final institution = account.institutionName?.trim();
    final subtitle = [
      account.type.label,
      if (institution != null && institution.isNotEmpty) institution,
      if (!account.isActive) 'Inativa',
    ].join(' · ');
    return Semantics(
      button: true,
      label: '${account.name}, $subtitle, saldo ${formatMoney(item.balance)}',
      child: FinanCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        radius: AppSpacing.radius,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: _typeIcon(account.type),
                    color: scheme.primary,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_AccountAction>(
                    tooltip: 'Ações da conta',
                    icon: Icon(
                      CupertinoIcons.ellipsis,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onSelected: onAction,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _AccountAction.edit,
                        child: Text('Editar'),
                      ),
                      PopupMenuItem(
                        value: _AccountAction.toggle,
                        child: Text(
                          account.isActive ? 'Desativar' : 'Reativar',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _AccountAction.delete,
                        child: Text('Excluir'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoney(
                        value: item.balance,
                        style: AppTypography.headline(
                          negative
                              ? AppColors.expenseOf(brightness)
                              : scheme.onSurface,
                        ).copyWith(fontSize: 22),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AnimatedProgressBar(
                      value: share,
                      color: scheme.primary,
                      height: 5,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      negative
                          ? 'Saldo negativo'
                          : '${(share * 100).round()}% do saldo total',
                      style: AppTypography.label(
                        negative
                            ? AppColors.expenseOf(brightness)
                            : scheme.onSurface.withValues(alpha: 0.5),
                      ).copyWith(fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
