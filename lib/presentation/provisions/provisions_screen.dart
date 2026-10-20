import 'package:finan/app/app_scope.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/enums/recurrence_frequency.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ProvisionsScreen extends StatefulWidget {
  const ProvisionsScreen({super.key});

  @override
  State<ProvisionsScreen> createState() => _ProvisionsScreenState();
}

class _ProvisionsScreenState extends State<ProvisionsScreen> {
  List<Recurrence> _recurrences = const [];
  List<Provision> _provisions = const [];
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
    setState(() => _loading = true);
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final recurrences = await scope.graph.finance.listRecurrences(userId);
      final provisions = await scope.graph.finance.listProvisions(userId);
      if (!mounted) return;
      setState(() {
        _recurrences = recurrences;
        _provisions = provisions;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final scope = AppScope.of(context);
    final userId = scope.session.user.id;
    final accounts = await scope.graph.accounts.listByUser(
      userId,
      includeInactive: false,
    );
    final categories = await scope.graph.listCategories(
      userId,
      includeInactive: false,
    );
    if (!mounted || accounts.isEmpty || categories.isEmpty) return;
    final name = TextEditingController();
    final amount = TextEditingController();
    var accountId = accounts.first.id;
    var categoryId = categories.first.id;
    var type = TransactionType.expense;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nova recorrência'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            DropdownButtonFormField<TransactionType>(
              initialValue: type,
              items: const [
                DropdownMenuItem(
                  value: TransactionType.expense,
                  child: Text('Despesa'),
                ),
                DropdownMenuItem(
                  value: TransactionType.income,
                  child: Text('Receita'),
                ),
              ],
              onChanged: (value) {
                if (value != null) type = value;
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: accountId,
              items: [
                for (final account in accounts)
                  DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: (value) {
                if (value != null) accountId = value;
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              items: [
                for (final category in categories)
                  DropdownMenuItem(value: category.id, child: Text(category.name)),
              ],
              onChanged: (value) {
                if (value != null) categoryId = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    final parsed = tryParseMoney(amount.text);
    if (saved != true || parsed == null || !mounted) return;
    try {
      final today = AppScope.of(context).graph.clock.today();
      await AppScope.of(context).graph.createRecurrence(
        userId: userId,
        name: name.text,
        type: type,
        amount: parsed,
        accountId: accountId,
        categoryId: categoryId,
        frequency: RecurrenceFrequency.monthly,
        startDate: today,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _generate(Recurrence recurrence) async {
    final today = AppScope.of(context).graph.clock.today();
    final until = LocalDate(today.year, today.month, 1).addMonths(1).addDays(-1);
    try {
      final count = await AppScope.of(context).graph.generateProvisions(
        userId: AppScope.of(context).session.user.id,
        recurrenceId: recurrence.id,
        until: until,
      );
      if (!mounted) return;
      showSuccess(context, count == 0 ? 'Nada novo para gerar' : 'Gerados $count');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _settle(Provision provision) async {
    try {
      await AppScope.of(context).graph.settleProvision(
        userId: AppScope.of(context).session.user.id,
        provisionId: provision.id,
      );
      if (!mounted) return;
      showSuccess(context, 'Provisionamento lançado no saldo');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Recorrências',
      subtitle: 'Provisões e ciclos',
      actions: [
        IconButton(
          onPressed: _create,
          icon: const Icon(CupertinoIcons.add),
        ),
      ],
      body: _loading
          ? const Center(child: CupertinoActivityIndicator())
          : _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text('Recorrências', style: Theme.of(context).textTheme.titleMedium),
                if (_recurrences.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Text('Nenhuma recorrência.'),
                  ),
                for (final recurrence in _recurrences)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recurrence.name),
                    subtitle: Text(
                      '${recurrence.frequency.label} · ${formatMoney(recurrence.amount)}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _generate(recurrence),
                      child: const Text('Gerar'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Provisionamentos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Ainda não alteram o saldo. Liquidar cria o lançamento real.',
                ),
                for (final provision in _provisions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(provision.description),
                    subtitle: Text(
                      '${formatLocalDate(provision.dueDate)} · ${provision.status.value}',
                    ),
                    trailing: provision.status.isOpen
                        ? TextButton(
                            onPressed: () => _settle(provision),
                            child: const Text('Liquidar'),
                          )
                        : Text(formatMoney(provision.amount)),
                  ),
              ],
            ),
    );
  }
}
