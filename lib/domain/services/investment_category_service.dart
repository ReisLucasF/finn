import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/enums/transaction_type.dart';
import 'package:finan/domain/services/ofx_normalizer.dart';

class InvestmentCashEvent {
  const InvestmentCashEvent({
    required this.description,
    required this.type,
    required this.amount,
    required this.date,
    this.transactionId,
    this.accountId,
    this.accountName,
    this.investmentId,
  });

  final String description;
  final TransactionType type;
  final Money amount;
  final LocalDate date;
  final String? transactionId;
  final String? accountId;
  final String? accountName;
  final String? investmentId;

  bool get isLinked => investmentId != null;
}

class InvestmentProductBucket {
  const InvestmentProductBucket({
    required this.key,
    required this.label,
    required this.openCapital,
    required this.realizedGain,
    required this.events,
  });

  final String key;
  final String label;
  final Money openCapital;
  final Money realizedGain;
  final List<InvestmentCashEvent> events;
}

class InvestmentCategorySnapshot {
  const InvestmentCategorySnapshot({
    required this.openCapital,
    required this.realizedGain,
    this.products = const [],
  });

  /// Aportes que ainda não voltaram para a conta. Entram no patrimônio.
  final Money openCapital;

  /// Resgate acima da aplicação correspondente. Já está na conta e não é receita.
  final Money realizedGain;

  final List<InvestmentProductBucket> products;
}

/// Emparelha aporte/resgate do mesmo produto mesmo com nomes de extrato diferentes.
String normalizeInvestmentKey(String raw) {
  var text = normalizeDescription(raw);
  text = text.replaceFirst(
    RegExp(r'^dinheiro (reservado|retirado) '),
    'reserva ',
  );
  text = text.replaceAll(RegExp(r'\bs\s+a\b'), 'sa');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

class InvestmentCategoryService {
  const InvestmentCategoryService();

  InvestmentCategorySnapshot settle(
    Iterable<InvestmentCashEvent> events, {
    LocalDate? gainFromInclusive,
    LocalDate? gainToExclusive,
  }) {
    final groups = <String, List<InvestmentCashEvent>>{};
    for (final event in events) {
      if (event.type != TransactionType.investmentContribution &&
          event.type != TransactionType.investmentWithdrawal) {
        continue;
      }
      groups
          .putIfAbsent(normalizeInvestmentKey(event.description), () => [])
          .add(event);
    }
    var openCents = 0;
    var gainCents = 0;
    final products = <InvestmentProductBucket>[];
    for (final entry in groups.entries) {
      final sorted = [...entry.value]..sort((left, right) {
        final byDate = left.date.compareTo(right.date);
        if (byDate != 0) return byDate;
        return left.type == right.type
            ? 0
            : left.type == TransactionType.investmentContribution
            ? -1
            : 1;
      });
      var capital = 0;
      var gain = 0;
      for (final event in sorted) {
        if (event.type == TransactionType.investmentContribution) {
          capital += event.amount.cents;
          continue;
        }
        final inPeriod = _inPeriod(event.date, gainFromInclusive, gainToExclusive);
        if (event.amount.cents <= capital) {
          capital -= event.amount.cents;
          continue;
        }
        final extra = event.amount.cents - capital;
        capital = 0;
        if (inPeriod) gain += extra;
      }
      openCents += capital;
      gainCents += gain;
      products.add(
        InvestmentProductBucket(
          key: entry.key,
          label: _labelFor(sorted),
          openCapital: Money(capital),
          realizedGain: Money(gain),
          events: sorted,
        ),
      );
    }
    products.sort((a, b) => b.openCapital.cents.compareTo(a.openCapital.cents));
    return InvestmentCategorySnapshot(
      openCapital: Money(openCents),
      realizedGain: Money(gainCents),
      products: products,
    );
  }

  String _labelFor(List<InvestmentCashEvent> events) {
    for (final event in events.reversed) {
      final text = event.description.trim();
      if (text.isNotEmpty) return text;
    }
    return 'Investimento';
  }

  bool _inPeriod(LocalDate date, LocalDate? from, LocalDate? toExclusive) {
    if (from != null && date < from) return false;
    if (toExclusive != null && date >= toExclusive) return false;
    return true;
  }

  /// Total investido resiliente a vínculo parcial (ex.: só resgates vinculados).
  ///
  /// `cadastrados + abertura(todo o extrato) − abertura(só vinculados)`.
  Money totalInvested({
    required Iterable<Money> registeredValues,
    required Iterable<InvestmentCashEvent> allCashEvents,
  }) {
    var registered = 0;
    for (final value in registeredValues) {
      registered += value.cents;
    }
    final allOpen = settle(allCashEvents).openCapital.cents;
    final linkedOpen = settle([
      for (final event in allCashEvents)
        if (event.isLinked) event,
    ]).openCapital.cents;
    final total = registered + allOpen - linkedOpen;
    return Money(total < 0 ? 0 : total);
  }

  /// Capital ainda fora de investimentos cadastrados (para o breakdown da UI).
  Money unlinkedOpenCapital(Iterable<InvestmentCashEvent> allCashEvents) {
    final allOpen = settle(allCashEvents).openCapital.cents;
    final linkedOpen = settle([
      for (final event in allCashEvents)
        if (event.isLinked) event,
    ]).openCapital.cents;
    final open = allOpen - linkedOpen;
    return Money(open < 0 ? 0 : open);
  }
}
