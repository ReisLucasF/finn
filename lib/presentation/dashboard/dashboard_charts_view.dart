import 'dart:math' as math;

import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/dashboard_summary.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:flutter/material.dart';

const _sliceColors = <Color>[
  Color(0xFF1F6B4A),
  Color(0xFF3E4C7A),
  Color(0xFF7A342C),
  Color(0xFF8A6A2F),
  Color(0xFF2E7D6F),
  Color(0xFF5C5346),
];

class DashboardChartsView extends StatelessWidget {
  const DashboardChartsView({required this.charts, super.key});

  final DashboardCharts charts;

  @override
  Widget build(BuildContext context) {
    final income = _tone(context, income: true);
    final expense = _tone(context, income: false);
    final months = charts.months;
    final worth = charts.netWorth;
    final investments = charts.investments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Análise',
          subtitle: 'Evolução, fluxo e composição dos últimos meses',
        ),
        _ChartCard(
          title: 'Patrimônio',
          footnote: worth.length >= 2
              ? _deltaFootnote(
                  from: worth[worth.length - 2].amount,
                  to: worth.last.amount,
                  label: 'vs mês anterior',
                )
              : null,
          semanticsLabel:
              'Patrimônio nos últimos meses, de ${formatMoney(worth.first.amount)} a ${formatMoney(worth.last.amount)}.',
          child: _LineChart(
            points: [for (final point in worth) point.amount.cents],
            labels: [for (final point in worth) _monthLabel(point.date)],
            color: income,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ChartCard(
          title: 'Fluxo de caixa',
          footnote: months.isEmpty
              ? null
              : 'Média receitas ${_avgMoney([for (final m in months) m.income])} · '
                    'despesas ${_avgMoney([for (final m in months) m.expense])}',
          semanticsLabel:
              'Receitas ${formatMoney(months.last.income)} e despesas ${formatMoney(months.last.expense)} no mês atual.',
          legend: [
            _LegendDot(color: income, label: 'Receitas'),
            _LegendDot(color: expense, label: 'Despesas'),
          ],
          child: _GroupedBars(
            income: [for (final month in months) month.income.cents],
            expense: [for (final month in months) month.expense.cents],
            labels: [for (final month in months) _monthLabel(month.start)],
            incomeColor: income,
            expenseColor: expense,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ChartCard(
          title: 'Tendência de economia',
          footnote: months.length >= 2
              ? _deltaFootnote(
                  from: months[months.length - 2].savings,
                  to: months.last.savings,
                  label: 'vs mês anterior',
                )
              : null,
          semanticsLabel:
              'Economia do mês atual ${formatMoney(months.last.savings)}.',
          child: _SingleBars(
            values: [for (final month in months) month.savings.cents],
            labels: [for (final month in months) _monthLabel(month.start)],
            positive: income,
            negative: expense,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final expenseCard = _DonutCard(
              title: 'Despesas por categoria',
              slices: charts.expenseByCategory,
              empty: 'Nenhuma despesa neste período.',
            );
            final incomeCard = _DonutCard(
              title: 'Receitas por categoria',
              slices: charts.incomeByCategory,
              empty: 'Nenhuma receita neste período.',
            );
            if (constraints.maxWidth < 720) {
              return Column(
                children: [
                  expenseCard,
                  const SizedBox(height: AppSpacing.md),
                  incomeCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: expenseCard),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: incomeCard),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _ChartCard(
          title: 'Investimentos',
          semanticsLabel:
              'Capital investido ${formatMoney(investments.last.invested)}. Valor atual ${formatMoney(investments.last.current)}.',
          legend: [
            _LegendDot(color: expense, label: 'Capital investido'),
            _LegendDot(color: income, label: 'Valor atual'),
          ],
          child: _DualLine(
            first: [for (final point in investments) point.invested.cents],
            second: [for (final point in investments) point.current.cents],
            labels: [for (final point in investments) _monthLabel(point.date)],
            firstColor: expense,
            secondColor: income,
          ),
        ),
      ],
    );
  }
}

class _DonutCard extends StatelessWidget {
  const _DonutCard({
    required this.title,
    required this.slices,
    required this.empty,
  });

  final String title;
  final List<CategorySlice> slices;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final visible = _topSlices(slices);
    final total = visible.fold<int>(
      0,
      (sum, slice) => sum + slice.amount.cents,
    );
    final spoken = visible.isEmpty
        ? empty
        : visible
              .map((slice) => '${slice.label} ${formatMoney(slice.amount)}')
              .join(', ');
    return _ChartCard(
      title: title,
      semanticsLabel: spoken,
      child: total == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(empty),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HoverDonut(
                  slices: visible,
                  colors: [
                    for (var index = 0; index < visible.length; index++)
                      _sliceColors[index % _sliceColors.length],
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var index = 0; index < visible.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              _Swatch(
                                color:
                                    _sliceColors[index % _sliceColors.length],
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  visible[index].label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                '${formatMoney(visible[index].amount)}'
                                ' · ${_share(visible[index].amount.cents, total)}',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.semanticsLabel,
    required this.child,
    this.legend = const [],
    this.footnote,
  });

  final String title;
  final String semanticsLabel;
  final Widget child;
  final List<Widget> legend;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$title. $semanticsLabel',
      child: DecoratedBox(
        decoration: FinanCard.decoration(context),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.headline(scheme.onSurface)
                    .copyWith(fontSize: 16),
              ),
              if (legend.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: legend,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              child,
              if (footnote != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(footnote!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _deltaFootnote({
  required Money from,
  required Money to,
  required String label,
}) {
  final delta = to.cents - from.cents;
  if (delta == 0) return 'Estável $label';
  final sign = delta > 0 ? '+' : '−';
  return '$sign${formatMoney(Money(delta.abs()))} $label';
}

String _avgMoney(List<Money> values) {
  if (values.isEmpty) return formatMoney(Money.zero);
  var total = 0;
  for (final value in values) {
    total += value.cents;
  }
  return formatMoney(Money(total ~/ values.length));
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Swatch(color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(label),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.points,
    required this.labels,
    required this.color,
  });

  final List<int> points;
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPlot(
      labels: labels,
      series: [_PlotSeries('Patrimônio', color, points)],
    );
  }
}

class _DualLine extends StatelessWidget {
  const _DualLine({
    required this.first,
    required this.second,
    required this.labels,
    required this.firstColor,
    required this.secondColor,
  });

  final List<int> first;
  final List<int> second;
  final List<String> labels;
  final Color firstColor;
  final Color secondColor;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPlot(
      labels: labels,
      series: [
        _PlotSeries('Capital investido', firstColor, first),
        _PlotSeries('Valor atual', secondColor, second),
      ],
    );
  }
}

class _GroupedBars extends StatelessWidget {
  const _GroupedBars({
    required this.income,
    required this.expense,
    required this.labels,
    required this.incomeColor,
    required this.expenseColor,
  });

  final List<int> income;
  final List<int> expense;
  final List<String> labels;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPlot(
      labels: labels,
      bars: true,
      series: [
        _PlotSeries('Receitas', incomeColor, income),
        _PlotSeries('Despesas', expenseColor, expense),
      ],
    );
  }
}

class _SingleBars extends StatelessWidget {
  const _SingleBars({
    required this.values,
    required this.labels,
    required this.positive,
    required this.negative,
  });

  final List<int> values;
  final List<String> labels;
  final Color positive;
  final Color negative;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPlot(
      labels: labels,
      bars: true,
      series: [_PlotSeries('Economia', positive, values, negative: negative)],
    );
  }
}

/// Dispara a animação quando uma parte real do gráfico entra na viewport.
mixin _RevealMotion<T extends StatefulWidget> on State<T> {
  ScrollPosition? _scroll;
  VoidCallback? _onScroll;
  bool _revealed = false;
  bool _armed = false;

  void reveal(AnimationController motion) {
    if (_revealed) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.value = 1;
      _revealed = true;
      return;
    }
    if (_armed) return;
    _armed = true;
    _onScroll = () => _revealIfSeen(motion);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _revealed) return;
      _scroll = Scrollable.maybeOf(context)?.position;
      _scroll?.addListener(_onScroll!);
      _revealIfSeen(motion);
    });
  }

  void _revealIfSeen(AnimationController motion) {
    if (_revealed || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      _start(motion);
      return;
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: viewport);
    final overlap = (origin & box.size).intersect(Offset.zero & viewport.size);
    if (overlap.width > 0 && overlap.height >= box.size.height * 1) {
      _start(motion);
    }
  }

  void _start(AnimationController motion) {
    _revealed = true;
    final listener = _onScroll;
    if (listener != null) _scroll?.removeListener(listener);
    _scroll = null;
    motion.forward();
  }

  void disposeReveal() {
    final listener = _onScroll;
    if (listener != null) _scroll?.removeListener(listener);
    _scroll = null;
  }
}

class _PlotSeries {
  const _PlotSeries(this.name, this.color, this.values, {this.negative});

  final String name;
  final Color color;
  final Color? negative;
  final List<int> values;
}

class _AnimatedPlot extends StatefulWidget {
  const _AnimatedPlot({
    required this.labels,
    required this.series,
    this.bars = false,
  });

  final List<String> labels;
  final List<_PlotSeries> series;
  final bool bars;

  @override
  State<_AnimatedPlot> createState() => _AnimatedPlotState();
}

class _AnimatedPlotState extends State<_AnimatedPlot>
    with SingleTickerProviderStateMixin, _RevealMotion {
  late final AnimationController _motion;
  int? _hover;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reveal(_motion);
  }

  @override
  void dispose() {
    disposeReveal();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 188,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, 188);
          final geometry = _geometry(
            size: size,
            count: widget.labels.length,
            bars: widget.bars,
          );
          return MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (event) => _move(event.localPosition, geometry),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              onTapDown: (details) => _move(details.localPosition, geometry),
              child: AnimatedBuilder(
                animation: _motion,
                builder: (context, _) {
                  final hover = _hover;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: size,
                        painter: _PlotPainter(
                          labels: widget.labels,
                          series: widget.series,
                          bars: widget.bars,
                          progress: Curves.easeOutCubic.transform(
                            _motion.value,
                          ),
                          hover: hover,
                          labelColor: scheme.onSurface.withValues(alpha: 0.62),
                          guideColor: scheme.onSurface.withValues(alpha: 0.12),
                        ),
                      ),
                      if (hover != null &&
                          hover >= 0 &&
                          hover < widget.labels.length)
                        _tooltip(geometry.centers[hover], size.width, scheme),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _move(Offset position, _Geometry geometry) {
    final next = geometry.indexAt(position.dx);
    if (next != _hover) setState(() => _hover = next);
  }

  Widget _tooltip(double x, double width, ColorScheme scheme) {
    final index = _hover!;
    final rows = [
      for (final series in widget.series)
        (
          series.values[index] < 0
              ? (series.negative ?? series.color)
              : series.color,
          series.name,
          formatMoney(Money(series.values[index])),
        ),
    ];
    final anchorRight = x > width * 0.62;
    return Positioned(
      left: anchorRight ? x - 12 : x + 12,
      top: 4,
      child: FractionalTranslation(
        translation: Offset(anchorRight ? -1 : 0, 0),
        child: IgnorePointer(
          child: _TooltipCard(
            title: widget.labels[index],
            rows: rows,
            scheme: scheme,
          ),
        ),
      ),
    );
  }
}

class _TooltipCard extends StatelessWidget {
  const _TooltipCard({
    required this.title,
    required this.rows,
    required this.scheme,
  });

  final String title;
  final List<(Color, String, String)> rows;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.inverseSurface,
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: scheme.onInverseSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final row in rows) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Swatch(color: row.$1),
                  const SizedBox(width: 6),
                  Text(
                    '${row.$2}  ${row.$3}',
                    style: TextStyle(color: scheme.onInverseSurface),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Geometry {
  const _Geometry({required this.plot, required this.centers});

  final Rect plot;
  final List<double> centers;

  int? indexAt(double x) {
    if (centers.isEmpty) return null;
    var nearest = 0;
    var best = (x - centers.first).abs();
    for (var index = 1; index < centers.length; index++) {
      final distance = (x - centers[index]).abs();
      if (distance < best) {
        best = distance;
        nearest = index;
      }
    }
    final slot = centers.length == 1 ? plot.width : plot.width / centers.length;
    if (best > slot * 0.65) return null;
    return nearest;
  }
}

_Geometry _geometry({
  required Size size,
  required int count,
  required bool bars,
}) {
  final plot = Rect.fromLTWH(
    16,
    18,
    math.max(0, size.width - 32),
    size.height - 46,
  );
  if (count == 0) return _Geometry(plot: plot, centers: const []);
  if (!bars) {
    return _Geometry(
      plot: plot,
      centers: [
        for (var index = 0; index < count; index++)
          count == 1
              ? plot.center.dx
              : plot.left + plot.width * index / (count - 1),
      ],
    );
  }
  final slot = plot.width / count;
  return _Geometry(
    plot: plot,
    centers: [
      for (var index = 0; index < count; index++)
        plot.left + slot * index + slot / 2,
    ],
  );
}

class _PlotPainter extends CustomPainter {
  _PlotPainter({
    required this.labels,
    required this.series,
    required this.bars,
    required this.progress,
    required this.hover,
    required this.labelColor,
    required this.guideColor,
  });

  final List<String> labels;
  final List<_PlotSeries> series;
  final bool bars;
  final double progress;
  final int? hover;
  final Color labelColor;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty || series.isEmpty) return;
    final geometry = _geometry(size: size, count: labels.length, bars: bars);
    final plot = geometry.plot;
    final values = [if (bars) 0, for (final item in series) ...item.values];
    var min = values.reduce(math.min);
    var max = values.reduce(math.max);
    if (min == max) max = min + 1;
    final span = max - min;
    double yAt(int value) {
      final ratio = (value - min) / span;
      return plot.bottom - ratio * plot.height;
    }

    final zero = yAt(0).clamp(plot.top, plot.bottom);
    canvas.drawLine(
      Offset(plot.left, zero),
      Offset(plot.right, zero),
      Paint()
        ..color = guideColor
        ..strokeWidth = 1,
    );

    final labelStyle = TextStyle(color: labelColor, fontSize: 11);
    for (var index = 0; index < labels.length; index++) {
      final painter = TextPainter(
        text: TextSpan(text: labels[index], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          geometry.centers[index] - painter.width / 2,
          size.height - painter.height - 2,
        ),
      );
    }

    if (hover != null) {
      final x = geometry.centers[hover!];
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = labelColor.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }

    if (bars) {
      _bars(canvas, plot, geometry, yAt, zero);
    } else {
      _lines(canvas, plot, geometry, yAt);
    }
  }

  void _lines(
    Canvas canvas,
    Rect plot,
    _Geometry geometry,
    double Function(int value) yAt,
  ) {
    for (final item in series) {
      final points = <Offset>[
        for (var index = 0; index < item.values.length; index++)
          Offset(
            geometry.centers[index],
            plot.bottom - (plot.bottom - yAt(item.values[index])) * progress,
          ),
      ];
      if (points.isEmpty) continue;
      final curve = _curve(points);
      final fill = Path.from(curve)
        ..lineTo(points.last.dx, plot.bottom)
        ..lineTo(points.first.dx, plot.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()..color = item.color.withValues(alpha: 0.16),
      );
      canvas.drawPath(
        curve,
        Paint()
          ..color = item.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      for (var index = 0; index < points.length; index++) {
        final active = hover == index;
        canvas.drawCircle(
          points[index],
          active ? 6 : 3.5,
          Paint()..color = item.color,
        );
        if (active) {
          canvas.drawCircle(
            points[index],
            10,
            Paint()
              ..color = item.color.withValues(alpha: 0.25)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6,
          );
        }
      }
    }
  }

  void _bars(
    Canvas canvas,
    Rect plot,
    _Geometry geometry,
    double Function(int value) yAt,
    double zero,
  ) {
    final count = labels.length;
    final slot = plot.width / count;
    final width = math.min(18.0, (slot * 0.72) / series.length);
    for (var index = 0; index < count; index++) {
      final active = hover == null || hover == index;
      final groupWidth = width * series.length;
      var left = geometry.centers[index] - groupWidth / 2;
      for (final item in series) {
        final raw = item.values[index];
        final shown = (raw * progress).round();
        final top = math.min(yAt(shown), zero);
        final bottom = math.max(yAt(shown), zero);
        final color = raw < 0 ? (item.negative ?? item.color) : item.color;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              left,
              top,
              left + width - 3,
              math.max(bottom, top + 2),
            ),
            const Radius.circular(6),
          ),
          Paint()..color = color.withValues(alpha: active ? 1 : 0.28),
        );
        left += width;
      }
    }
  }

  Path _curve(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final current = points[index];
      final next = points[index + 1];
      final midX = (current.dx + next.dx) / 2;
      path.cubicTo(midX, current.dy, midX, next.dy, next.dx, next.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _PlotPainter oldDelegate) => true;
}

class _HoverDonut extends StatefulWidget {
  const _HoverDonut({required this.slices, required this.colors});

  final List<CategorySlice> slices;
  final List<Color> colors;

  @override
  State<_HoverDonut> createState() => _HoverDonutState();
}

class _HoverDonutState extends State<_HoverDonut>
    with SingleTickerProviderStateMixin, _RevealMotion {
  late final AnimationController _motion;
  int? _hover;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reveal(_motion);
  }

  @override
  void dispose() {
    disposeReveal();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.slices.fold<int>(
      0,
      (sum, slice) => sum + slice.amount.cents,
    );
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 132,
      height: 132,
      child: MouseRegion(
        onHover: (event) => _move(event.localPosition, total),
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          onTapDown: (details) => _move(details.localPosition, total),
          child: AnimatedBuilder(
            animation: _motion,
            builder: (context, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  CustomPaint(
                    size: const Size(132, 132),
                    painter: _DonutPainter(
                      values: [
                        for (final slice in widget.slices) slice.amount.cents,
                      ],
                      colors: widget.colors,
                      progress: Curves.easeOutCubic.transform(_motion.value),
                      hover: _hover,
                    ),
                  ),
                  if (_hover != null)
                    Center(
                      child: SizedBox(
                        width: 74,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.slices[_hover!].label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              formatMoney(widget.slices[_hover!].amount),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _share(
                                widget.slices[_hover!].amount.cents,
                                total,
                              ),
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _move(Offset position, int total) {
    if (total <= 0) return;
    final center = const Offset(66, 66);
    final delta = position - center;
    final distance = delta.distance;
    if (distance < 28 || distance > 66) {
      if (_hover != null) setState(() => _hover = null);
      return;
    }
    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    var cursor = 0.0;
    for (var index = 0; index < widget.slices.length; index++) {
      final sweep = widget.slices[index].amount.cents / total * math.pi * 2;
      if (angle <= cursor + sweep) {
        if (_hover != index) setState(() => _hover = index);
        return;
      }
      cursor += sweep;
    }
  }
}

String _share(int cents, int total) {
  if (total <= 0) return '0%';
  return '${(cents * 100 / total).round()}%';
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.progress,
    required this.hover,
  });

  final List<int> values;
  final List<Color> colors;
  final double progress;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    var start = -math.pi / 2;
    final revealed = progress.clamp(0, 1);
    var remaining = revealed * math.pi * 2;
    for (var index = 0; index < values.length; index++) {
      final full = values[index] / total * math.pi * 2;
      final sweep = math.min(full, remaining);
      if (sweep <= 0) break;
      final active = hover == null || hover == index;
      final radius = hover == index ? 54.0 : 48.0;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        math.max(0, sweep - 0.03),
        false,
        Paint()
          ..color = colors[index].withValues(alpha: active ? 1 : 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = hover == index ? 18 : 14
          ..strokeCap = StrokeCap.butt,
      );
      start += full;
      remaining -= full;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

List<CategorySlice> _topSlices(List<CategorySlice> slices) {
  final positive = [
    for (final slice in slices)
      if (slice.amount.cents > 0) slice,
  ];
  if (positive.length <= 6) return positive;
  var rest = 0;
  for (final slice in positive.skip(5)) {
    rest += slice.amount.cents;
  }
  return [
    ...positive.take(5),
    CategorySlice(label: 'Outros', amount: Money(rest)),
  ];
}

String _monthLabel(LocalDate date) {
  return monthNames[date.month - 1].substring(0, 3);
}

Color _tone(BuildContext context, {required bool income}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (income) return dark ? AppColors.accentDark : AppColors.accent;
  return dark ? AppColors.expenseDark : AppColors.expense;
}
