import 'package:finan/app/app_scope.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/enums/account_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:flutter/material.dart';

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({this.account, super.key});

  final Account? account;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.account?.name ?? '',
  );
  late final TextEditingController _institution = TextEditingController(
    text: widget.account?.institutionName ?? '',
  );
  late final TextEditingController _balance = TextEditingController(
    text: widget.account == null
        ? ''
        : formatMoney(widget.account!.initialBalance),
  );
  late AccountType _type = widget.account?.type ?? AccountType.checking;
  late bool _active = widget.account?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _institution.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final scope = AppScope.of(context);
    final parsed = _balance.text.trim().isEmpty
        ? const Money(0)
        : tryParseMoney(_balance.text, allowNegative: true);
    if (parsed == null) {
      setState(() => _error = 'Informe um saldo inicial válido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = widget.account;
      if (account == null) {
        await scope.graph.createAccount(
          userId: scope.session.user.id,
          name: _name.text,
          type: _type,
          initialBalance: parsed,
          currency: scope.session.user.currency,
          institutionName: _institution.text,
        );
      } else {
        await scope.graph.updateAccount(
          id: account.id,
          name: _name.text,
          type: _type,
          initialBalance: parsed,
          isActive: _active,
          institutionName: _institution.text,
          institutionCode: account.institutionCode,
        );
      }
      if (!mounted) return;
      showSuccess(
        context,
        account == null ? 'Conta criada' : 'Conta atualizada',
      );
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
    final editing = widget.account != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Editar conta' : 'Nova conta')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _institution,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Instituição',
              hintText: 'Opcional',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: 'Saldo inicial'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Tipo', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final type in AccountType.values)
                ChoiceChip(
                  label: Text(type.label),
                  selected: _type == type,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _type = type),
                ),
            ],
          ),
          if (editing) ...[
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Conta ativa'),
              value: _active,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _active = value),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvando...' : 'Salvar'),
          ),
        ],
      ),
    );
  }
}
