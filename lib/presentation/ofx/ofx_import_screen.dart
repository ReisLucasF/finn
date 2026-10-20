import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finan/app/app_scope.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/domain/entities/account.dart';
import 'package:finan/domain/entities/category.dart';
import 'package:finan/domain/entities/ofx_review.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class OfxImportScreen extends StatefulWidget {
  const OfxImportScreen({super.key});

  @override
  State<OfxImportScreen> createState() => _OfxImportScreenState();
}

class _OfxImportScreenState extends State<OfxImportScreen> {
  List<Account> _accounts = const [];
  List<Category> _categories = const [];
  String? _accountId;
  Uint8List? _bytes;
  String? _fileName;
  OfxAnalysis? _analysis;
  final Map<String, bool> _import = {};
  final Map<String, String?> _categoryByLine = {};
  final Map<String, bool> _asTransfer = {};
  final Map<String, String?> _otherAccount = {};
  Object? _error;
  bool _loading = true;
  bool _analyzing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAccounts();
    });
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
      if (!mounted) return;
      setState(() {
        _accounts = accounts.where((account) => !account.isDeleted).toList();
        _categories = categories;
        _accountId ??= _accounts.isEmpty ? null : _accounts.first.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ofx'],
      dialogTitle: 'Importar OFX',
    );
    if (files.isEmpty || !mounted) return;
    final bytes = await files.first.readAsBytes();
    setState(() {
      _bytes = bytes;
      _fileName = files.first.name;
      _analysis = null;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    final bytes = _bytes;
    final accountId = _accountId;
    if (bytes == null || accountId == null) return;
    setState(() {
      _analyzing = true;
      _error = null;
    });
    try {
      final scope = AppScope.of(context);
      final analysis = await scope.graph.analyzeOfx(
        userId: scope.session.user.id,
        accountId: accountId,
        bytes: bytes,
        fileName: _fileName,
      );
      if (!mounted) return;
      setState(() {
        _analysis = analysis;
        _import
          ..clear()
          ..addEntries([
            for (final line in analysis.lines)
              MapEntry(line.id, line.importByDefault),
          ]);
        _categoryByLine
          ..clear()
          ..addEntries([
            for (final line in analysis.lines)
              MapEntry(line.id, _suggestedCategory(line)),
          ]);
        _asTransfer
          ..clear()
          ..addEntries([
            for (final line in analysis.lines) MapEntry(line.id, false),
          ]);
        _otherAccount
          ..clear()
          ..addEntries([
            for (final line in analysis.lines)
              MapEntry(line.id, line.possibleTransfer?.accountId),
          ]);
        _analyzing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _analyzing = false;
        _analysis = null;
      });
    }
  }

  String? _suggestedCategory(OfxReviewLine line) {
    final categoryId = line.suggestion?.categoryId;
    if (categoryId == null) return null;
    for (final category in _categories) {
      if (category.id == categoryId && category.type.accepts(line.type)) {
        return category.id;
      }
    }
    return null;
  }

  Future<void> _confirm() async {
    final analysis = _analysis;
    if (analysis == null || _saving) return;
    setState(() => _saving = true);
    try {
      final scope = AppScope.of(context);
      final result = await scope.graph.importOfx(
        userId: scope.session.user.id,
        analysis: analysis,
        decisions: [
          for (final line in analysis.lines)
            OfxImportDecision(
              lineId: line.id,
              import: _import[line.id] ?? false,
              categoryId: (_asTransfer[line.id] ?? false)
                  ? null
                  : _categoryByLine[line.id],
              transferAccountId: (_asTransfer[line.id] ?? false)
                  ? _otherAccount[line.id]
                  : null,
              linkTransactionId:
                  (_asTransfer[line.id] ?? false) &&
                      _otherAccount[line.id] == line.possibleTransfer?.accountId
                  ? line.possibleTransfer?.transactionId
                  : null,
            ),
        ],
      );
      if (!mounted) return;
      showSuccess(
        context,
        'Importados ${result.imported}. Ignorados ${result.ignored}.',
      );
      Navigator.of(context).pop(result.imported > 0);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Importar OFX',
      subtitle: 'Extrato do banco',
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CupertinoActivityIndicator());
    if (_error != null && _analysis == null && _bytes == null) {
      return ErrorView(message: friendlyError(_error!), onRetry: _loadAccounts);
    }
    if (_accounts.isEmpty) {
      return const EmptyView(
        message: 'Crie uma conta ativa antes de importar um OFX.',
      );
    }
    final analysis = _analysis;
    return Column(
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
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: 'Conta'),
                items: [
                  for (final account in _accounts)
                    DropdownMenuItem(value: account.id, child: Text(account.name)),
                ],
                onChanged: _analyzing || _saving
                    ? null
                    : (value) {
                        setState(() {
                          _accountId = value;
                          _analysis = null;
                        });
                        if (_bytes != null) _analyze();
                      },
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _analyzing || _saving ? null : _pickFile,
                icon: const Icon(CupertinoIcons.arrow_up_doc),
                label: Text(_fileName ?? 'Escolher arquivo OFX'),
              ),
              if (_error != null && analysis == null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  friendlyError(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        if (_analyzing)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (analysis == null)
          const Expanded(
            child: EmptyView(
              message: 'Escolha a conta e o arquivo para revisar os lançamentos.',
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              itemCount: analysis.lines.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _lineCard(analysis.lines[index]),
            ),
          ),
        if (analysis != null)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: FilledButton(
                onPressed: _saving ? null : _confirm,
                child: Text(_saving ? 'Importando…' : 'Confirmar importação'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _lineCard(OfxReviewLine line) {
    final categories = [
      for (final category in _categories)
        if (category.type.accepts(line.type)) category,
    ];
    final selected = _import[line.id] ?? false;
    final signed = line.type == TransactionType.expense
        ? '-${formatMoney(line.absoluteAmount)}'
        : formatMoney(line.absoluteAmount);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: _saving || line.coveredByExistingTransfer
                      ? null
                      : (value) =>
                            setState(() => _import[line.id] = value ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.originalDescription),
                      Text(
                        '${formatLocalDate(line.postedDate)} · $signed',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (line.duplicateBand != DuplicateBand.none &&
                !line.coveredByExistingTransfer)
              Text(
                _duplicateLabel(line),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (line.coveredByExistingTransfer)
              Text(
                'Já registrada como transferência na outra conta. Desmarcada para não duplicar.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (line.possibleTransfer != null &&
                !(_asTransfer[line.id] ?? false))
              Text(
                'Possível transferência para outra conta. Marque abaixo se for o caso.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (selected && !line.coveredByExistingTransfer) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Transferência para outra conta'),
                value: _asTransfer[line.id] ?? false,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _asTransfer[line.id] = value),
              ),
              if (_asTransfer[line.id] ?? false)
                DropdownButtonFormField<String>(
                  initialValue: _otherAccounts().any(
                    (account) => account.id == _otherAccount[line.id],
                  )
                      ? _otherAccount[line.id]
                      : null,
                  decoration: const InputDecoration(labelText: 'Outra conta'),
                  items: [
                    for (final account in _otherAccounts())
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _otherAccount[line.id] = value),
                )
              else if (categories.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: categories.any(
                    (category) => category.id == _categoryByLine[line.id],
                  )
                      ? _categoryByLine[line.id]
                      : '',
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sem categoria'),
                    ),
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _categoryByLine[line.id] = value == ''
                              ? null
                              : value,
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Account> _otherAccounts() {
    final current = _analysis?.accountId;
    return [
      for (final account in _accounts)
        if (account.id != current) account,
    ];
  }

  String _duplicateLabel(OfxReviewLine line) {
    final percent = (line.duplicateScore * 100).round();
    final band = switch (line.duplicateBand) {
      DuplicateBand.possible => 'Possível duplicata',
      DuplicateBand.probable => 'Provável duplicata',
      DuplicateBand.veryLikely => 'Duplicata muito provável',
      DuplicateBand.none => '',
    };
    return '$band ($percent%). Fica desmarcada para não importar sozinha.';
  }
}
