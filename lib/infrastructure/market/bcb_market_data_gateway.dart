import 'dart:convert';

import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/app_exception.dart';
import 'package:finan/domain/repositories/investment_yield_repository.dart';
import 'package:http/http.dart' as http;

/// API pública SGS do Banco Central.
///
/// Séries diárias exigem `dataInicial` e aceitam janelas de no máximo
/// 10 anos; pedimos em blocos de 5 anos.
class BcbMarketDataGateway implements MarketDataGateway {
  BcbMarketDataGateway({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const _base = 'https://api.bcb.gov.br/dados/serie/bcdata.sgs';
  static const _timeout = Duration(seconds: 20);

  @override
  Future<List<(LocalDate, double)>> daily(
    int series,
    LocalDate from,
    LocalDate to,
  ) async {
    final result = <(LocalDate, double)>[];
    var start = from;
    while (start <= to) {
      final windowEnd = start.addMonths(60).addDays(-1);
      final end = windowEnd < to ? windowEnd : to;
      result.addAll(
        await _get(
          Uri.parse(
            '$_base.$series/dados?formato=json'
            '&dataInicial=${_br(start)}&dataFinal=${_br(end)}',
          ),
        ),
      );
      start = end.addDays(1);
    }
    return result;
  }

  @override
  Future<List<(LocalDate, double)>> latest(int series, int count) {
    return _get(Uri.parse('$_base.$series/dados/ultimos/$count?formato=json'));
  }

  Future<List<(LocalDate, double)>> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await (_client?.get(uri) ?? http.get(uri)).timeout(_timeout);
    } catch (_) {
      throw const AppException(
        'Sem conexão com o Banco Central para atualizar o CDI.',
        code: 'market_offline',
      );
    }
    // Sem dados no intervalo a API responde 404 com corpo vazio ou erro.
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) {
      throw AppException(
        'O Banco Central respondeu ${response.statusCode} ao consultar o CDI.',
        code: 'market_http',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map &&
            item['data'] is String &&
            double.tryParse('${item['valor']}') != null)
          (_parseBr(item['data'] as String), double.parse('${item['valor']}')),
    ];
  }

  static String _br(LocalDate date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  static LocalDate _parseBr(String text) {
    final parts = text.split('/');
    return LocalDate(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  }
}
