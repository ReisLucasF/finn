import 'package:finan/app/app_scope.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/entities/transaction.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/domain/enums/transaction_status.dart';
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

class TransactionFormScreen extends StatefulWidget {
  const TransactionFormScreen({this.type, this.transaction, super.key});

  final TransactionType? type;
  final Transaction? transaction;

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.transaction == null
        ? ''
        : formatMoney(widget.transaction!.amount).replaceFirst('R\$ ', ''),
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.transaction?.description ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.transaction?.notes ?? '',
  );
  late TransactionType _type = _flow(
    widget.transaction?.type ?? widget.type ?? TransactionType.expense,
  );
  late TransactionStatus _status =
      widget.transaction?.status ?? TransactionStatus.confirmed;
  late LocalDate _date;
  late String? _accountId = widget.transaction?.accountId;
  late String? _categoryId = widget.transaction?.categoryId;
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  List<Investment> _investments = const [];
  List<InvestmentProductBucket> _investmentProducts = const [];
  late bool _fundFromInvestment =
      widget.transaction?.pairedTransactionId != null;
  String? _investmentProductLabel;

  /// Investimento cadastrado de onde sai o dinheiro (despesa paga com
  /// investimento). Nulo = produto não vinculado do extrato.
  String? _fundingInvestmentId;
  late String? _linkInvestmentId = widget.transaction?.investmentId;
  bool _loading = true;
  bool _saving = false;
  bool _createdAny = false;
  Object? _error;
  String? _formError;

  bool _dependenciesReady = false;
  static const _investmentCategories = InvestmentCategoryService();

  TransactionType _flow(TransactionType type) {
    return switch (type) {
      TransactionType.investmentContribution => TransactionType.expense,
      TransactionType.investmentWithdrawal => TransactionType.income,
      _ => type,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dependenciesReady) return;
    _dependenciesReady = true;
    _date =
        widget.transaction?.transactionDate ??
        AppScope.of(context).graph.clock.today();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final accounts = await scope.graph.accounts.listByUser(userId);
      final categories = await scope.graph.listCategories(userId);
      final investments = await scope.graph.finance.listInvestments(userId);
      final cash = await scope.graph.transactions.listUnlinkedInvestmentCash(
        userId,
      );
      final products = _investmentCategories.settle(cash).products;
      String? productLabel = _investmentProductLabel;
      final pairId = widget.transaction?.pairedTransactionId;
      String? fundingInvestmentId = _fundingInvestmentId;
      if (pairId != null &&
          (productLabel == null || fundingInvestmentId == null)) {
        final pair = await scope.graph.transactions.findById(pairId);
        productLabel ??= pair?.description;
        fundingInvestmentId ??= pair?.investmentId;
      }
      if (productLabel != null) {
        final key = normalizeInvestmentKey(productLabel);
        for (final product in products) {
          if (product.key == key) {
            productLabel = product.label;
            break;
          }
        }
      }
      // Transferência avulsa (interna): edita como receita/despesa pelo sinal do caixa.
      var flowType = _type;
      final current = widget.transaction;
      if (current != null &&
          current.type == TransactionType.transfer &&
          current.transferId == null) {
        final entries = await scope.graph.transactions.entriesFor(current.id);
        flowType = entries.isNotEmpty && entries.first.amount.cents < 0
            ? TransactionType.expense
            : TransactionType.income;
      }
      if (!mounted) return;
      setState(() {
        _type = flowType;
        _accounts = accounts;
        _categories = categories;
        _investments = [
          for (final item in investments)
            if (item.isActive || item.id == _linkInvestmentId) item,
        ];
        _investmentProducts = [
          for (final product in products)
            if (product.openCapital.cents > 0 ||
                (productLabel != null &&
                    product.key == normalizeInvestmentKey(productLabel)))
              product,
        ];
        _investmentProductLabel = productLabel;
        _fundingInvestmentId = fundingInvestmentId;
        _linkInvestmentId ??= widget.transaction?.investmentId;
        _fundFromInvestment =
            widget.transaction?.pairedTransactionId != null ||
            _fundFromInvestment;
        _loading = false;
        _accountId ??= _firstAccount(accounts)?.id;
        if (widget.transaction == null) {
          _categoryId ??= _firstCategory(categories, _type)?.id;
        } else if (_categoryId != null) {
          final selected = categories
              .where((item) => item.id == _categoryId)
              .firstOrNull;
          if (selected == null || !selected.type.accepts(_type)) {
            _categoryId = _firstCategory(categories, _type)?.id;
          }
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Account? _firstAccount(List<Account> accounts) {
    for (final account in accounts) {
      if (account.isActive) return account;
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  Category? _firstCategory(List<Category> categories, TransactionType type) {
    for (final category in categories) {
      if (category.isActive && category.type.accepts(type)) return category;
    }
    return null;
  }

  List<Account> get _accountOptions {
    return [
      for (final account in _accounts)
        if (account.isActive || account.id == _accountId) account,
    ];
  }

  List<Category> get _categoryOptions {
    return [
      for (final category in _categories)
        if (category.type.accepts(_type) &&
            (category.isActive || category.id == _categoryId))
          category,
    ];
  }

  String? get _categoryHint {
    final category = _categories
        .where((item) => item.id == _categoryId)
        .firstOrNull;
    return switch (category?.type) {
      CategoryType.investmentApplication =>
        'Não entra como despesa. O valor continua no patrimônio até o resgate.',
      CategoryType.investmentRedemption =>
        'Não entra como receita. O que passar da aplicação é rendimento.',
      CategoryType.internalTransfer =>
        'Não entra como receita nem despesa. Use para movimento entre contas '
            'ainda sem transferência cadastrada.',
      _ => null,
    };
  }

  Category? get _selectedCategory {
    return _categories.where((item) => item.id == _categoryId).firstOrNull;
  }

  bool get _isInvestmentCashCategory {
    final type = _selectedCategory?.type;
    return type == CategoryType.investmentApplication ||
        type == CategoryType.investmentRedemption;
  }

  bool get _canFundFromInvestment {
    if (_type != TransactionType.expense) return false;
    return !_isInvestmentCashCategory;
  }

  bool get _canLinkInvestment => _isInvestmentCashCategory;

  List<Investment> get _activeInvestments => [
    for (final item in _investments)
      if (item.isActive || item.id == _fundingInvestmentId) item,
  ];

  /// Valor selecionado no menu "De onde sai o dinheiro".
  String? get _fundingKey {
    final id = _fundingInvestmentId;
    if (id != null) {
      return _activeInvestments.any((item) => item.id == id) ? 'inv:$id' : null;
    }
    final label = _investmentProductLabel;
    return label != null && _productLabelOptions.contains(label)
        ? 'prod:$label'
        : null;
  }

  List<String> get _productLabelOptions {
    final labels = <String>{
      for (final product in _investmentProducts) product.label,
      if (_investmentProductLabel != null &&
          _investmentProductLabel!.trim().isNotEmpty)
        _investmentProductLabel!.trim(),
    };
    return labels.toList()..sort();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _date = LocalDate(picked.year, picked.month, picked.day));
  }

  Future<void> _save({bool continueEditing = false}) async {
    final amount = tryParseMoney(_amount.text);
    if (amount == null || amount.cents <= 0) {
      setState(() => _formError = 'Informe um valor maior que zero.');
      return;
    }
    final accountId = _accountId;
    if (accountId == null) {
      setState(() => _formError = 'Escolha a conta.');
      return;
    }
    if (_type != TransactionType.income && _type != TransactionType.expense) {
      setState(
        () => _formError =
            'Transferência entre contas cadastradas não usa categoria. '
            'Para movimento avulso, use a categoria Transferências internas.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final scope = AppScope.of(context);
      final current = widget.transaction;
      if (current == null) {
        await scope.graph.createTransaction(
          userId: scope.session.user.id,
          type: _type,
          amount: amount,
          transactionDate: _date,
          accountId: accountId,
          categoryId: _categoryId,
          description: _description.text,
          notes: _notes.text,
          status: _status,
          fundFromInvestment: _canFundFromInvestment && _fundFromInvestment,
          investmentProductLabel: _investmentProductLabel,
          fundingInvestmentId: _fundingInvestmentId,
          linkInvestmentId: _canLinkInvestment ? _linkInvestmentId : null,
        );
      } else {
        await scope.graph.updateTransaction(
          id: current.id,
          type: _type,
          amount: amount,
          transactionDate: _date,
          accountId: accountId,
          categoryId: _categoryId,
          status: _status,
          description: _description.text,
          notes: _notes.text,
          fundFromInvestment: _canFundFromInvestment && _fundFromInvestment,
          investmentProductLabel: _investmentProductLabel,
          // Escolha explícita: '' = produto do extrato, sem investimento.
          fundingInvestmentId: _fundingInvestmentId ?? '',
          // '' = desvincular; id = vincular; null = não mexer no vínculo
          linkInvestmentId: _canLinkInvestment
              ? (_linkInvestmentId ?? '')
              : null,
        );
      }
      if (!mounted) return;
      if (continueEditing && current == null) {
        _createdAny = true;
        _amount.clear();
        _description.clear();
        _notes.clear();
        setState(() => _saving = false);
        showSuccess(context, 'Salvo. Pode lançar o próximo.');
        return;
      }
      showSuccess(
        context,
        current == null ? 'Lançamento criado' : 'Lançamento atualizado',
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = friendlyError(error);
      });
    }
  }

  Future<void> _delete() async {
    final current = widget.transaction;
    if (current == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Excluir lançamento',
      message: 'O lançamento sai do saldo e dos totais. O histórico é mantido.',
      confirmLabel: 'Excluir',
    );
    if (!confirmed || !mounted) return;
    try {
      await AppScope.of(context).graph.deleteTransaction(current.id);
      if (!mounted) return;
      showSuccess(context, 'Lançamento excluído');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _formError = friendlyError(error));
    }
  }

  void _setType(TransactionType type) {
    setState(() {
      _type = type;
      if (type != TransactionType.expense) {
        _fundFromInvestment = false;
      }
      final category = _categories
          .where((item) => item.id == _categoryId)
          .firstOrNull;
      if (_categoryId != null &&
          (category == null || !category.type.accepts(type))) {
        _categoryId = _firstCategory(_categories, type)?.id;
      }
    });
  }

  void _setCategory(String? id) {
    setState(() {
      _categoryId = id;
      if (!_isInvestmentCashCategory) {
        _linkInvestmentId = widget.transaction?.investmentId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.transaction != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _createdAny);
      },
      child: FinanPage(
        title: editing ? 'Editar lançamento' : 'Novo lançamento',
        subtitle: editing
            ? 'Altere e salve para atualizar saldos e totais'
            : 'Registre uma receita ou despesa',
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: () => Navigator.pop(context, _createdAny),
          icon: Icon(
            CupertinoIcons.chevron_back,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        maxContentWidth: 760,
        body: _loading
            ? const LoadingSkeleton()
            : _error != null
            ? ErrorView(
                message: 'Não foi possível carregar o lançamento.',
                onRetry: () => _load(showLoading: true),
              )
            : _form(context, editing),
      ),
    );
  }

  Widget _form(BuildContext context, bool editing) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final today = AppScope.of(context).graph.clock.today();
    final flow =
        _type == TransactionType.income || _type == TransactionType.expense;
    final tone = _type == TransactionType.income
        ? AppColors.incomeOf(brightness)
        : _type == TransactionType.expense
        ? AppColors.expenseOf(brightness)
        : scheme.primary;
    var order = 0;
    Widget step(Widget child) => FadeSlideIn(index: order++, child: child);

    return ListView(
      padding: screenPadding(context),
      children: [
        // Valor em destaque, colorido pelo tipo.
        step(
          FinanCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (flow)
                  _TypeToggle(
                    value: _type,
                    enabled: !_saving,
                    onChanged: _setType,
                  )
                else
                  Center(
                    child: DeltaChip(label: _type.label, color: tone),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Valor em R\$',
                  textAlign: TextAlign.center,
                  style: AppTypography.label(
                    scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                TextField(
                  controller: _amount,
                  autofocus: !editing,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppTypography.display(tone).copyWith(fontSize: 40),
                  cursorColor: tone,
                  decoration: InputDecoration(
                    hintText: '0,00',
                    hintStyle: AppTypography.display(
                      scheme.onSurface.withValues(alpha: 0.2),
                    ).copyWith(fontSize: 40),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _description,
                  textCapitalization: TextCapitalization.sentences,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: 'Descrição (ex.: Mercado, Salário)',
                    prefixIcon: Icon(CupertinoIcons.text_alignleft, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        step(
          FinanCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FieldLabel(icon: CupertinoIcons.creditcard, text: 'Conta'),
                const SizedBox(height: AppSpacing.xs),
                if (_accountOptions.isEmpty)
                  Text(
                    'Crie uma conta ativa antes de lançar.',
                    style: TextStyle(color: scheme.error),
                  )
                else
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final account in _accountOptions)
                        FinanPill(
                          label: account.name,
                          icon: CupertinoIcons.building_2_fill,
                          selected: _accountId == account.id,
                          onTap: () {
                            if (_saving) return;
                            setState(() => _accountId = account.id);
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.lg),
                _FieldLabel(icon: CupertinoIcons.tag, text: 'Categoria'),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final category in _categoryOptions)
                      FinanPill(
                        label: category.name,
                        icon: iconFromName(category.icon),
                        selected: _categoryId == category.id,
                        onTap: () {
                          if (_saving) return;
                          _setCategory(category.id);
                        },
                      ),
                    FinanPill(
                      label: 'Sem categoria',
                      icon: CupertinoIcons.minus_circle,
                      selected: _categoryId == null,
                      onTap: () {
                        if (_saving) return;
                        _setCategory(null);
                      },
                    ),
                  ],
                ),
                if (_categoryHint != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _Hint(
                    text: _categoryHint!,
                    color: AppColors.infoOf(brightness),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _FieldLabel(icon: CupertinoIcons.calendar, text: 'Data'),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    FinanPill(
                      label: 'Hoje',
                      selected: _date == today,
                      onTap: () {
                        if (_saving) return;
                        setState(() => _date = today);
                      },
                    ),
                    FinanPill(
                      label: 'Ontem',
                      selected: _date == today.addDays(-1),
                      onTap: () {
                        if (_saving) return;
                        setState(() => _date = today.addDays(-1));
                      },
                    ),
                    FinanPill(
                      label: _date == today || _date == today.addDays(-1)
                          ? 'Outra data'
                          : formatLocalDate(_date),
                      icon: CupertinoIcons.calendar,
                      selected: _date != today && _date != today.addDays(-1),
                      onTap: () {
                        if (_saving) return;
                        _pickDate();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_canLinkInvestment || _canFundFromInvestment) ...[
          const SizedBox(height: AppSpacing.md),
          step(FinanCard(child: _investmentSection(context))),
        ],
        const SizedBox(height: AppSpacing.md),
        step(
          FinanCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded:
                    _status != TransactionStatus.confirmed ||
                    _notes.text.isNotEmpty,
                leading: Icon(
                  CupertinoIcons.slider_horizontal_3,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
                title: Text(
                  'Mais opções',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  'Status ${_status.label.toLowerCase()}'
                  '${_notes.text.isNotEmpty ? ' · com notas' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel(
                    icon: CupertinoIcons.checkmark_circle,
                    text: 'Status',
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final status in [
                        TransactionStatus.confirmed,
                        TransactionStatus.pending,
                        if (editing) TransactionStatus.cancelled,
                      ])
                        FinanPill(
                          label: status.label,
                          selected: _status == status,
                          onTap: () {
                            if (_saving) return;
                            setState(() => _status = status);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notas'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_formError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _Hint(text: _formError!, color: scheme.error),
        ],
        const SizedBox(height: AppSpacing.lg),
        step(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _saving || _accountOptions.isEmpty
                    ? null
                    : () => _save(),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.checkmark_alt, size: 18),
                label: Text(_saving ? 'Salvando...' : 'Salvar'),
              ),
              if (!editing) ...[
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _saving || _accountOptions.isEmpty
                      ? null
                      : () => _save(continueEditing: true),
                  icon: const Icon(CupertinoIcons.add, size: 18),
                  label: const Text('Salvar e lançar outro'),
                ),
              ],
              if (editing) ...[
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(CupertinoIcons.trash, size: 18),
                  label: const Text('Excluir lançamento'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _investmentSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(icon: CupertinoIcons.chart_pie, text: 'Investimento'),
        const SizedBox(height: AppSpacing.sm),
        if (_canLinkInvestment) ...[
          DropdownButtonFormField<String?>(
            key: ValueKey('link-${_linkInvestmentId ?? 'none'}'),
            initialValue:
                _investments.any((item) => item.id == _linkInvestmentId)
                ? _linkInvestmentId
                : null,
            decoration: const InputDecoration(
              labelText: 'Investimento (opcional)',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Não vincular'),
              ),
              for (final item in _investments)
                DropdownMenuItem<String?>(
                  value: item.id,
                  child: Text(
                    '${item.name} · ${formatMoney(item.currentValue)}',
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _linkInvestmentId = value),
          ),
          if (widget.transaction?.investmentId != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Para desvincular, escolha “Não vincular” e salve.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _saving
                    ? null
                    : () async {
                        final scope = AppScope.of(context);
                        final transactionId = widget.transaction!.id;
                        final ok = await confirmAction(
                          context,
                          title: 'Desvincular investimento',
                          message:
                              'O lançamento volta para “não vinculados” '
                              'e sai da posição deste investimento.',
                          confirmLabel: 'Desvincular',
                        );
                        if (!ok || !mounted) return;
                        try {
                          await scope.graph.unlinkInvestmentCash(
                            userId: scope.session.user.id,
                            transactionId: transactionId,
                          );
                          if (!mounted) return;
                          setState(() => _linkInvestmentId = null);
                          showSuccess(context, 'Desvinculado');
                          Navigator.pop(context, true);
                        } catch (error) {
                          if (!mounted) return;
                          setState(() => _formError = friendlyError(error));
                        }
                      },
                child: const Text('Desvincular agora'),
              ),
            ),
          ] else if (_investments.isEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Cadastre um investimento em Investimentos para vincular.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
        if (_canFundFromInvestment) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Paga com dinheiro investido'),
            subtitle: const Text(
              'Gera um resgate que entra na conta e cobre a despesa: o saldo '
              'da conta não muda e o valor sai do investimento.',
            ),
            value: _fundFromInvestment,
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _fundFromInvestment = value;
                    final hasChoice =
                        _fundingInvestmentId != null ||
                        (_investmentProductLabel?.isNotEmpty ?? false);
                    if (!value || hasChoice) return;
                    final active = _activeInvestments;
                    if (active.isNotEmpty) {
                      _fundingInvestmentId = active.first.id;
                      _investmentProductLabel = active.first.name;
                    } else if (_productLabelOptions.isNotEmpty) {
                      _investmentProductLabel = _productLabelOptions.first;
                    }
                  }),
          ),
          if (_fundFromInvestment) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(
                'fund-${_fundingInvestmentId ?? _investmentProductLabel ?? ''}',
              ),
              initialValue: _fundingKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'De onde sai o dinheiro',
              ),
              items: [
                for (final item in _activeInvestments)
                  DropdownMenuItem(
                    value: 'inv:${item.id}',
                    child: Text(
                      '${item.name} · ${formatMoney(item.currentValue)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final label in _productLabelOptions)
                  DropdownMenuItem(
                    value: 'prod:$label',
                    child: Text(
                      '$label · do extrato (não vinculado)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      if (value == null) return;
                      if (value.startsWith('inv:')) {
                        final id = value.substring(4);
                        _fundingInvestmentId = id;
                        _investmentProductLabel = _investments
                            .firstWhere((item) => item.id == id)
                            .name;
                      } else {
                        _fundingInvestmentId = null;
                        _investmentProductLabel = value.substring(5);
                      }
                    }),
            ),
            if (_fundingInvestmentId != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'O valor da despesa sai da posição deste investimento.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_productLabelOptions.isEmpty && _activeInvestments.isEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Nome do produto',
                  hintText: 'Ex.: Emergências',
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (value) => _investmentProductLabel = value.trim(),
              ),
            ],
          ],
        ],
      ],
    );
  }
}

/// Seletor Receita/Despesa com cores do tipo.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final TransactionType value;
  final bool enabled;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    Widget option(TransactionType type, String label, IconData icon) {
      final selected = value == type;
      final color = type == TransactionType.income
          ? AppColors.incomeOf(brightness)
          : AppColors.expenseOf(brightness);
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: Pressable(
            onTap: enabled ? () => onChanged(type) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: selected ? color : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? color
                        : scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: AppTypography.label(
                      selected
                          ? color
                          : scheme.onSurface.withValues(alpha: 0.6),
                    ).copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 4),
      ),
      child: Row(
        children: [
          option(
            TransactionType.income,
            'Receita',
            CupertinoIcons.arrow_down_left,
          ),
          const SizedBox(width: 4),
          option(
            TransactionType.expense,
            'Despesa',
            CupertinoIcons.arrow_up_right,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.6);
    return Row(
      children: [
        Icon(icon, size: 15, color: muted),
        const SizedBox(width: 6),
        Text(text, style: AppTypography.label(muted)),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.info_circle, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: AppTypography.label(color)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
