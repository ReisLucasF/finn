import 'package:finan/app/app_scope.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:flutter/material.dart';

class TransferFormScreen extends StatefulWidget {
  const TransferFormScreen({super.key});

  @override
  State<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends State<TransferFormScreen> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  List<Account> _accounts = const [];
  String? _sourceId;
  String? _destinationId;
  late LocalDate _date;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _date = AppScope.of(context).graph.clock.today();
      _load();
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final scope = AppScope.of(context);
      final accounts = await scope.graph.accounts.listByUser(
        scope.session.user.id,
        includeInactive: false,
      );
      if (!mounted) return;
      final active = accounts.where((account) => !account.isDeleted).toList();
      setState(() {
        _accounts = active;
        _sourceId = active.isEmpty ? null : active.first.id;
        _destinationId = active.length > 1 ? active[1].id : active.firstOrNull?.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final amount = tryParseMoney(_amount.text);
    final sourceId = _sourceId;
    final destinationId = _destinationId;
    if (amount == null || sourceId == null || destinationId == null) {
      setState(() => _error = 'Informe valor, origem e destino.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scope = AppScope.of(context);
      await scope.graph.createTransfer(
        userId: scope.session.user.id,
        sourceAccountId: sourceId,
        destinationAccountId: destinationId,
        amount: amount,
        date: _date,
        description: _description.text,
      );
      if (!mounted) return;
      showSuccess(context, 'Transferência registrada');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transferência')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _sourceId,
                  decoration: const InputDecoration(labelText: 'Origem'),
                  items: [
                    for (final account in _accounts)
                      DropdownMenuItem(value: account.id, child: Text(account.name)),
                  ],
                  onChanged: (value) => setState(() => _sourceId = value),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _destinationId,
                  decoration: const InputDecoration(labelText: 'Destino'),
                  items: [
                    for (final account in _accounts)
                      DropdownMenuItem(value: account.id, child: Text(account.name)),
                  ],
                  onChanged: (value) => setState(() => _destinationId = value),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data'),
                  subtitle: Text(formatLocalDate(_date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(_date.year, _date.month, _date.day),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked == null) return;
                    setState(
                      () => _date = LocalDate(picked.year, picked.month, picked.day),
                    );
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Salvando…' : 'Transferir'),
                ),
              ],
            ),
    );
  }
}
