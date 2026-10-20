import 'package:finan/core/money/money.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';

enum DashboardInsightTone { positive, warning, neutral }

class DashboardInsight {
  const DashboardInsight({
    required this.title,
    required this.detail,
    required this.tone,
  });

  final String title;
  final String detail;
  final DashboardInsightTone tone;
}

/// Gera insights curtos a partir dos números já calculados da dashboard.
class DashboardInsightService {
  const DashboardInsightService();

  List<DashboardInsight> build({
    required DashboardSummary summary,
    required int activeGoals,
    required int goalsOnTrack,
  }) {
    final insights = <DashboardInsight>[];
    final emergency = summary.emergency;
    final months = summary.charts.months;

    if (summary.monthlySavings.cents < 0) {
      insights.add(
        DashboardInsight(
          title: 'Período no vermelho',
          detail:
              'Despesas superam receitas em ${_money(Money(-summary.monthlySavings.cents))}. '
              'Revise as maiores categorias do período.',
          tone: DashboardInsightTone.warning,
        ),
      );
    } else if (summary.savingsRate >= 0.2) {
      insights.add(
        DashboardInsight(
          title: 'Boa taxa de economia',
          detail:
              'Você guardou ${(summary.savingsRate * 100).round()}% da receita neste período.',
          tone: DashboardInsightTone.positive,
        ),
      );
    } else if (summary.monthlyIncome.cents > 0 && summary.savingsRate < 0.1) {
      insights.add(
        DashboardInsight(
          title: 'Economia apertada',
          detail:
              'Só ${(summary.savingsRate * 100).round()}% da receita sobrou. '
              'Um corte nas despesas discricionárias ajuda a meta de reserva.',
          tone: DashboardInsightTone.neutral,
        ),
      );
    }

    if (emergency.averageEssential.cents > 0) {
      if (!emergency.onTarget) {
        insights.add(
          DashboardInsight(
            title: 'Reserva abaixo da meta',
            detail:
                'Autonomia de ${emergency.runwayMonths.toStringAsFixed(1)} meses; '
                'meta ${emergency.targetMonths}. Faltam ${_money(emergency.gap)}.',
            tone: DashboardInsightTone.warning,
          ),
        );
      } else {
        insights.add(
          DashboardInsight(
            title: 'Reserva em dia',
            detail:
                'Você cobre cerca de ${emergency.runwayMonths.toStringAsFixed(1)} meses '
                'de despesas essenciais (meta ${emergency.targetMonths}).',
            tone: DashboardInsightTone.positive,
          ),
        );
      }
    }

    if (summary.investmentRate >= 0.1) {
      insights.add(
        DashboardInsight(
          title: 'Aportes consistentes',
          detail:
              '${(summary.investmentRate * 100).round()}% da receita foi aplicada '
              'em investimentos no período.',
          tone: DashboardInsightTone.positive,
        ),
      );
    } else if (summary.monthlyIncome.cents > 0 &&
        summary.investmentRate == 0 &&
        summary.totalInvestments.cents > 0) {
      insights.add(
        const DashboardInsight(
          title: 'Sem aportes no período',
          detail:
              'Há investimentos cadastrados, mas nenhum aporte confirmado neste recorte.',
          tone: DashboardInsightTone.neutral,
        ),
      );
    }

    if (months.length >= 2) {
      final previous = months[months.length - 2];
      final current = months.last;
      final delta = current.expense.cents - previous.expense.cents;
      if (previous.expense.cents > 0 &&
          delta.abs() / previous.expense.cents >= 0.15) {
        insights.add(
          DashboardInsight(
            title: delta > 0 ? 'Despesas em alta' : 'Despesas em queda',
            detail: delta > 0
                ? 'Gastou ${_money(Money(delta))} a mais que no mês anterior do gráfico.'
                : 'Gastou ${_money(Money(-delta))} a menos que no mês anterior do gráfico.',
            tone: delta > 0
                ? DashboardInsightTone.warning
                : DashboardInsightTone.positive,
          ),
        );
      }
    }

    final topExpense = [
      for (final slice in summary.charts.expenseByCategory)
        if (slice.amount.cents > 0) slice,
    ];
    if (topExpense.isNotEmpty && summary.monthlyExpenses.cents > 0) {
      final lead = topExpense.first;
      final share = lead.amount.cents / summary.monthlyExpenses.cents;
      if (share >= 0.4) {
        insights.add(
          DashboardInsight(
            title: 'Concentração em ${lead.label}',
            detail:
                '${(share * 100).round()}% das despesas do período estão nessa categoria.',
            tone: DashboardInsightTone.neutral,
          ),
        );
      }
    }

    if (activeGoals == 0) {
      insights.add(
        const DashboardInsight(
          title: 'Nenhuma meta ativa',
          detail:
              'Cadastre uma meta para acompanhar progresso e tempo estimado até o alvo.',
          tone: DashboardInsightTone.neutral,
        ),
      );
    } else if (goalsOnTrack > 0) {
      insights.add(
        DashboardInsight(
          title: 'Metas no ritmo',
          detail: goalsOnTrack == activeGoals
              ? 'Todas as $activeGoals metas ativas têm caminho com o aporte atual.'
              : '$goalsOnTrack de $activeGoals metas fecham com o aporte planejado.',
          tone: DashboardInsightTone.positive,
        ),
      );
    }

    return insights.take(5).toList(growable: false);
  }

  String _money(Money value) {
    final abs = value.cents.abs();
    final whole = abs ~/ 100;
    final frac = (abs % 100).toString().padLeft(2, '0');
    return 'R\$ $whole,$frac';
  }
}
