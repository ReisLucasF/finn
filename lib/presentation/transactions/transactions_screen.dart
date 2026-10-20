import 'package:finan/app/app_config.dart';
import 'package:finan/app/app_scope.dart';
import 'package:finan/app/router.dart';
import 'package:finan/application/transactions/closing_balances.dart';
import 'package:finan/application/transactions/list_transactions.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_status.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/finan_widgets.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:finan/presentation/transfers/transfer_pair_prompt.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _periodPresets = <TransactionPeriod>[
  TransactionPeriod.currentMonth,
  TransactionPeriod.previousMonth,
  TransactionPeriod.last3Months,
  TransactionPeriod.last6Months,
  TransactionPeriod.yearToDate,
  TransactionPeriod.all,
];

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({required this.refreshTick, super.key});

  final int refreshTick;

  @override
  State<TransactionsScreen> createState() => TransactionsScreenState();
}

class TransactionsScreenState extends State<TransactionsScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<Transaction> _items = const [];
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  Map<(String, LocalDate), Money> _balances = const {};
  LocalDate? _nextDate;
  int _total = 0;
  TransactionType? _type;
  String? _accountId;
  final Set<String> _categoryIds = {};
  bool _includeUncategorized = false;
  String _appliedSearch = '';
  TransactionPeriod _period = TransactionPeriod.currentMonth;
  bool _newestFirst = true;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didUpdateWidget(covariant TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _load(silent: _items.isNotEmpty);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false, bool append = false}) async {
    final request = ++_request;
    final savedOffset = silent && !append && _scroll.hasClients
        ? _scroll.offset
        : null;
    if (!silent && !append) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    if (append) setState(() => _loadingMore = true);
    final limit = append || !silent
        ? AppConfig.transactionPageSize
        : (_items.length < AppConfig.transactionPageSize
              ? AppConfig.transactionPageSize
              : _items.length);
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final search = _search.text;
      final accounts = await scope.graph.accounts.listByUser(userId);
      final categories = await scope.graph.listCategories(userId);
      final page = await scope.graph.listTransactions(
        userId: userId,
        type: _type,
        accountId: _accountId,
        categoryIds: _categoryIds.isEmpty ? null : _categoryIds.toList(),
        includeUncategorized: _includeUncategorized,
        uncategorizedOnly: _includeUncategorized && _categoryIds.isEmpty,
        period: _period,
        search: search,
        newestFirst: _newestFirst,
        limit: limit,
        offset: append ? _items.length : 0,
      );
      if (!mounted || request != _request) return;
      final items = append ? [..._items, ...page.items] : page.items;
      final totals = await scope.graph.transactions.confirmedDailyTotals(
        userId,
      );
      if (!mounted || request != _request) return;
      final balances = closingBalances(
        accounts: accounts,
        totals: totals,
        points: closingPoints(
          items: items,
          nextDate: page.nextDate,
          accountId: _accountId,
        ),
      );
      setState(() {
        _accounts = accounts;
        _categories = categories;
        _items = items;
        _balances = balances;
        _nextDate = page.nextDate;
        _total = page.total;
        _appliedSearch = search;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      if (savedOffset == null) {
        if (!silent && !append) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            _scroll.jumpTo(0);
          });
        }
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final maxExtent = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(savedOffset > maxExtent ? maxExtent : savedOffset);
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _applyFilter(VoidCallback change) {
    setState(change);
    _load();
  }

  Future<void> _selectPeriod(TransactionPeriod period) async {
    if (period.kind == TransactionPeriodKind.custom) {
      await _pickCustomPeriod();
      return;
    }
    if (period == _period) return;
    _applyFilter(() => _period = period);
  }

  Future<void> _pickCustomPeriod() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          _period.customStart != null && _period.customEndInclusive != null
          ? DateTimeRange(
              start: DateTime(
                _period.customStart!.year,
                _period.customStart!.month,
                _period.customStart!.day,
              ),
              end: DateTime(
                _period.customEndInclusive!.year,
                _period.customEndInclusive!.month,
                _period.customEndInclusive!.day,
              ),
            )
          : null,
      helpText: 'Período do extrato',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
      saveText: 'Aplicar',
    );
    if (picked == null || !mounted) return;
    _applyFilter(() {
      _period = TransactionPeriod.custom(
        start: LocalDate.fromDateTime(picked.start),
        endInclusive: LocalDate.fromDateTime(picked.end),
      );
    });
  }

  String get _periodLabel {
    if (_period.kind == TransactionPeriodKind.custom &&
        _period.customStart != null &&
        _period.customEndInclusive != null) {
      return '${formatLocalDate(_period.customStart!)} – '
          '${formatLocalDate(_period.customEndInclusive!)}';
    }
    return _period.label;
  }

  Future<void> _open(Transaction transaction) async {
    final saved = await AppRouter.openTransactionForm(
      context,
      transaction: transaction,
    );
    if (saved == true) await _load(silent: true);
  }

  Future<void> _recategorize() async {
    final options = [
      for (final category in _categories)
        if (category.isActive &&
            category.deletedAt == null &&
            (_type == null || category.type.accepts(_type!)))
          category,
    ];
    if (options.isEmpty || !mounted) return;
    var selected = options.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final category = options.firstWhere((item) => item.id == selected);
            final scope = switch (category.type) {
              CategoryType.income =>
                'receitas, resgates e transferências internas '
                    '(voltam a ser receita)',
              CategoryType.expense =>
                'despesas, aplicações e transferências internas '
                    '(voltam a ser despesa)',
              CategoryType.both => 'receitas e despesas',
              CategoryType.investmentApplication =>
                'despesas, que passam a ser aplicação e saem das despesas',
              CategoryType.investmentRedemption =>
                'receitas, que passam a ser resgate e saem das receitas',
              CategoryType.internalTransfer =>
                'receitas e despesas, que passam a transferência interna '
                    'e saem das somas da dashboard',
            };
            return AlertDialog(
              title: const Text('Trocar categoria'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'O filtro atual tem $_total lançamentos. '
                    'A nova categoria entra nas $scope compatíveis '
                    '(nome, categoria atual, conta e período). '
                    'Transferências não mudam.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selected),
                    initialValue: selected,
                    decoration: const InputDecoration(
                      labelText: 'Nova categoria',
                    ),
                    items: [
                      for (final item in options)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text('${item.name} · ${item.type.label}'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setLocal(() => selected = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      final scope = AppScope.of(context);
      final updated = await scope.graph.recategorizeTransactions(
        userId: scope.session.user.id,
        categoryId: selected,
        type: _type,
        accountId: _accountId,
        currentCategoryIds: _categoryIds.isEmpty ? null : _categoryIds.toList(),
        includeUncategorized: _includeUncategorized,
        uncategorizedOnly: _includeUncategorized && _categoryIds.isEmpty,
        period: _period,
        search: _appliedSearch,
      );
      if (!mounted) return;
      await _load(silent: true);
      if (!mounted) return;
      final message = await _recategorizeMessage(updated, selected);
      if (!mounted) return;
      showSuccess(context, message);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<String> _recategorizeMessage(int updated, String categoryId) async {
    if (updated == 1) return '1 lançamento atualizado.';
    if (updated > 1) return '$updated lançamentos atualizados.';
    final name =
        _categories
            .where((category) => category.id == categoryId)
            .firstOrNull
            ?.name ??
        'essa categoria';
    final filtering = _includeUncategorized || _categoryIds.isNotEmpty;
    if (filtering && !_categoryIds.contains(categoryId)) {
      return 'Nenhum lançamento compatível com essa categoria.';
    }
    if (_categoryIds.length == 1 && _categoryIds.contains(categoryId)) {
      return 'Esses lançamentos já estão em $name.';
    }
    final scope = AppScope.of(context);
    final already = await scope.graph.listTransactions(
      userId: scope.session.user.id,
      type: _type,
      accountId: _accountId,
      categoryIds: [categoryId],
      period: _period,
      search: _appliedSearch,
      limit: 1,
    );
    return already.total > 0
        ? 'Esses lançamentos já estão em $name.'
        : 'Nenhum lançamento compatível com essa categoria.';
  }

  String get _categoryFilterLabel {
    if (_includeUncategorized && _categoryIds.isEmpty) {
      return 'Sem categoria';
    }
    if (!_includeUncategorized && _categoryIds.isEmpty) {
      return 'Todas';
    }
    final names = [
      for (final category in _categories)
        if (_categoryIds.contains(category.id)) category.name,
    ];
    if (_includeUncategorized) names.insert(0, 'Sem categoria');
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]}, ${names[1]}';
    return '${names.length} categorias';
  }

  Future<void> _pickCategories() async {
    var selectedIds = {..._categoryIds};
    var includeUncategorized = _includeUncategorized;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Categorias'),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Todas'),
                        value: !includeUncategorized && selectedIds.isEmpty,
                        onChanged: (_) => setLocal(() {
                          includeUncategorized = false;
                          selectedIds = {};
                        }),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Sem categoria'),
                        value: includeUncategorized,
                        onChanged: (value) => setLocal(() {
                          includeUncategorized = value ?? false;
                        }),
                      ),
                      const Divider(height: AppSpacing.md),
                      for (final category in _categories)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${category.name} · ${category.type.label}',
                          ),
                          value: selectedIds.contains(category.id),
                          onChanged: (value) => setLocal(() {
                            if (value == true) {
                              selectedIds.add(category.id);
                            } else {
                              selectedIds.remove(category.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    _applyFilter(() {
      _categoryIds
        ..clear()
        ..addAll(selectedIds);
      _includeUncategorized = includeUncategorized;
    });
  }

  String get _accountFilterLabel {
    if (_accountId == null) return 'Todas as contas';
    return _accounts
            .where((account) => account.id == _accountId)
            .firstOrNull
            ?.name ??
        'Conta';
  }

  Future<void> _pickAccount() async {
    final picked = await showModalBottomSheet<(String?,)>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        Widget option(String? id, String label, IconData icon) => ListTile(
          leading: Icon(icon, color: scheme.primary),
          title: Text(label),
          trailing: _accountId == id
              ? Icon(CupertinoIcons.checkmark_alt, color: scheme.primary)
              : null,
          onTap: () => Navigator.pop(context, (id,)),
        );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  0,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Text(
                  'Filtrar por conta',
                  style: AppTypography.headline(scheme.onSurface),
                ),
              ),
              option(
                null,
                'Todas as contas',
                CupertinoIcons.square_stack_3d_up,
              ),
              for (final account in _accounts)
                option(account.id, account.name, CupertinoIcons.creditcard),
            ],
          ),
        );
      },
    );
    if (picked == null || picked.$1 == _accountId) return;
    _applyFilter(() => _accountId = picked.$1);
  }

  bool get _hasExtraFilters =>
      _type != null ||
      _accountId != null ||
      _categoryIds.isNotEmpty ||
      _includeUncategorized ||
      _appliedSearch.isNotEmpty;

  void _clearFilters() {
    _search.clear();
    _applyFilter(() {
      _type = null;
      _accountId = null;
      _categoryIds.clear();
      _includeUncategorized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categoryNames = {
      for (final category in _categories) category.id: category.name,
    };
    final categoriesById = {
      for (final category in _categories) category.id: category,
    };
    final subtitleParts = <String>[_periodLabel];
    if (_total > 0) {
      subtitleParts.insert(
        0,
        '$_total ${_total == 1 ? 'lançamento' : 'lançamentos'}',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return FinanPage(
      title: 'Extrato',
      subtitle: subtitleParts.join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Trocar categoria do filtro',
            onPressed: _loading || _total == 0 ? null : _recategorize,
            icon: const Icon(CupertinoIcons.tag),
          ),
          const SizedBox(width: AppSpacing.xxs),
          IconButton.filledTonal(
            tooltip: 'Importar OFX',
            onPressed: () async {
              final saved = await AppRouter.openOfxImport(context);
              if (!context.mounted) return;
              final changed = await TransferPairPrompt.maybeShow(context);
              if (!context.mounted) return;
              if (saved == true || changed) await _load(silent: true);
            },
            icon: const Icon(CupertinoIcons.arrow_down_doc),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListenableBuilder(
                  listenable: _search,
                  builder: (context, _) => TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText:
                          'Buscar descrição ou valor (ex.: Uber, 1.307,62)',
                      prefixIcon: const Icon(CupertinoIcons.search, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpar busca',
                              icon: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                                size: 18,
                              ),
                              onPressed: () {
                                _search.clear();
                                _load();
                              },
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _PillRow(
                  children: [
                    for (final period in _periodPresets)
                      FinanPill(
                        label: period.label,
                        selected: _period.kind == period.kind,
                        onTap: () => _selectPeriod(period),
                      ),
                    FinanPill(
                      label: _period.kind == TransactionPeriodKind.custom
                          ? _periodLabel
                          : 'Personalizado',
                      icon: CupertinoIcons.calendar,
                      selected: _period.kind == TransactionPeriodKind.custom,
                      onTap: () => _selectPeriod(
                        const TransactionPeriod(
                          kind: TransactionPeriodKind.custom,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _PillRow(
                  children: [
                    FinanPill(
                      label: 'Todos os tipos',
                      selected: _type == null,
                      onTap: () => _applyFilter(() => _type = null),
                    ),
                    FinanPill(
                      label: 'Receitas',
                      icon: CupertinoIcons.arrow_down_left,
                      selected: _type == TransactionType.income,
                      onTap: () =>
                          _applyFilter(() => _type = TransactionType.income),
                    ),
                    FinanPill(
                      label: 'Despesas',
                      icon: CupertinoIcons.arrow_up_right,
                      selected: _type == TransactionType.expense,
                      onTap: () =>
                          _applyFilter(() => _type = TransactionType.expense),
                    ),
                    Container(width: 1, height: 22, color: scheme.outline),
                    FinanPill(
                      label: _accountFilterLabel,
                      icon: CupertinoIcons.creditcard,
                      trailingIcon: CupertinoIcons.chevron_down,
                      selected: _accountId != null,
                      onTap: _pickAccount,
                    ),
                    FinanPill(
                      label: _categoryFilterLabel == 'Todas'
                          ? 'Categorias'
                          : _categoryFilterLabel,
                      icon: CupertinoIcons.tag,
                      trailingIcon: CupertinoIcons.chevron_down,
                      selected:
                          _categoryIds.isNotEmpty || _includeUncategorized,
                      onTap: _pickCategories,
                    ),
                    FinanPill(
                      label: _newestFirst ? 'Mais recentes' : 'Mais antigos',
                      icon: _newestFirst
                          ? CupertinoIcons.arrow_down
                          : CupertinoIcons.arrow_up,
                      selected: false,
                      onTap: () =>
                          _applyFilter(() => _newestFirst = !_newestFirst),
                    ),
                    if (_hasExtraFilters)
                      TextButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(CupertinoIcons.xmark, size: 14),
                        label: const Text('Limpar filtros'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _body(categoryNames, categoriesById)),
        ],
      ),
    );
  }

  Widget _body(
    Map<String, String> categoryNames,
    Map<String, Category> categoriesById,
  ) {
    if (_loading) return const LoadingSkeleton();
    if (_error != null && _items.isEmpty) {
      return ErrorView(
        message: 'Não foi possível carregar os lançamentos.',
        onRetry: _load,
      );
    }
    if (_items.isEmpty) {
      return EmptyView(
        icon: CupertinoIcons.doc_text_search,
        message: 'Nenhum lançamento encontrado.',
        detail: _hasExtraFilters
            ? 'Tente outro período ou limpe os filtros.'
            : 'Use o botão + para lançar ou importe um extrato OFX.',
        actionLabel: _hasExtraFilters ? 'Limpar filtros' : null,
        onAction: _hasExtraFilters ? _clearFilters : null,
      );
    }
    final groups = _groupByDay(_items);
    final hasMore = _items.length < _total;
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          96,
        ),
        itemCount: groups.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= groups.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: OutlinedButton.icon(
                onPressed: _loadingMore
                    ? null
                    : () => _load(append: true, silent: true),
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.chevron_down, size: 16),
                label: Text(
                  _loadingMore
                      ? 'Carregando...'
                      : 'Carregar mais (${_total - _items.length} restantes)',
                ),
              ),
            );
          }
          final group = groups[index];
          final dayComplete =
              index < groups.length - 1 || _nextDate != group.date;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FadeSlideIn(
              index: index.clamp(0, 6),
              offset: 12,
              child: _DayGroup(
                dateLabel: _dayLabel(group.date),
                transactions: group.items,
                categoryNames: categoryNames,
                categories: categoriesById,
                balances: dayComplete ? _balancesForDay(group.date) : const [],
                onOpen: _open,
                subtitleOf: _subtitle,
              ),
            ),
          );
        },
      ),
    );
  }

  List<_DayBucket> _groupByDay(List<Transaction> items) {
    final groups = <_DayBucket>[];
    for (final item in items) {
      if (groups.isEmpty || groups.last.date != item.transactionDate) {
        groups.add(_DayBucket(date: item.transactionDate, items: [item]));
      } else {
        groups.last.items.add(item);
      }
    }
    return groups;
  }

  String _dayLabel(LocalDate date) {
    final today = LocalDate.fromDateTime(DateTime.now());
    if (date == today) return 'Hoje · ${formatLocalDate(date)}';
    if (date == today.addDays(-1)) return 'Ontem · ${formatLocalDate(date)}';
    return formatLocalDate(date);
  }

  String _subtitle(Transaction transaction, Map<String, String> categoryNames) {
    final category = categoryNames[transaction.categoryId];
    var type = category == null
        ? transaction.type.label
        : '${transaction.type.label} · $category';
    if (transaction.type == TransactionType.expense &&
        transaction.pairedTransactionId != null) {
      type = '$type · paga com investimento';
    } else if (transaction.type == TransactionType.investmentWithdrawal &&
        transaction.pairedTransactionId != null) {
      type = '$type · vinculada à despesa';
    }
    return transaction.status == TransactionStatus.confirmed
        ? type
        : '$type · ${transaction.status.label}';
  }

  List<(String, Money)> _balancesForDay(LocalDate date) {
    final ids = <String>{};
    if (_accountId != null) {
      ids.add(_accountId!);
    } else {
      for (final item in _items) {
        if (item.transactionDate != date) continue;
        final id = item.accountId;
        if (id != null) ids.add(id);
      }
    }
    final accounts = [
      for (final id in ids)
        ?_accounts.where((account) => account.id == id).firstOrNull,
    ]..sort((a, b) => a.name.compareTo(b.name));
    return [
      for (final account in accounts)
        if (_balances[(account.id, date)] case final balance?)
          (
            _accountId == null
                ? 'Saldo do dia · ${account.name}'
                : 'Saldo do dia',
            balance,
          ),
    ];
  }
}

class _DayBucket {
  _DayBucket({required this.date, required this.items});

  final LocalDate date;
  final List<Transaction> items;
}

class _PillRow extends StatelessWidget {
  const _PillRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xs),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.dateLabel,
    required this.transactions,
    required this.categoryNames,
    required this.categories,
    required this.balances,
    required this.onOpen,
    required this.subtitleOf,
  });

  final String dateLabel;
  final List<Transaction> transactions;
  final Map<String, String> categoryNames;
  final Map<String, Category> categories;
  final List<(String, Money)> balances;
  final ValueChanged<Transaction> onOpen;
  final String Function(Transaction, Map<String, String>) subtitleOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    // Resultado do dia: entradas menos saídas (transferências não contam).
    var net = 0;
    for (final item in transactions) {
      final signed = signedAmount(item.type, item.amount);
      if (signed.startsWith('+')) net += item.amount.cents;
      if (signed.startsWith('−')) net -= item.amount.cents;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            0,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dateLabel.toUpperCase(),
                  style: AppTypography.label(
                    scheme.onSurface.withValues(alpha: 0.5),
                  ).copyWith(letterSpacing: 0.8, fontSize: 12),
                ),
              ),
              if (net != 0)
                Text(
                  '${net > 0 ? '+' : '−'}${formatMoney(Money(net.abs()))}',
                  style: AppTypography.label(
                    net > 0
                        ? AppColors.incomeOf(brightness)
                        : scheme.onSurface.withValues(alpha: 0.55),
                  ).copyWith(fontSize: 12),
                ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: FinanCard.decoration(context, radius: AppSpacing.radius),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < transactions.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: AppSpacing.hairline,
                      indent: 66,
                      endIndent: AppSpacing.md,
                      color: scheme.outline.withValues(alpha: 0.6),
                    ),
                  _TransactionRow(
                    transaction: transactions[i],
                    category: categories[transactions[i].categoryId],
                    title:
                        transactions[i].description ??
                        categoryNames[transactions[i].categoryId] ??
                        transactions[i].type.label,
                    subtitle: subtitleOf(transactions[i], categoryNames),
                    onTap: () => onOpen(transactions[i]),
                  ),
                ],
                if (balances.isNotEmpty)
                  Container(
                    color: scheme.onSurface.withValues(alpha: 0.03),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      children: [
                        for (final entry in balances)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.equal_circle,
                                  size: 14,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    entry.$1,
                                    style: AppTypography.label(
                                      scheme.onSurface.withValues(alpha: 0.55),
                                    ).copyWith(fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(
                                  formatMoney(entry.$2),
                                  style: AppTypography.label(
                                    entry.$2.cents < 0
                                        ? AppColors.expenseOf(brightness)
                                        : scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.category,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Transaction transaction;
  final Category? category;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final amount = signedAmount(transaction.type, transaction.amount);
    final incoming = amount.startsWith('+');
    final pending = transaction.status != TransactionStatus.confirmed;
    final fallback = switch (transaction.type) {
      TransactionType.transfer => CupertinoIcons.arrow_right_arrow_left,
      TransactionType.creditCardPayment => CupertinoIcons.creditcard,
      TransactionType.investmentContribution ||
      TransactionType.investmentWithdrawal ||
      TransactionType.investmentIncome ||
      TransactionType.investmentLoss => CupertinoIcons.chart_pie,
      TransactionType.income => CupertinoIcons.arrow_down_left,
      TransactionType.expense => CupertinoIcons.bag,
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        child: Row(
          children: [
            CategoryBadge(
              category: category,
              fallbackIcon: fallback,
              fallbackColor: incoming
                  ? AppColors.incomeOf(brightness)
                  : scheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amount,
                  style: AppTypography.label(
                    incoming
                        ? AppColors.incomeOf(brightness)
                        : scheme.onSurface,
                  ).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (pending) ...[
                  const SizedBox(height: 3),
                  DeltaChip(
                    label: transaction.status.label,
                    color: AppColors.warningOf(brightness),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
