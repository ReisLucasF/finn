import 'package:finan/core/date/local_date.dart';
import 'package:finan/domain/entities/investment_yield.dart';

abstract class InvestmentYieldRepository {
  Future<void> save(InvestmentYield config);

  Future<void> delete(String investmentId);

  Future<List<InvestmentYield>> listByUser(String userId);
}

/// Séries do Banco Central em cache local.
abstract class MarketDataRepository {
  static const cdiDaily = 12;
  static const cdiMonthly = 4391;
  static const cdiAnnual = 4389;

  Future<void> saveValues(int series, List<(LocalDate, double)> values);

  /// Valores da série a partir de [from] (inclusive), ou todos.
  Future<Map<LocalDate, double>> values(int series, {LocalDate? from});

  Future<(LocalDate, double)?> latest(int series);

  Future<LocalDate?> earliest(int series);
}

/// Fonte remota das séries (API SGS do BCB).
abstract class MarketDataGateway {
  /// Série diária entre as datas (inclusive). Divide em janelas aceitas
  /// pela API.
  Future<List<(LocalDate, double)>> daily(
    int series,
    LocalDate from,
    LocalDate to,
  );

  /// Últimos [count] valores da série.
  Future<List<(LocalDate, double)>> latest(int series, int count);
}
