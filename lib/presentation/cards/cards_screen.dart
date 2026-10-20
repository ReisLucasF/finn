import 'package:finan/app/app_scope.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/core/theme/app_colors.dart';
import 'package:finan/core/theme/app_spacing.dart';
import 'package:finan/core/theme/app_typography.dart';
import 'package:finan/domain/entities/planning.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/repositories/finance_repository.dart';
import 'package:finan/domain/services/card_limit_service.dart';
import 'package:finan/presentation/format/finance_format.dart';
import 'package:finan/presentation/shared/feedback_widgets.dart';
import 'package:finan/presentation/shared/finan_card.dart';
import 'package:finan/presentation/shared/finan_page.dart';
import 'package:finan/presentation/shared/finan_widgets.dart';
import 'package:finan/presentation/shared/motion.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  final CardLimitService _limits = const CardLimitService();
  List<CreditCard> _cards = const [];
  List<CardUsage> _usage = const [];
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
    setState(() {
      _loading = _cards.isEmpty;
      _error = null;
    });
    try {
      final scope = AppScope.of(context);
      final userId = scope.session.user.id;
      final cards = await scope.graph.finance.listCreditCards(userId);
      final usage = await scope.graph.finance.cardUsage(userId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _usage = usage;
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

  Money _used(CreditCard card) {
    for (final usage in _usage) {
      if (usage.cardId == card.id) {
        return _limits.used(
          initialUsed: usage.initialUsed,
          confirmedEntries: usage.confirmedEntries,
        );
      }
    }
    return card.initialUsedLimit;
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final limit = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Novo cartão'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: limit,
                decoration: const InputDecoration(labelText: 'Limite'),
                keyboardType: TextInputType.number,
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
        );
      },
    );
    if (saved != true || !mounted) return;
    final parsed = tryParseMoney(limit.text);
    if (parsed == null) return;
    try {
      final scope = AppScope.of(context);
      await scope.graph.createCreditCard(
        userId: scope.session.user.id,
        name: name.text,
        creditLimit: parsed,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _purchase(CreditCard card) async {
    final scope = AppScope.of(context);
    final categories = await scope.graph.listCategories(
      scope.session.user.id,
      includeInactive: false,
    );
    final expenses = [
      for (final category in categories)
        if (category.type.accepts(TransactionType.expense)) category,
    ];
    if (!mounted || expenses.isEmpty) return;
    final amount = TextEditingController();
    String categoryId = expenses.first.id;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Compra em ${card.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                decoration: const InputDecoration(labelText: 'Valor'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: categoryId,
                items: [
                  for (final category in expenses)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
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
              child: const Text('Lançar'),
            ),
          ],
        );
      },
    );
    final parsed = tryParseMoney(amount.text);
    if (saved != true || parsed == null || !mounted) return;
    try {
      await AppScope.of(context).graph.createCardPurchase(
        userId: AppScope.of(context).session.user.id,
        cardId: card.id,
        categoryId: categoryId,
        amount: parsed,
        date: AppScope.of(context).graph.clock.today(),
      );
      if (!mounted) return;
      showSuccess(context, 'Compra lançada no cartão');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  Future<void> _pay(CreditCard card) async {
    final scope = AppScope.of(context);
    final accounts = await scope.graph.accounts.listByUser(
      scope.session.user.id,
      includeInactive: false,
    );
    if (!mounted || accounts.isEmpty) return;
    final amount = TextEditingController();
    var accountId = accounts.first.id;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Pagar ${card.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                decoration: const InputDecoration(labelText: 'Valor'),
                keyboardType: TextInputType.number,
              ),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) accountId = value;
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
              child: const Text('Pagar'),
            ),
          ],
        );
      },
    );
    final parsed = tryParseMoney(amount.text);
    if (saved != true || parsed == null || !mounted) return;
    try {
      await AppScope.of(context).graph.payCreditCard(
        userId: AppScope.of(context).session.user.id,
        cardId: card.id,
        accountId: accountId,
        amount: parsed,
        date: AppScope.of(context).graph.clock.today(),
      );
      if (!mounted) return;
      showSuccess(context, 'Fatura paga sem nova despesa');
      await _load();
    } catch (error) {
      if (!mounted) return;
      showError(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return FinanPage(
      title: 'Cartões',
      subtitle: 'Limites e faturas',
      trailing: IconButton.filledTonal(
        tooltip: 'Novo cartão',
        onPressed: _create,
        icon: const Icon(CupertinoIcons.add),
      ),
      body: _loading && _cards.isEmpty
          ? const LoadingSkeleton()
          : _error != null
          ? ErrorView(message: friendlyError(_error!), onRetry: _load)
          : _cards.isEmpty
          ? EmptyView(
              icon: CupertinoIcons.creditcard,
              message: 'Nenhum cartão cadastrado.',
              detail:
                  'Cadastre seus cartões para acompanhar o limite usado e '
                  'pagar a fatura sem duplicar despesas.',
              actionLabel: 'Novo cartão',
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
    final active = [
      for (final card in _cards)
        if (card.isActive && !card.isDeleted) card,
    ];
    var limitCents = 0;
    var usedCents = 0;
    for (final card in active) {
      limitCents += card.creditLimit.cents;
      usedCents += _used(card).cents;
    }
    final available = Money(limitCents - usedCents);
    final utilization = limitCents <= 0 ? 0.0 : usedCents / limitCents;
    final brightness = Theme.of(context).brightness;
    var order = 0;
    Widget step(Widget child) => FadeSlideIn(index: order++, child: child);
    return ListView(
      padding: screenPadding(context),
      children: [
        step(
          FinanHero(
            icon: CupertinoIcons.creditcard_fill,
            label: 'Fatura em aberto',
            value: Money(usedCents),
            caption: '${(utilization * 100).round()}% do limite total em uso',
            side: ProgressRing(
              value: utilization,
              color: utilization >= 0.8
                  ? AppColors.warningDark
                  : AppColors.accentDark,
              size: 84,
              stroke: 8,
              child: Text(
                '${(utilization * 100).round()}%',
                style: AppTypography.label(Colors.white)
                    .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            stats: [
              HeroStat(
                icon: CupertinoIcons.chart_bar_alt_fill,
                label: 'Limite total',
                money: Money(limitCents),
              ),
              HeroStat(
                icon: CupertinoIcons.checkmark_circle,
                label: 'Disponível',
                money: available,
              ),
              HeroStat(
                icon: CupertinoIcons.rectangle_stack,
                label: 'Cartões',
                text: '${active.length}',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        step(
          SectionHeader(
            title: 'Seus cartões',
            subtitle: 'Pagar a fatura não gera despesa nova',
            action: 'Novo cartão',
            onAction: _create,
          ),
        ),
        step(
          TileGrid(
            columns: gridColumns(width),
            spacing: AppSpacing.md,
            children: [
              for (var i = 0; i < _cards.length; i++)
                _CardTile(
                  card: _cards[i],
                  used: _used(_cards[i]),
                  available: _limits.available(
                    limit: _cards[i].creditLimit,
                    used: _used(_cards[i]),
                  ),
                  palette: _cardPalettes[i % _cardPalettes.length],
                  brightness: brightness,
                  onPurchase: () => _purchase(_cards[i]),
                  onPay: () => _pay(_cards[i]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

const _cardPalettes = <List<Color>>[
  [Color(0xFF0B4A37), Color(0xFF1C7A5C)],
  [Color(0xFF26304F), Color(0xFF4A5A8C)],
  [Color(0xFF4A1F2A), Color(0xFF8C3B4F)],
  [Color(0xFF3B2F1A), Color(0xFF8A6A2F)],
  [Color(0xFF1F2937), Color(0xFF4B5563)],
];

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.card,
    required this.used,
    required this.available,
    required this.palette,
    required this.brightness,
    required this.onPurchase,
    required this.onPay,
  });

  final CreditCard card;
  final Money used;
  final Money available;
  final List<Color> palette;
  final Brightness brightness;
  final VoidCallback onPurchase;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final limit = card.creditLimit.cents;
    final ratio = limit <= 0 ? 0.0 : used.cents / limit;
    final color = ratio >= 1
        ? AppColors.expenseOf(brightness)
        : ratio >= 0.8
        ? AppColors.warningOf(brightness)
        : AppColors.incomeOf(brightness);
    final soft = Colors.white.withValues(alpha: 0.72);
    final cycleText = [
      if (card.closingDay != null) 'fecha dia ${card.closingDay}',
      if (card.dueDay != null) 'vence dia ${card.dueDay}',
    ].join(' · ');
    final cycle = cycleText.isEmpty
        ? ''
        : cycleText[0].toUpperCase() + cycleText.substring(1);
    // Emissor e bandeira sem repetir (ex.: "VISA · VISA").
    final issuer = <String>{
      for (final part in [card.issuer, card.brand])
        if (part != null && part.trim().isNotEmpty) part.trim().toUpperCase(),
    }.join(' · ');
    return Semantics(
      label:
          '${card.name}. Usado ${formatMoney(used)} de '
          '${formatMoney(card.creditLimit)}. Disponível ${formatMoney(available)}.',
      child: FinanCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Frente do cartão.
              AspectRatio(
                aspectRatio: 1.9,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: palette.first.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Opacity(
                    opacity: card.isActive ? 1 : 0.6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                card.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.label(Colors.white)
                                    .copyWith(fontSize: 15),
                              ),
                            ),
                            Icon(CupertinoIcons.wifi, size: 18, color: soft),
                          ],
                        ),
                        if (issuer.isNotEmpty)
                          Text(
                            issuer,
                            style: AppTypography.label(soft)
                                .copyWith(fontSize: 11.5),
                          ),
                        const Spacer(),
                        Container(
                          width: 34,
                          height: 24,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE9D9A6), Color(0xFFBFA05A)],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                card.lastFourDigits == null
                                    ? '•••• •••• ••••'
                                    : '•••• •••• •••• ${card.lastFourDigits}',
                                style: AppTypography.label(soft)
                                    .copyWith(fontSize: 13, letterSpacing: 1.4),
                              ),
                            ),
                            if (!card.isActive)
                              const DeltaChip(
                                label: 'Inativo',
                                color: Colors.white,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fatura atual',
                                style: AppTypography.label(
                                  scheme.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: AnimatedMoney(
                                  value: used,
                                  style: AppTypography.headline(
                                    scheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(ratio * 100).round()}%',
                          style: AppTypography.headline(color)
                              .copyWith(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AnimatedProgressBar(value: ratio, color: color),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Disponível ${formatMoney(available)} de '
                      '${formatMoney(card.creditLimit)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (cycle.isNotEmpty)
                      Text(
                        cycle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _CardAction(
                            icon: CupertinoIcons.bag,
                            label: 'Compra',
                            onTap: onPurchase,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: _CardAction(
                            icon: CupertinoIcons.checkmark_seal,
                            label: 'Pagar fatura',
                            onTap: onPay,
                            primary: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
    );
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    return primary
        ? FilledButton.tonal(onPressed: onTap, style: style, child: child)
        : OutlinedButton(onPressed: onTap, style: style, child: child);
  }
}
