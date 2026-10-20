import 'package:finan/application/planning/planning_actions.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/enums/goal_type.dart';
import 'package:finan/domain/services/goal_projection_service.dart';

/// Progresso e projeção de uma meta, igual na dashboard e na tela de metas.
class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.present,
    required this.monthlyPace,
    required this.projection,
    required this.plannedProjection,
    required this.progress,
    required this.onTrack,
  });

  final FinancialGoal goal;

  /// Valor atual: patrimônio/investimentos para metas desses tipos,
  /// senão o valor informado na meta.
  final Money present;

  /// Economia média recente (últimos 3 meses do gráfico).
  final Money monthlyPace;

  /// Projeção no ritmo real de economia, sem rendimento.
  final GoalProjection projection;

  /// Projeção com o aporte planejado da meta; nula se igual ao ritmo.
  final GoalProjection? plannedProjection;
  final double progress;
  final bool onTrack;

  Money get remaining {
    final missing = goal.targetAmount.cents - present.cents;
    return Money(missing < 0 ? 0 : missing);
  }

  static GoalProgress evaluate({
    required DashboardSummary summary,
    required FinancialGoal goal,
    required CalculateGoalProjection calculate,
  }) {
    final present = presentOf(summary, goal);
    final pace = savingsPace(summary);
    // Ritmo real (economia recente). Retorno configurado não entra aqui:
    // a pergunta é “se continuar economizando assim”.
    final paceProjection = calculate(
      present: present,
      monthlyContribution: pace,
      monthlyRate: 0,
      months: 12,
      target: goal.targetAmount,
    );
    final planned = goal.expectedMonthlySavings;
    final plannedProjection = planned.cents == pace.cents
        ? null
        : calculate(
            present: present,
            monthlyContribution: planned,
            monthlyRate: goal.expectedMonthlyReturnRate,
            months: 12,
            target: goal.targetAmount,
          );
    final progress = goal.targetAmount.cents <= 0
        ? 0.0
        : (present.cents / goal.targetAmount.cents).clamp(0.0, 1.0);
    return GoalProgress(
      goal: goal,
      present: present,
      monthlyPace: pace,
      projection: paceProjection,
      plannedProjection: plannedProjection,
      progress: progress,
      onTrack: pace.cents > 0 && paceProjection.monthsToTarget != null,
    );
  }

  static Money presentOf(DashboardSummary summary, FinancialGoal goal) {
    return switch (goal.goalType) {
      GoalType.netWorth => summary.netWorth,
      GoalType.investment => summary.totalInvestments,
      GoalType.savings ||
      GoalType.purchase ||
      GoalType.custom => goal.currentAmount,
    };
  }

  /// Média da economia dos últimos meses do gráfico (mais estável que o mês atual).
  static Money savingsPace(DashboardSummary summary) {
    final months = summary.charts.months;
    if (months.isNotEmpty) {
      final window = months.length <= 3
          ? months
          : months.sublist(months.length - 3);
      var total = 0;
      for (final month in window) {
        total += month.savings.cents;
      }
      final average = Money(total ~/ window.length);
      if (average.cents > 0) return average;
    }
    if (summary.monthlySavings.cents > 0) return summary.monthlySavings;
    return Money.zero;
  }
}

extension GoalTypeLabel on GoalType {
  String get label => switch (this) {
    GoalType.netWorth => 'Patrimônio',
    GoalType.savings => 'Poupança',
    GoalType.investment => 'Investimentos',
    GoalType.purchase => 'Compra',
    GoalType.custom => 'Personalizada',
  };
}
