import 'package:file_picker/file_picker.dart';
import 'package:finan/app/app_scope.dart';
import 'package:finan/presentation/backup/pick_finance_backup.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:flutter/material.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await AppScope.of(context).graph.createBackup();
      if (!mounted) return;
      final saved = await FilePicker.saveFile(
        fileName: 'finan.financebackup',
        bytes: bytes,
        dialogTitle: 'Salvar backup',
      );
      if (!mounted) return;
      if (saved != null) showSuccess(context, 'Backup salvo');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final confirmed = await confirmAction(
      context,
      title: 'Restaurar backup',
      message:
          'Os dados locais serão substituídos pelo conteúdo do arquivo. Essa ação não pode ser desfeita.',
      confirmLabel: 'Restaurar',
    );
    if (!confirmed || !mounted) return;
    late final PickedBackup? picked;
    try {
      picked = await pickFinanceBackup(dialogTitle: 'Escolher backup');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyError(error));
      return;
    }
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = picked.bytes;
      if (!mounted) return;
      final scope = AppScope.of(context);
      await scope.graph.restoreBackup(bytes);
      final user = await scope.graph.open();
      if (!mounted) return;
      scope.session.setUser(user);
      showSuccess(context, 'Backup restaurado');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Backup',
      subtitle: 'Exportar e restaurar',
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const Text(
            'O arquivo .financebackup contém suas contas, lançamentos, cartões, investimentos e metas. A sincronização remota não está ligada.',
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : _export,
            child: const Text('Exportar backup'),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : _restore,
            child: const Text('Restaurar backup'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
