import 'package:finan/app/app_scope.dart';
import 'package:finan/app/router.dart';
import 'package:finan/application/investments/investment_yield_actions.dart';
import 'package:finan/application/transactions/list_transactions.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/entities/investment_yield.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/investment_kind.dart';
import 'package:finan/domain/enums/investment_movement_type.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/investment_category_service.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/finan_widgets.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum _InvestView { unified, byAccount }

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  static const _categories = InvestmentCategoryService();

  List<Investment> _items = const [];
  List<Account> _accounts = const [];

  /// Conta padrão por investimento (cadastrada ou inferida dos lançamentos).
  Map<String, String?> _defaultAccount = const {};
  List<InvestmentCashEvent> _cash = const [];
  List<InvestmentCashEvent> _allCash = const [];
  InvestmentCategorySnapshot _snapshot = const InvestmentCategorySnapshot(
    openCapital: Money.zero,
    realizedGain: Money.zero,
  );
  Money _adjustedUnlinked = Money.zero;
  Money _totalInvestedAmount = Money.zero;
  _InvestView _view = _InvestView.unified;
  InvestmentYieldOverview _yields = InvestmentYieldOverview.empty;
  bool _syncing = false;
  bool _synced = false;
  String? _syncError;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() => _loading = _items.isEmpty && _cash.isEmpty);
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final items = await scope.graph.finance.listInvestments(userId);
      final allCash = await scope.graph.transactions.listInvestmentCash(userId);
      final yields = await scope.graph.getInvestmentEstimates(userId);
      final accounts = await scope.graph.accounts.listByUser(
        userId,
        includeInactive: false,
      );
      final defaults = <String, String?>{};
      for (final item in items) {
        var accountId = item.accountId;
        if (accountId == null) {
          final last = await scope.graph.listTransactions(
            userId: userId,
            investmentId: item.id,
            period: TransactionPeriod.all,
            limit: 1,
          );
          accountId = last.items.firstOrNull?.accountId;
        }
        defaults[item.id] = accountId;
      }
      final cash = [
        for (final event in allCash)
          if (!event.isLinked) event,
      ];
      if (!mounted) return;
      final active = [
        for (final item in items)
          if (item.isActive) item,
      ];
      setState(() {
        _items = active;
        _yields = yields;
        _accounts = accounts;
        _defaultAccount = defaults;
        _allCash = allCash;
        _cash = cash;
        _snapshot = _categories.settle(cash);
        _totalInvestedAmount = _categories.totalInvested(
          registeredValues: [
            for (final item in active)
              yields.estimates[item.id]?.net ?? item.currentValue,
          ],
          allCashEvents: allCash,
        );
        _adjustedUnlinked = _categories.unlinkedOpenCapital(allCash);
        _loading = false;
        _error = null;
      });
      if (!_synced) {
        _synced = true;
        _sync();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Busca o CDI que falta no Banco Central e recalcula se algo mudou.
  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final scope = AppScope.of(context);
      final changed = await scope.graph.syncMarketData(scope.session.user.id);
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncError = null;
      });
      // Recalcula mesmo sem dado novo: outra tela (ex.: dashboard) pode ter
      // atualizado o cache do CDI depois que esta carregou.
      if (changed || _yields.configs.isNotEmpty) await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _syncing = false;
        _syncError = friendlyError(error);
      });
    }
  }

  Future<void> _configureYield(Investment investment) async {
    final draft = await showModalBottomSheet<_YieldDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _YieldEditor(
        investment: investment,
        current: _yields.configs[investment.id],
      ),
    );
    if (draft == null || !mounted) return;
    final scope = AppScope.of(context);
    try {
      final indexer = draft.indexer;
      if (indexer == null) {
        await scope.graph.removeInvestmentYield(investment.id);
      } else {
        await scope.graph.saveInvestmentYield(
          investmentId: investment.id,
          indexer: indexer,
          rate: draft.rate,
          taxRegime: draft.regime,
        );
      }
      await _load();
      await _sync();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  /// Valor exibido: líquido estimado para indexados, senão o lançado.
  Money _valueOf(Investment item) =>
      _yields.estimates[item.id]?.net ?? item.currentValue;

  Money get _registeredTotal {
    var cents = 0;
    for (final item in _items) {
      cents += _valueOf(item).cents;
    }
    return Money(cents);
  }

  Money get _totalInvested => _totalInvestedAmount;

  Future<void> _create() async {
    final draft =
        await showModalBottomSheet<(String, InvestmentKind, String, String?)>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => _InvestmentEditor(accounts: _accounts),
        );
    if (draft == null || !mounted) return;
    try {
      final scope = AppScope.of(context);
      await scope.graph.createInvestment(
        userId: scope.session.user.id,
        name: draft.$1,
        kind: draft.$2,
        institution: draft.$3.isEmpty ? null : draft.$3,
        accountId: draft.$4,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _edit(Investment investment) async {
    final draft =
        await showModalBottomSheet<(String, InvestmentKind, String, String?)>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => _InvestmentEditor(
            initial: investment,
            accounts: _accounts,
            defaultAccountId: _defaultAccount[investment.id],
          ),
        );
    if (draft == null || !mounted) return;
    final scope = AppScope.of(context);
    try {
      await scope.graph.updateInvestment(
        userId: scope.session.user.id,
        investmentId: investment.id,
        name: draft.$1,
        kind: draft.$2,
        institution: draft.$3,
        accountId: draft.$4,
      );
      if (!mounted) return;
      showSuccess(context, 'Investimento atualizado');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _delete(Investment investment) async {
    final confirmed = await confirmAction(
      context,
      title: 'Excluir ${investment.name}?',
      message:
          'O investimento some da carteira. Aportes e resgates vinculados '
          'continuam no extrato e voltam para "não vinculados". '
          'Movimentações sem lançamento são descartadas.',
      confirmLabel: 'Excluir',
    );
    if (!confirmed || !mounted) return;
    final scope = AppScope.of(context);
    try {
      final unlinked = await scope.graph.deleteInvestment(
        userId: scope.session.user.id,
        investmentId: investment.id,
      );
      if (!mounted) return;
      showSuccess(
        context,
        unlinked == 0
            ? 'Investimento excluído'
            : 'Investimento excluído; $unlinked lançamento(s) voltaram '
                  'para não vinculados',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _move(Investment investment, InvestmentMovementType type) async {
    final needsAccount =
        type == InvestmentMovementType.contribution ||
        type == InvestmentMovementType.withdrawal;
    if (needsAccount && _accounts.isEmpty) {
      showError(context, 'Cadastre uma conta antes de movimentar.');
      return;
    }
    final draft = await showModalBottomSheet<_MoveDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MovementSheet(
        investment: investment,
        type: type,
        accounts: _accounts,
        defaultAccountId: _defaultAccount[investment.id],
        position: investment.currentValue,
        estimate: _yields.estimates[investment.id],
      ),
    );
    if (draft == null || !mounted) return;
    final scope = AppScope.of(context);
    final userId = scope.session.user.id;
    final today = scope.graph.clock.today();
    try {
      if (draft.redeemAll) {
        final diff = await scope.graph.redeemInvestment(
          userId: userId,
          investmentId: investment.id,
          received: draft.amount,
          date: today,
          accountId: draft.accountId!,
        );
        if (!mounted) return;
        showSuccess(
          context,
          diff.cents >= 0
              ? 'Investimento zerado · rendimento real +${formatMoney(diff)}'
              : 'Investimento zerado · perda de ${formatMoney(Money(-diff.cents))}',
        );
      } else {
        await scope.graph.moveInvestment(
          userId: userId,
          investmentId: investment.id,
          movement: type,
          amount: draft.amount,
          date: today,
          accountId: draft.accountId,
          description: '${type.label} · ${investment.name}',
        );
        if (!mounted) return;
        showSuccess(context, '${type.label} registrado');
      }
      // Primeira movimentação define a conta padrão do investimento.
      final accountId = draft.accountId;
      if (investment.accountId == null && accountId != null) {
        await scope.graph.updateInvestment(
          userId: userId,
          investmentId: investment.id,
          name: investment.name,
          kind: investment.kind,
          institution: investment.institution,
          accountId: accountId,
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _linkProduct(InvestmentProductBucket product) async {
    if (_items.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Crie o investimento primeiro'),
          content: const Text(
            'Use o + para cadastrar o investimento e depois vincule '
            'estes lançamentos a ele.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendi'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _create();
              },
              child: const Text('Criar agora'),
            ),
          ],
        ),
      );
      return;
    }
    var selected = _items.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vincular ao investimento'),
        content: DropdownButtonFormField<String>(
          initialValue: selected,
          decoration: const InputDecoration(labelText: 'Investimento'),
          items: [
            for (final item in _items)
              DropdownMenuItem(
                value: item.id,
                child: Text('${item.name} · ${formatMoney(item.currentValue)}'),
              ),
          ],
          onChanged: (value) {
            if (value != null) selected = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final scope = AppScope.of(context);
      for (final event in product.events) {
        final id = event.transactionId;
        if (id == null) continue;
        await scope.graph.linkInvestmentCash(
          userId: scope.session.user.id,
          investmentId: selected,
          transactionId: id,
        );
      }
      if (!mounted) return;
      showSuccess(context, 'Lançamentos vinculados');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _openInvestment(Investment investment) async {
    final scope = AppScope.of(context);
    List<Transaction> items;
    try {
      final page = await scope.graph.listTransactions(
        userId: scope.session.user.id,
        investmentId: investment.id,
        period: TransactionPeriod.all,
        limit: 200,
      );
      items = page.items;
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
      return;
    }
    final orphans = await scope.graph.removeOrphanMovements.list(investment.id);
    if (!mounted) return;
    var orphanNet = 0;
    for (final orphan in orphans) {
      final reduces =
          orphan.type == InvestmentMovementType.withdrawal ||
          orphan.type == InvestmentMovementType.loss ||
          orphan.type == InvestmentMovementType.fee;
      orphanNet += reduces ? -orphan.amount.cents : orphan.amount.cents;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        investment.name,
                        style: AppTypography.headline(
                          Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Posição ${formatMoney(investment.currentValue)}'
                        '${items.isEmpty ? '' : ' · ${items.length} lançamentos'}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (orphans.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: _OrphanBanner(
                      count: orphans.length,
                      net: Money(orphanNet),
                      onRemove: () async {
                        final ok = await confirmAction(
                          sheetContext,
                          title: 'Remover movimentações sem lançamento?',
                          message:
                              'São ${orphans.length} movimentação(ões) que '
                              'somam ${formatMoney(Money(orphanNet))} na posição, '
                              'mas cujo lançamento não existe mais. A posição '
                              'será recalculada.',
                          confirmLabel: 'Remover',
                        );
                        if (!ok || !sheetContext.mounted) return;
                        await scope.graph.removeOrphanMovements(
                          userId: scope.session.user.id,
                          investmentId: investment.id,
                        );
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          children: [
                            Text(
                              'Nenhum lançamento vinculado ainda. '
                              'Use Aporte/Resgate ou vincule itens do extrato.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final signed =
                                item.type ==
                                        TransactionType.investmentWithdrawal ||
                                    item.type ==
                                        TransactionType.investmentIncome
                                ? '+'
                                : item.type ==
                                          TransactionType
                                              .investmentContribution ||
                                      item.type ==
                                          TransactionType.investmentLoss
                                ? '−'
                                : '';
                            return ListTile(
                              title: Text(
                                item.description?.trim().isNotEmpty == true
                                    ? item.description!
                                    : item.type.label,
                              ),
                              subtitle: Text(
                                '${formatLocalDate(item.transactionDate)} · '
                                '${item.type.label}',
                              ),
                              trailing: Text(
                                '$signed${formatMoney(item.amount)}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              onTap: () async {
                                final saved =
                                    await AppRouter.openTransactionForm(
                                      context,
                                      transaction: item,
                                    );
                                if (saved == true && sheetContext.mounted) {
                                  Navigator.pop(sheetContext, true);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Investimentos',
      subtitle: 'Carteira e movimentações',
      trailing: IconButton.filledTonal(
        tooltip: 'Novo investimento',
        onPressed: _create,
        icon: const Icon(CupertinoIcons.add),
      ),
      body: _loading && _items.isEmpty && _cash.isEmpty
          ? const LoadingSkeleton()
          : _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : _items.isEmpty && _cash.isEmpty
          ? EmptyView(
              icon: CupertinoIcons.chart_pie,
              message: 'Nenhum investimento cadastrado.',
              detail:
                  'Cadastre seus produtos (CDB, ações, fundos…) e registre '
                  'aportes, resgates e rendimentos.',
              actionLabel: 'Novo investimento',
              onAction: _create,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _content(context, constraints.maxWidth),
              ),
            ),
    );
  }

  Widget _content(BuildContext context, double width) {
    final realized = _categories.settle(_allCash).realizedGain;
    var order = 0;
    Widget step(Widget child) => FadeSlideIn(index: order++, child: child);
    return ListView(
      padding: screenPadding(context),
      children: [
        step(
          FinanHero(
            icon: CupertinoIcons.graph_square_fill,
            label: 'Total investido',
            value: _totalInvested,
            badge: _yields.cdi.annualPercent == null
                ? null
                : DeltaChip(
                    label:
                        'CDI ${_yields.cdi.annualPercent!.toStringAsFixed(2).replaceAll('.', ',')}% a.a.',
                    color: Colors.white,
                  ),
            caption:
                '${_items.length} '
                '${_items.length == 1 ? 'produto cadastrado' : 'produtos cadastrados'}',
            stats: [
              HeroStat(
                icon: CupertinoIcons.square_stack_3d_up,
                label: 'Cadastrados',
                money: _registeredTotal,
              ),
              HeroStat(
                icon: CupertinoIcons.link,
                label: 'Não vinculados',
                money: _adjustedUnlinked,
              ),
              HeroStat(
                icon: CupertinoIcons.arrow_up_right,
                label: 'Ganho resgatado',
                money: realized,
              ),
            ],
            footer: realized.cents > 0
                ? const Text('Rendimento resgatado não entra em receitas.')
                : null,
          ),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          step(
            _YieldSummaryCard(
              overview: _yields,
              syncing: _syncing,
              syncError: _syncError,
              onRefresh: _sync,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          step(_AllocationCard(items: _items, valueOf: _valueOf)),
        ],
        const SizedBox(height: AppSpacing.lg),
        step(
          Row(
            children: [
              for (final view in _InvestView.values) ...[
                FinanPill(
                  label: view == _InvestView.unified
                      ? 'Unificado'
                      : 'Por conta',
                  icon: view == _InvestView.unified
                      ? CupertinoIcons.square_stack_3d_up
                      : CupertinoIcons.creditcard,
                  selected: _view == view,
                  onTap: () => setState(() => _view = view),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_view == _InvestView.unified)
          ..._unifiedBody(width, step)
        else
          ..._byAccountBody(width, step),
      ],
    );
  }

  Widget _registered(double width) {
    if (_items.isEmpty) {
      return FinanCard(
        onTap: _create,
        child: Row(
          children: [
            IconBadge(
              icon: CupertinoIcons.add,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(
              child: Text(
                'Nenhum investimento cadastrado ainda. '
                'Cadastre para vincular os aportes do extrato.',
              ),
            ),
          ],
        ),
      );
    }
    final total = _registeredTotal.cents;
    final sorted = [..._items]
      ..sort((a, b) => _valueOf(b).cents.compareTo(_valueOf(a).cents));
    return TileGrid(
      columns: gridColumns(width),
      children: [
        for (final item in sorted)
          _RegisteredCard(
            investment: item,
            value: _valueOf(item),
            realized: _yields.realized[item.id],
            share: total <= 0 ? 0 : _valueOf(item).cents / total,
            config: _yields.configs[item.id],
            estimate: _yields.estimates[item.id],
            onOpen: () => _openInvestment(item),
            onEdit: () => _edit(item),
            onDelete: () => _delete(item),
            onConfigure: () => _configureYield(item),
            onMove: _move,
          ),
      ],
    );
  }

  List<Widget> _unifiedBody(double width, Widget Function(Widget) step) {
    final pending = [
      for (final product in _snapshot.products)
        if (product.openCapital.cents > 0) product,
    ];
    return [
      step(
        SectionHeader(
          title: 'Cadastrados',
          subtitle: 'Toque para ver e editar os lançamentos',
          action: 'Novo',
          onAction: _create,
        ),
      ),
      step(_registered(width)),
      if (pending.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.lg),
        step(
          const SectionHeader(
            title: 'Não vinculados no extrato',
            subtitle: 'Aportes e resgates do banco ainda sem investimento',
          ),
        ),
        step(
          TileGrid(
            columns: gridColumns(width),
            children: [
              for (final product in pending)
                _ProductCard(
                  product: product,
                  onLink: () => _linkProduct(product),
                ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _byAccountBody(double width, Widget Function(Widget) step) {
    final byAccount = <String, List<InvestmentCashEvent>>{};
    for (final event in _cash) {
      final key = event.accountName?.trim().isNotEmpty == true
          ? event.accountName!
          : 'Sem conta';
      byAccount.putIfAbsent(key, () => []).add(event);
    }
    final names = byAccount.keys.toList()..sort();
    return [
      step(
        SectionHeader(
          title: 'Cadastrados',
          subtitle: 'Todas as contas',
          action: 'Novo',
          onAction: _create,
        ),
      ),
      step(_registered(width)),
      for (final name in names)
        ...(() {
          final snapshot = _categories.settle(byAccount[name]!);
          final products = [
            for (final product in snapshot.products)
              if (product.openCapital.cents > 0 ||
                  product.realizedGain.cents > 0)
                product,
          ];
          return [
            const SizedBox(height: AppSpacing.lg),
            step(
              SectionHeader(
                title: name,
                subtitle:
                    'Em aberto ${formatMoney(snapshot.openCapital)}'
                    '${snapshot.realizedGain.cents > 0 ? ' · ganho resgatado ${formatMoney(snapshot.realizedGain)}' : ''}',
              ),
            ),
            if (products.isNotEmpty)
              step(
                TileGrid(
                  columns: gridColumns(width),
                  children: [
                    for (final product in products)
                      _ProductCard(
                        product: product,
                        onLink: () => _linkProduct(product),
                      ),
                  ],
                ),
              ),
          ];
        })(),
    ];
  }
}

const _kindColors = <InvestmentKind, Color>{
  InvestmentKind.fixedIncome: Color(0xFF2E9E78),
  InvestmentKind.stocks: Color(0xFF4F6BD8),
  InvestmentKind.funds: Color(0xFF8A6AD8),
  InvestmentKind.etf: Color(0xFF2E8FB8),
  InvestmentKind.crypto: Color(0xFFD89A2E),
  InvestmentKind.pension: Color(0xFFC0566B),
  InvestmentKind.other: Color(0xFF7A8580),
};

IconData _kindIcon(InvestmentKind kind) => switch (kind) {
  InvestmentKind.fixedIncome => CupertinoIcons.lock_shield_fill,
  InvestmentKind.stocks => CupertinoIcons.chart_bar_alt_fill,
  InvestmentKind.funds => CupertinoIcons.square_stack_3d_up_fill,
  InvestmentKind.etf => CupertinoIcons.layers_alt_fill,
  InvestmentKind.crypto => CupertinoIcons.bitcoin_circle_fill,
  InvestmentKind.pension => CupertinoIcons.person_crop_circle_fill,
  InvestmentKind.other => CupertinoIcons.circle_grid_hex_fill,
};

/// Barra empilhada com a alocação por tipo de investimento.
class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.items, required this.valueOf});

  final List<Investment> items;
  final Money Function(Investment) valueOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byKind = <InvestmentKind, int>{};
    var total = 0;
    for (final item in items) {
      final value = valueOf(item).cents;
      final cents = value < 0 ? 0 : value;
      byKind[item.kind] = (byKind[item.kind] ?? 0) + cents;
      total += cents;
    }
    final slices = byKind.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (total <= 0 || slices.isEmpty) return const SizedBox.shrink();
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label:
          'Alocação: ${slices.map((s) => '${s.key.label} ${(s.value * 100 / total).round()}%').join(', ')}',
      child: FinanCard(
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alocação por tipo',
                style: AppTypography.headline(scheme.onSurface)
                    .copyWith(fontSize: 16),
              ),
              const SizedBox(height: AppSpacing.md),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 12,
                    child: Row(
                      children: [
                        for (var i = 0; i < slices.length; i++) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: (slices[i].value * 1000 ~/ total).clamp(
                              1,
                              1000,
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: t,
                              child: Container(
                                color: _kindColors[slices[i].key],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final slice in slices)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _kindColors[slice.key],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          slice.key.label,
                          style: AppTypography.label(
                            scheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${(slice.value * 100 / total).round()}% · '
                          '${formatMoney(Money(slice.value))}',
                          style: AppTypography.label(
                            scheme.onSurface.withValues(alpha: 0.5),
                          ).copyWith(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisteredCard extends StatelessWidget {
  const _RegisteredCard({
    required this.investment,
    required this.value,
    required this.realized,
    required this.share,
    required this.config,
    required this.estimate,
    required this.onOpen,
    required this.onConfigure,
    required this.onEdit,
    required this.onDelete,
    required this.onMove,
  });

  final Investment investment;
  final Money value;

  /// Rendimento real de resgates totais (ciclos encerrados).
  final Money? realized;
  final double share;
  final InvestmentYield? config;
  final InvestmentEstimate? estimate;
  final VoidCallback onOpen;
  final VoidCallback onConfigure;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<void> Function(Investment, InvestmentMovementType) onMove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _kindColors[investment.kind]!;
    final institution = investment.institution?.trim();
    final subtitle = [
      investment.kind.label,
      if (institution != null && institution.isNotEmpty) institution,
    ].join(' · ');
    return Semantics(
      button: true,
      label: '${investment.name}, $subtitle, ${formatMoney(value)}',
      child: FinanCard(
        onTap: onOpen,
        padding: const EdgeInsets.all(AppSpacing.md),
        radius: AppSpacing.radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  IconBadge(
                    icon: _kindIcon(investment.kind),
                    color: color,
                    size: 40,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          investment.name,
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
                  PopupMenuButton<String>(
                    tooltip: 'Ações do investimento',
                    icon: Icon(
                      CupertinoIcons.ellipsis,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onSelected: (value) => switch (value) {
                      'open' => onOpen(),
                      'edit' => onEdit(),
                      'yield' => onConfigure(),
                      _ => onDelete(),
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'open',
                        child: Text('Ver lançamentos'),
                      ),
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(
                        value: 'yield',
                        child: Text('Rentabilidade'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: Icon(
                  config == null
                      ? CupertinoIcons.slider_horizontal_3
                      : CupertinoIcons.percent,
                  size: 15,
                ),
                label: Text(
                  config == null
                      ? 'Definir indexador'
                      : '${config!.label} · '
                            '${config!.taxRegime == TaxRegime.exempt ? 'isento' : 'IR + IOF'}',
                ),
                onPressed: onConfigure,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (estimate != null && estimate!.principal.cents > 0)
              Text(
                'Líquido estimado',
                style: AppTypography.label(
                  scheme.onSurface.withValues(alpha: 0.55),
                ).copyWith(fontSize: 11.5),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: AnimatedMoney(
                value: value,
                style: AppTypography.headline(scheme.onSurface)
                    .copyWith(fontSize: 22),
              ),
            ),
            if (estimate != null && estimate!.principal.cents > 0) ...[
              const SizedBox(height: 4),
              _EstimateDetails(estimate: estimate!),
            ],
            if (realized != null) ...[
              const SizedBox(height: 4),
              DeltaChip(
                label:
                    '${value.isZero ? 'Resgatado · ' : ''}rendimento real '
                    '${realized!.cents >= 0 ? '+' : ''}${formatMoney(realized!)}',
                color: realized!.cents >= 0
                    ? AppColors.incomeOf(Theme.of(context).brightness)
                    : AppColors.expenseOf(Theme.of(context).brightness),
                icon: CupertinoIcons.checkmark_seal,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            AnimatedProgressBar(value: share, color: color, height: 5),
            const SizedBox(height: 4),
            Text(
              '${(share * 100).round()}% da carteira cadastrada',
              style: AppTypography.label(
                scheme.onSurface.withValues(alpha: 0.5),
              ).copyWith(fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (type, icon) in const [
                  (
                    InvestmentMovementType.contribution,
                    CupertinoIcons.arrow_down_circle,
                  ),
                  (
                    InvestmentMovementType.withdrawal,
                    CupertinoIcons.arrow_up_circle,
                  ),
                  (InvestmentMovementType.income, CupertinoIcons.plus_circle),
                  (InvestmentMovementType.loss, CupertinoIcons.minus_circle),
                ])
                  ActionChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(type.label),
                    onPressed: () => onMove(investment, type),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onLink});

  final InvestmentProductBucket product;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final accounts = <String>{
      for (final event in product.events)
        if (event.accountName != null && event.accountName!.trim().isNotEmpty)
          event.accountName!,
    };
    final meta = [
      '${product.events.length} lançamentos',
      if (accounts.isNotEmpty) accounts.join(', '),
    ].join(' · ');
    return FinanCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      radius: AppSpacing.radius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: CupertinoIcons.link,
                color: AppColors.warningOf(brightness),
                size: 36,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Em aberto',
            style: AppTypography.label(
              scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          Text(
            formatMoney(product.openCapital),
            style: AppTypography.headline(scheme.onSurface)
                .copyWith(fontSize: 20),
          ),
          if (product.realizedGain.cents > 0)
            Text(
              'Ganho resgatado ${formatMoney(product.realizedGain)}',
              style: AppTypography.label(AppColors.incomeOf(brightness))
                  .copyWith(fontSize: 12),
            ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.tonalIcon(
            onPressed: onLink,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
            ),
            icon: const Icon(CupertinoIcons.link, size: 16),
            label: const Text('Vincular a um investimento'),
          ),
        ],
      ),
    );
  }
}

class _InvestmentEditor extends StatefulWidget {
  const _InvestmentEditor({
    required this.accounts,
    this.initial,
    this.defaultAccountId,
  });

  /// Investimento em edição; nulo = novo.
  final Investment? initial;
  final List<Account> accounts;
  final String? defaultAccountId;

  @override
  State<_InvestmentEditor> createState() => _InvestmentEditorState();
}

class _InvestmentEditorState extends State<_InvestmentEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _institution = TextEditingController(
    text: widget.initial?.institution ?? '',
  );
  late InvestmentKind _kind =
      widget.initial?.kind ?? InvestmentKind.fixedIncome;
  late String? _accountId =
      widget.initial?.accountId ??
      widget.defaultAccountId ??
      (widget.accounts.isEmpty ? null : widget.accounts.first.id);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome do investimento.');
      return;
    }
    Navigator.pop(context, (name, _kind, _institution.text.trim(), _accountId));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.initial == null
                ? 'Novo investimento'
                : 'Editar investimento',
            style: AppTypography.headline(scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Nome',
              hintText: 'Ex.: CDB Banco X, Tesouro Selic',
              errorText: _error,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _institution,
            decoration: const InputDecoration(
              labelText: 'Instituição (opcional)',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Tipo',
            style: AppTypography.label(scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final kind in InvestmentKind.values)
                FinanPill(
                  label: kind.label,
                  icon: _kindIcon(kind),
                  selected: _kind == kind,
                  onTap: () => setState(() => _kind = kind),
                ),
            ],
          ),
          if (widget.accounts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Conta (aportes e resgates)',
              style: AppTypography.label(
                scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final account in widget.accounts)
                  FinanPill(
                    label: account.name,
                    icon: CupertinoIcons.creditcard,
                    selected: _accountId == account.id,
                    onTap: () => setState(() => _accountId = account.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: _submit, child: const Text('Salvar')),
        ],
      ),
    );
  }
}

// ───────────────────────────── Aporte / resgate ─────────────────────────────

class _MoveDraft {
  const _MoveDraft({
    required this.amount,
    required this.accountId,
    required this.redeemAll,
  });

  final Money amount;
  final String? accountId;
  final bool redeemAll;
}

class _MovementSheet extends StatefulWidget {
  const _MovementSheet({
    required this.investment,
    required this.type,
    required this.accounts,
    required this.defaultAccountId,
    required this.position,
    this.estimate,
  });

  final Investment investment;
  final InvestmentMovementType type;
  final List<Account> accounts;
  final String? defaultAccountId;
  final Money position;
  final InvestmentEstimate? estimate;

  @override
  State<_MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<_MovementSheet> {
  final _amount = TextEditingController();
  late String? _accountId =
      widget.accounts.any((a) => a.id == widget.defaultAccountId)
      ? widget.defaultAccountId
      : (widget.accounts.isEmpty ? null : widget.accounts.first.id);
  bool _changingAccount = false;
  bool _redeemAll = false;
  String? _error;

  bool get _movesAccount =>
      widget.type == InvestmentMovementType.contribution ||
      widget.type == InvestmentMovementType.withdrawal;

  bool get _isWithdrawal => widget.type == InvestmentMovementType.withdrawal;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _fill(Money value) =>
      _amount.text = formatMoney(value).replaceFirst('R\$ ', '');

  void _submit() {
    final value = tryParseMoney(_amount.text);
    if (value == null || value.cents <= 0) {
      setState(() => _error = 'Informe um valor maior que zero.');
      return;
    }
    if (_movesAccount && _accountId == null) {
      setState(() => _error = 'Cadastre uma conta antes.');
      return;
    }
    Navigator.pop(
      context,
      _MoveDraft(
        amount: value,
        accountId: _movesAccount ? _accountId : null,
        redeemAll: _isWithdrawal && _redeemAll,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final estimate = widget.estimate;
    final account = widget.accounts
        .where((a) => a.id == _accountId)
        .firstOrNull;
    final typed = tryParseMoney(_amount.text);
    final diff = typed == null
        ? null
        : Money(typed.cents - widget.position.cents);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.type.label} · ${widget.investment.name}',
              style: AppTypography.headline(scheme.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              'Posição lançada ${formatMoney(widget.position)}'
              '${estimate != null && estimate.principal.cents > 0 ? ' · líquido estimado ${formatMoney(estimate.net)}' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _redeemAll ? 'Valor que caiu na conta' : 'Valor',
                prefixText: 'R\$ ',
                errorText: _error,
              ),
            ),
            if (_isWithdrawal) ...[
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (estimate != null && estimate.principal.cents > 0)
                    ActionChip(
                      label: Text(
                        'Líquido estimado ${formatMoney(estimate.net)}',
                      ),
                      onPressed: () => setState(() => _fill(estimate.net)),
                    ),
                  if (widget.position.cents > 0)
                    ActionChip(
                      label: Text('Posição ${formatMoney(widget.position)}'),
                      onPressed: () => setState(() => _fill(widget.position)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              FinanCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                radius: AppSpacing.radiusSm,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _redeemAll,
                  onChanged: (value) => setState(() => _redeemAll = value),
                  title: const Text('Resgatar tudo'),
                  subtitle: const Text(
                    'Informe o valor que caiu na conta. O investimento é '
                    'zerado e a diferença vira o rendimento real.',
                  ),
                ),
              ),
              if (_redeemAll && diff != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  diff.cents >= 0
                      ? 'Rendimento real: +${formatMoney(diff)} sobre a posição lançada'
                      : 'Perda: ${formatMoney(Money(-diff.cents))} em relação à posição lançada',
                  style: AppTypography.label(
                    diff.cents >= 0
                        ? AppColors.incomeOf(brightness)
                        : AppColors.expenseOf(brightness),
                  ),
                ),
              ],
            ],
            if (_movesAccount) ...[
              const SizedBox(height: AppSpacing.md),
              if (!_changingAccount && account != null)
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.creditcard,
                      size: 16,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _isWithdrawal
                            ? 'Cai na conta ${account.name}'
                            : 'Sai da conta ${account.name}',
                        style: AppTypography.label(scheme.onSurface),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _changingAccount = true),
                      child: const Text('Trocar'),
                    ),
                  ],
                )
              else
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final item in widget.accounts)
                      FinanPill(
                        label: item.name,
                        selected: _accountId == item.id,
                        onTap: () => setState(() {
                          _accountId = item.id;
                          _changingAccount = false;
                        }),
                      ),
                  ],
                ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _submit,
              child: Text(_redeemAll ? 'Resgatar tudo e zerar' : 'Confirmar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── Rentabilidade ─────────────────────────────

String _pct(double fraction, {int digits = 2}) =>
    '${(fraction * 100).toStringAsFixed(digits).replaceAll('.', ',')}%';

/// Resumo do rendimento estimado dos investimentos indexados.
class _YieldSummaryCard extends StatelessWidget {
  const _YieldSummaryCard({
    required this.overview,
    required this.syncing,
    required this.syncError,
    required this.onRefresh,
  });

  final InvestmentYieldOverview overview;
  final bool syncing;
  final String? syncError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final cdi = overview.cdi;
    final last = cdi.lastDailyDate ?? cdi.annualDate;
    final income = AppColors.incomeOf(brightness);
    final hasEstimates = overview.estimates.values.any(
      (item) => item.principal.cents > 0,
    );
    final grossGain = overview.grossGain;
    final returnPct = overview.principal.cents <= 0
        ? 0.0
        : grossGain.cents / overview.principal.cents;
    var iof = 0;
    var incomeTax = 0;
    for (final estimate in overview.estimates.values) {
      iof += estimate.iof.cents;
      incomeTax += estimate.incomeTax.cents;
    }
    return FinanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Rendimento estimado',
                  style: AppTypography.headline(scheme.onSurface)
                      .copyWith(fontSize: 16),
                ),
              ),
              if (cdi.annualPercent != null)
                DeltaChip(
                  label:
                      'CDI ${cdi.annualPercent!.toStringAsFixed(2).replaceAll('.', ',')}% a.a.',
                  color: scheme.primary,
                  icon: CupertinoIcons.chart_bar_alt_fill,
                ),
              const SizedBox(width: AppSpacing.xxs),
              IconButton(
                tooltip: 'Atualizar CDI',
                visualDensity: VisualDensity.compact,
                onPressed: syncing ? null : onRefresh,
                icon: syncing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 18),
              ),
            ],
          ),
          if (hasEstimates) ...[
            const SizedBox(height: AppSpacing.md),
            TileGrid(
              columns: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
              children: [
                _Figure(
                  label: 'Rendimento bruto',
                  value: grossGain,
                  caption: '${_pct(returnPct)} sobre o aplicado',
                  color: income,
                ),
                _Figure(
                  label: 'IR estimado',
                  value: Money(incomeTax),
                  caption: 'Tabela regressiva',
                ),
                _Figure(
                  label: 'IOF estimado',
                  value: Money(iof),
                  caption: iof > 0 ? 'Aportes com menos de 30 dias' : 'Zerado',
                ),
                _Figure(
                  label: 'Líquido se resgatar hoje',
                  value: overview.net,
                  caption: 'Ganho líquido ${formatMoney(overview.netGain)}',
                  color: income,
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Defina o indexador de um investimento (ex.: 110% do CDI) para '
              'ver rendimento, IR e IOF estimados.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (!overview.realizedTotal.isZero) ...[
            const SizedBox(height: AppSpacing.sm),
            DeltaChip(
              label:
                  'Rendimento real de resgates totais: '
                  '${overview.realizedTotal.cents >= 0 ? '+' : ''}'
                  '${formatMoney(overview.realizedTotal)}',
              color: overview.realizedTotal.cents >= 0
                  ? AppColors.incomeOf(brightness)
                  : AppColors.expenseOf(brightness),
              icon: CupertinoIcons.checkmark_seal,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              if (last != null) 'CDI do BCB até ${formatLocalDate(last)}',
              if (cdi.monthlyPercent != null && cdi.monthlyDate != null)
                'mês ${cdi.monthlyDate!.month.toString().padLeft(2, '0')}/'
                    '${cdi.monthlyDate!.year}: '
                    '${cdi.monthlyPercent!.toStringAsFixed(2).replaceAll('.', ',')}%',
              'valores aproximados',
            ].join(' · '),
            style: AppTypography.label(scheme.onSurface.withValues(alpha: 0.5))
                .copyWith(fontSize: 11.5, fontWeight: FontWeight.w500),
          ),
          if (syncError != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  CupertinoIcons.wifi_slash,
                  size: 13,
                  color: AppColors.warningOf(brightness),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$syncError Usando os dados salvos.',
                    style: AppTypography.label(AppColors.warningOf(brightness))
                        .copyWith(fontSize: 11.5, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.caption,
    this.color,
  });

  final String label;
  final Money value;
  final String caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.label(scheme.onSurface.withValues(alpha: 0.55))
                .copyWith(fontSize: 12),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoney(
              value: value,
              style: AppTypography.headline(color ?? scheme.onSurface)
                  .copyWith(fontSize: 17),
            ),
          ),
          Text(
            caption,
            style: AppTypography.label(scheme.onSurface.withValues(alpha: 0.45))
                .copyWith(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Linha de detalhe da estimativa dentro do card do investimento.
class _EstimateDetails extends StatelessWidget {
  const _EstimateDetails({required this.estimate});

  final InvestmentEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final muted = AppTypography.label(scheme.onSurface.withValues(alpha: 0.55))
        .copyWith(fontSize: 11.5, fontWeight: FontWeight.w500);
    final gain = estimate.grossGain;
    final share = estimate.cdiShare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bruto ${formatMoney(estimate.gross)} · IR ${formatMoney(estimate.incomeTax)}'
          '${estimate.iof.cents > 0 ? ' · IOF ${formatMoney(estimate.iof)}' : ''}',
          style: muted,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          children: [
            DeltaChip(
              label:
                  '${gain.cents >= 0 ? '+' : ''}${formatMoney(gain)} · ${_pct(estimate.grossReturn)}',
              color: AppColors.incomeOf(brightness),
              icon: CupertinoIcons.arrow_up_right,
            ),
            if (share != null)
              DeltaChip(
                label: '${_pct(share, digits: 0)} do CDI',
                color: scheme.primary,
              ),
            DeltaChip(
              label: '${estimate.businessDays} dias úteis',
              color: scheme.onSurface.withValues(alpha: 0.6),
              icon: CupertinoIcons.calendar,
            ),
          ],
        ),
        if (estimate.projectedDays > 0 || estimate.ignoredIncome.cents > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              [
                if (estimate.projectedDays > 0)
                  '${estimate.projectedDays} dia(s) com CDI projetado',
                if (estimate.ignoredIncome.cents > 0)
                  'rendimentos lançados à mão (${formatMoney(estimate.ignoredIncome)}) '
                      'não entram no cálculo',
              ].join(' · '),
              style: muted.copyWith(fontSize: 11),
            ),
          ),
      ],
    );
  }
}

/// Resultado do editor: nulo no indexador = remover (manual).
class _YieldDraft {
  const _YieldDraft(this.indexer, this.rate, this.regime);

  final YieldIndexer? indexer;
  final double rate;
  final TaxRegime regime;
}

class _YieldEditor extends StatefulWidget {
  const _YieldEditor({required this.investment, this.current});

  final Investment investment;
  final InvestmentYield? current;

  @override
  State<_YieldEditor> createState() => _YieldEditorState();
}

class _YieldEditorState extends State<_YieldEditor> {
  late YieldIndexer? _indexer =
      widget.current?.indexer ?? YieldIndexer.cdiPercent;
  late TaxRegime _regime = widget.current?.taxRegime ?? TaxRegime.regressive;
  late final TextEditingController _rate = TextEditingController(
    text: widget.current == null
        ? '100'
        : widget.current!.rate
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'\.?0+$'), '')
              .replaceAll('.', ','),
  );
  String? _error;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  (String, String, String) get _rateTexts => switch (_indexer) {
    YieldIndexer.cdiPercent => (
      'Percentual do CDI',
      '% do CDI',
      'Ex.: 100, 110',
    ),
    YieldIndexer.cdiPlus => (
      'Taxa sobre o CDI',
      '% a.a.',
      'Ex.: 1,5 (CDI + 1,5%)',
    ),
    YieldIndexer.prefixed => ('Taxa prefixada', '% a.a.', 'Ex.: 12,5'),
    null => ('', '', ''),
  };

  void _submit() {
    final indexer = _indexer;
    if (indexer == null) {
      Navigator.pop(context, _YieldDraft(null, 0, _regime));
      return;
    }
    final rate = double.tryParse(
      _rate.text.trim().replaceAll('.', '').replaceAll(',', '.'),
    );
    if (rate == null || rate <= 0) {
      setState(() => _error = 'Informe uma taxa maior que zero.');
      return;
    }
    Navigator.pop(context, _YieldDraft(indexer, rate, _regime));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, suffix, hint) = _rateTexts;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Rentabilidade',
              style: AppTypography.headline(scheme.onSurface),
            ),
            Text(
              widget.investment.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Indexador',
              style: AppTypography.label(
                scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final indexer in YieldIndexer.values)
                  FinanPill(
                    label: indexer.label,
                    selected: _indexer == indexer,
                    onTap: () => setState(() {
                      if (_indexer != indexer) {
                        _rate.text = switch (indexer) {
                          YieldIndexer.cdiPercent => '100',
                          YieldIndexer.cdiPlus => '1',
                          YieldIndexer.prefixed => '12',
                        };
                      }
                      _indexer = indexer;
                      _error = null;
                    }),
                  ),
                FinanPill(
                  label: 'Manual',
                  icon: CupertinoIcons.pencil,
                  selected: _indexer == null,
                  onTap: () => setState(() => _indexer = null),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_indexer == null)
              Text(
                'Sem indexador o valor é a soma dos aportes, rendimentos e '
                'resgates que você lança.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else ...[
              TextField(
                controller: _rate,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  suffixText: suffix,
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Tributação',
                style: AppTypography.label(
                  scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final regime in TaxRegime.values)
                    FinanPill(
                      label: regime.label,
                      selected: _regime == regime,
                      onTap: () => setState(() => _regime = regime),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _regime == TaxRegime.regressive
                    ? 'IR de 22,5% (até 180 dias) a 15% (acima de 720) sobre o '
                          'rendimento, por aporte. IOF regressivo nos primeiros 30 dias.'
                    : 'Sem IR nem IOF sobre o rendimento.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'O rendimento passa a ser calculado pelo CDI do Banco Central '
                'a partir das datas dos aportes; rendimentos lançados à mão '
                'deixam de contar.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.55)),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _submit, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }
}

extension on InvestmentMovementType {
  String get label {
    return switch (this) {
      InvestmentMovementType.contribution => 'Aporte',
      InvestmentMovementType.withdrawal => 'Resgate',
      InvestmentMovementType.income => 'Rendimento',
      InvestmentMovementType.loss => 'Perda',
      InvestmentMovementType.fee => 'Taxa',
    };
  }
}

class _OrphanBanner extends StatelessWidget {
  const _OrphanBanner({
    required this.count,
    required this.net,
    required this.onRemove,
  });

  final int count;
  final Money net;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.warningOf(Theme.of(context).brightness);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '$count movimentação(ões) sem lançamento somam '
              '${formatMoney(net)} na posição.',
              style: AppTypography.label(color)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(onPressed: onRemove, child: const Text('Remover')),
        ],
      ),
    );
  }
}
