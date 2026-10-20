import 'package:finan/app/app_scope.dart';
import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/enums/goal_type.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/goals/goal_progress.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/finan_widgets.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  List<GoalProgress> _items = const [];
  Money _pace = Money.zero;
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
    setState(() => _loading = _items.isEmpty);
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final goals = await scope.graph.finance.listGoals(userId);
      // Mesmo resumo da dashboard: patrimônio e ritmo de economia.
      final summary = await scope.graph.getDashboardSummary(userId);
      if (!mounted) return;
      final items = [
        for (final goal in goals)
          if (goal.isActive)
            GoalProgress.evaluate(
              summary: summary,
              goal: goal,
              calculate: scope.graph.calculateGoalProjection,
            ),
      ]..sort((a, b) => b.progress.compareTo(a.progress));
      setState(() {
        _items = items;
        _pace = GoalProgress.savingsPace(summary);
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
    final draft = await showModalBottomSheet<_GoalDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _GoalEditor(),
    );
    if (draft == null || !mounted) return;
    try {
      final scope = AppScope.of(context);
      await scope.graph.createFinancialGoal(
        userId: scope.session.user.id,
        name: draft.name,
        goalType: draft.type,
        targetAmount: draft.target,
        currentAmount: draft.current,
        expectedMonthlySavings: draft.monthly,
        monthlyRate: 0,
        targetDate: draft.targetDate,
      );
      if (!mounted) return;
      showSuccess(context, 'Meta criada');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Metas',
      subtitle: 'Objetivos e projeção',
      trailing: IconButton.filledTonal(
        tooltip: 'Nova meta',
        onPressed: _create,
        icon: const Icon(CupertinoIcons.add),
      ),
      body: _loading
          ? const LoadingSkeleton()
          : _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : _items.isEmpty
          ? EmptyView(
              icon: CupertinoIcons.flag,
              message: 'Nenhuma meta cadastrada.',
              detail:
                  'Defina um alvo, como patrimônio, uma compra ou uma '
                  'viagem, e veja em quanto tempo chega lá.',
              actionLabel: 'Nova meta',
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
    final reached = _items.where((item) => item.progress >= 1).length;
    final onTrack = _items.where((item) => item.onTrack).length;
    final average =
        _items.fold<double>(0, (sum, item) => sum + item.progress) /
        _items.length;
    var order = 0;
    Widget step(Widget child) => FadeSlideIn(index: order++, child: child);
    return ListView(
      padding: screenPadding(context),
      children: [
        step(
          FinanHero(
            icon: CupertinoIcons.flag_fill,
            label: 'Seu ritmo de economia',
            value: _pace,
            caption: 'Média mensal recente, base das projeções',
            side: ProgressRing(
              value: average,
              color: AppColors.accentDark,
              size: 92,
              stroke: 9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(average * 100).round()}%',
                    style: AppTypography.headline(Colors.white),
                  ),
                  Text(
                    'média',
                    style: AppTypography.label(
                      Colors.white.withValues(alpha: 0.7),
                    ).copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            stats: [
              HeroStat(
                icon: CupertinoIcons.flag,
                label: 'Ativas',
                text: '${_items.length}',
              ),
              HeroStat(
                icon: CupertinoIcons.speedometer,
                label: 'No ritmo',
                text: '$onTrack',
              ),
              HeroStat(
                icon: CupertinoIcons.checkmark_seal,
                label: 'Alcançadas',
                text: '$reached',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        step(
          SectionHeader(
            title: 'Suas metas',
            subtitle: 'Da mais próxima para a mais distante',
            action: 'Nova meta',
            onAction: _create,
          ),
        ),
        step(
          TileGrid(
            columns: gridColumns(width, max: 2),
            children: [for (final item in _items) _GoalCard(progress: item)],
          ),
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final goal = progress.goal;
    final reached = progress.progress >= 1;
    final color = reached || progress.onTrack
        ? AppColors.incomeOf(brightness)
        : AppColors.warningOf(brightness);
    final months = progress.projection.monthsToTarget;
    final estimate = switch (months) {
      0 => 'Meta alcançada',
      null when progress.monthlyPace.cents <= 0 =>
        'Sem economia recente para projetar',
      null => 'Nesse ritmo, não fecha em 100 anos',
      1 => 'Nesse ritmo: 1 mês',
      _ => 'Nesse ritmo: ${_duration(months)}',
    };
    final planned = progress.plannedProjection;
    final plannedMonths = planned?.monthsToTarget;
    final plannedLine = planned == null || goal.expectedMonthlySavings.isZero
        ? null
        : 'Aportando ${formatMoney(goal.expectedMonthlySavings)}/mês: '
              '${switch (plannedMonths) {
                0 => 'já alcançada',
                null => 'não fecha',
                _ => _duration(plannedMonths),
              }}';
    final deadline = goal.targetDate;
    final deadlineMonths = deadline == null ? null : _monthsUntil(deadline);
    final late =
        deadlineMonths != null &&
        !reached &&
        (months == null || months > deadlineMonths);
    return Semantics(
      label:
          '${goal.name}. ${(progress.progress * 100).round()}%. '
          '${formatMoney(progress.present)} de ${formatMoney(goal.targetAmount)}. '
          '$estimate.',
      child: FinanCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        radius: AppSpacing.radius,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProgressRing(
                    value: progress.progress,
                    color: color,
                    size: 64,
                    stroke: 7,
                    child: Text(
                      '${(progress.progress * 100).round()}%',
                      style: AppTypography.label(scheme.onSurface)
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headline(scheme.onSurface)
                              .copyWith(fontSize: 17),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: AppSpacing.xxs,
                          runSpacing: AppSpacing.xxs,
                          children: [
                            DeltaChip(
                              label: goal.goalType.label,
                              color: scheme.primary,
                            ),
                            if (reached)
                              DeltaChip(
                                label: 'Alcançada',
                                color: color,
                                icon: CupertinoIcons.checkmark,
                              )
                            else if (deadline != null)
                              DeltaChip(
                                label: 'Até ${formatLocalDate(deadline)}',
                                color: late
                                    ? AppColors.expenseOf(brightness)
                                    : scheme.onSurface.withValues(alpha: 0.6),
                                icon: CupertinoIcons.calendar,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedMoney(
                        value: progress.present,
                        style: AppTypography.headline(scheme.onSurface),
                      ),
                    ),
                  ),
                  Text(
                    'de ${formatMoney(goal.targetAmount)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              AnimatedProgressBar(value: progress.progress, color: color),
              const SizedBox(height: AppSpacing.sm),
              _Line(
                icon: CupertinoIcons.speedometer,
                text: estimate,
                color: reached ? color : null,
              ),
              if (!reached && progress.remaining.cents > 0)
                _Line(
                  icon: CupertinoIcons.arrow_right_circle,
                  text: 'Faltam ${formatMoney(progress.remaining)}',
                ),
              if (plannedLine != null)
                _Line(
                  icon: CupertinoIcons.calendar_badge_plus,
                  text: plannedLine,
                ),
              if (late)
                _Line(
                  icon: CupertinoIcons.exclamationmark_triangle,
                  text: 'No ritmo atual, passa do prazo',
                  color: AppColors.expenseOf(brightness),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _duration(int months) {
    if (months < 12) return '$months ${months == 1 ? 'mês' : 'meses'}';
    final years = months ~/ 12;
    final rest = months % 12;
    final y = '$years ${years == 1 ? 'ano' : 'anos'}';
    return rest == 0 ? y : '$y e $rest ${rest == 1 ? 'mês' : 'meses'}';
  }

  static int _monthsUntil(LocalDate date) {
    final today = LocalDate.fromDateTime(DateTime.now());
    final months = (date.year - today.year) * 12 + date.month - today.month;
    return months < 0 ? 0 : months;
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone =
        color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: tone),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.label(tone)
                  .copyWith(fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── Editor ─────────────────────────────

class _GoalDraft {
  const _GoalDraft({
    required this.name,
    required this.type,
    required this.target,
    required this.current,
    required this.monthly,
    this.targetDate,
  });

  final String name;
  final GoalType type;
  final Money target;
  final Money current;
  final Money monthly;
  final LocalDate? targetDate;
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor();

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _current = TextEditingController();
  final _monthly = TextEditingController();
  GoalType _type = GoalType.netWorth;
  LocalDate? _date;
  String? _error;

  /// Tipos cujo valor atual vem do app (patrimônio/investimentos).
  bool get _automatic =>
      _type == GoalType.netWorth || _type == GoalType.investment;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _current.dispose();
    _monthly.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 50),
      initialDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Prazo da meta',
      cancelText: 'Cancelar',
      confirmText: 'Definir',
    );
    if (picked != null) setState(() => _date = LocalDate.fromDateTime(picked));
  }

  void _submit() {
    final target = tryParseMoney(_target.text);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Dê um nome para a meta.');
      return;
    }
    if (target == null || target.cents <= 0) {
      setState(() => _error = 'Informe um valor alvo maior que zero.');
      return;
    }
    Navigator.pop(
      context,
      _GoalDraft(
        name: _name.text.trim(),
        type: _type,
        target: target,
        current: _automatic
            ? Money.zero
            : tryParseMoney(_current.text) ?? Money.zero,
        monthly: tryParseMoney(_monthly.text) ?? Money.zero,
        targetDate: _date,
      ),
    );
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nova meta', style: AppTypography.headline(scheme.onSurface)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex.: Primeiros 100 mil, Viagem, Carro',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Acompanhar',
              style: AppTypography.label(
                scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final type in GoalType.values)
                  FinanPill(
                    label: type.label,
                    selected: _type == type,
                    onTap: () => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _automatic
                  ? 'O valor atual vem do app: '
                        '${_type == GoalType.netWorth ? 'seu patrimônio líquido' : 'o total investido'}.'
                  : 'Você informa quanto já tem guardado para ela.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor alvo',
                prefixText: 'R\$ ',
              ),
            ),
            if (!_automatic) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _current,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Já guardado',
                  prefixText: 'R\$ ',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _monthly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Aporte mensal planejado (opcional)',
                prefixText: 'R\$ ',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(CupertinoIcons.calendar, size: 18),
              label: Text(
                _date == null
                    ? 'Definir prazo (opcional)'
                    : 'Prazo: ${formatLocalDate(_date!)}',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _submit, child: const Text('Criar meta')),
          ],
        ),
      ),
    );
  }
}
