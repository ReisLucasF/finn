import 'dart:io';

import 'package:finan/app/app_scope.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/infrastructure/update/update_service.dart';
import 'package:finan/presentation/backup/backup_screen.dart';
import 'package:finan/presentation/budgets/budgets_screen.dart';
import 'package:finan/presentation/cards/cards_screen.dart';
import 'package:finan/presentation/categories/categories_screen.dart';
import 'package:finan/presentation/emergency/emergency_screen.dart';
import 'package:finan/presentation/goals/goals_screen.dart';
import 'package:finan/presentation/investments/investments_screen.dart';
import 'package:finan/presentation/provisions/provisions_screen.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/theme_mode_picker.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({this.includeSidebarDestinations = true, super.key});

  /// No celular estes destinos só existem aqui. Na barra lateral, não repetir.
  final bool includeSidebarDestinations;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String? _version;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _reset() async {
    final confirmed = await confirmAction(
      context,
      title: 'Recomeçar',
      message:
          'Todas as contas, lançamentos e configurações deste aparelho serão apagados. O cadastro inicial começa de novo. Essa ação não pode ser desfeita.',
      confirmLabel: 'Apagar tudo',
    );
    if (!confirmed || !mounted) return;
    try {
      final scope = AppScope.of(context);
      final user = await scope.graph.reset();
      if (!mounted) return;
      scope.session.setUser(user);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(error))),
      );
    }
  }

  Future<void> _loadVersion() async {
    final v = await UpdateService.instance.versaoAtual();
    if (!mounted) return;
    setState(() => _version = v);
  }

  Future<void> _verificarAtualizacao() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final info = await UpdateService.instance.verificarAtualizacao();
      if (!mounted) return;
      if (info == null) {
        showSuccess(context, 'Você já está na versão mais recente.');
        return;
      }
      await _mostrarAtualizacao(info);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _mostrarAtualizacao(UpdateInfo info) async {
    final notes = (info.notes ?? '').trim();
    final instalar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Atualização ${info.version}'),
          content: SingleChildScrollView(
            child: Text(
              notes.isEmpty
                  ? 'Há uma nova versão disponível. Deseja baixar e instalar?'
                  : notes,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Depois'),
            ),
            if (Platform.isWindows)
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Atualizar'),
              ),
          ],
        );
      },
    );
    if (instalar != true || !mounted) return;
    await _baixarEInstalar(info);
  }

  Future<void> _baixarEInstalar(UpdateInfo info) async {
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadProgressDialog(
        info: info,
        onError: (message) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Mais',
      subtitle: 'Organização e conexões',
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          FinanGroup(
            title: 'Planejamento',
            children: [
              _item(context, 'Categorias', const CategoriesScreen(refreshTick: 0)),
              if (widget.includeSidebarDestinations) ...[
                _item(context, 'Orçamentos', const BudgetsScreen()),
                _item(context, 'Metas', const GoalsScreen()),
                _item(
                  context,
                  'Reserva de emergência',
                  const EmergencyScreen(),
                ),
              ],
              _item(context, 'Recorrências', const ProvisionsScreen()),
            ],
          ),
          if (widget.includeSidebarDestinations) ...[
            const SizedBox(height: AppSpacing.lg),
            FinanGroup(
              title: 'Patrimônio',
              children: [
                _item(context, 'Cartões', const CardsScreen()),
                _item(context, 'Investimentos', const InvestmentsScreen()),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FinanGroup(
            title: 'Dados',
            children: [
              _item(context, 'Backup', const BackupScreen()),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const FinanGroup(
            title: 'Aparência',
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: ThemeModePicker(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FinanGroup(
            title: 'Neste aparelho',
            children: [
              ListTile(
                title: const Text('Recomeçar'),
                subtitle: const Text(
                  'Apaga todos os dados e volta ao início.',
                ),
                onTap: _reset,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FinanGroup(
            title: 'Sobre',
            children: [
              ListTile(
                title: const Text('Versão'),
                subtitle: Text(_version ?? '…'),
              ),
              if (Platform.isWindows)
                ListTile(
                  title: const Text('Verificar atualização'),
                  trailing: _checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          CupertinoIcons.arrow_down_circle,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35),
                        ),
                  onTap: _checking ? null : _verificarAtualizacao,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, String title, Widget screen) {
    return ListTile(
      title: Text(title),
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 18,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
      ),
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute<void>(builder: (_) => screen),
        );
      },
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({
    required this.info,
    required this.onError,
  });

  final UpdateInfo info;
  final void Function(String message) onError;

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      await UpdateService.instance.baixarEInstalar(
        widget.info,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      widget.onError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = (_progress * 100).clamp(0, 100).toStringAsFixed(0);
    return AlertDialog(
      title: const Text('Baixando atualização'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          const SizedBox(height: AppSpacing.md),
          Text(
            _progress > 0 ? '$pct%' : 'Iniciando…',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
