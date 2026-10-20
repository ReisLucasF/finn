import 'package:finan/app/app_scope.dart';
import 'package:finan/app/router.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/enums/category_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({required this.refreshTick, super.key});

  final int refreshTick;

  @override
  State<CategoriesScreen> createState() => CategoriesScreenState();
}

class CategoriesScreenState extends State<CategoriesScreen> {
  List<Category> _categories = const [];
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
  void didUpdateWidget(covariant CategoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      _load(silent: _categories.isNotEmpty);
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
      final categories = await scope.graph.listCategories(
        scope.session.user.id,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _categories = categories;
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

  Future<void> _open({Category? category}) async {
    final saved = await AppRouter.openCategoryForm(context, category: category);
    if (saved == true) await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final income = [
      for (final category in _categories)
        if (category.type == CategoryType.income ||
            category.type == CategoryType.both)
          category,
    ];
    final expense = [
      for (final category in _categories)
        if (category.type == CategoryType.expense ||
            category.type == CategoryType.both)
          category,
    ];
    final investment = [
      for (final category in _categories)
        if (category.type == CategoryType.investmentApplication ||
            category.type == CategoryType.investmentRedemption)
          category,
    ];
    final transfers = [
      for (final category in _categories)
        if (category.type == CategoryType.internalTransfer) category,
    ];
    return FinanPage(
      title: 'Categorias',
      subtitle: 'Receitas, despesas, aportes e transferências',
      actions: [
        IconButton(
          tooltip: 'Nova categoria',
          onPressed: () => _open(),
          icon: const Icon(CupertinoIcons.add),
        ),
      ],
      body: _loading
          ? const LoadingSkeleton()
          : _error != null
          ? ErrorView(
              message: 'Não foi possível carregar as categorias.',
              onRetry: _load,
            )
          : _categories.isEmpty
          ? EmptyView(
              message: 'Você ainda não possui categorias.',
              actionLabel: 'Criar categoria',
              onAction: _open,
            )
          : RefreshIndicator(
              onRefresh: () => _load(silent: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  96,
                ),
                children: [
                  _Section(
                    title: 'Receitas',
                    categories: income,
                    onOpen: (category) => _open(category: category),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Despesas',
                    categories: expense,
                    onOpen: (category) => _open(category: category),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Section(
                    title: 'Investimentos',
                    categories: investment,
                    onOpen: (category) => _open(category: category),
                  ),
                  if (transfers.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _Section(
                      title: 'Transferências',
                      categories: transfers,
                      onOpen: (category) => _open(category: category),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.categories,
    required this.onOpen,
  });

  final String title;
  final List<Category> categories;
  final ValueChanged<Category> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final category in categories) ...[
          Card(
            child: ListTile(
              leading: Icon(
                iconFromName(category.icon),
                color: colorFromHex(
                  category.color,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(category.name),
              subtitle: Text(
                [
                  if (category.isSystem) 'Padrão',
                  if (!category.isActive) 'Inativa',
                  category.type.label,
                ].join(' · '),
              ),
              onTap: () => onOpen(category),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
