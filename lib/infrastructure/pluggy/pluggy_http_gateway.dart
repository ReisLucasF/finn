import 'dart:convert';
import 'dart:io';

import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/core/money/money.dart';
import 'package:finan/domain/pluggy/pluggy_models.dart';
import 'package:finan/domain/repositories/pluggy_gateway.dart';
import 'package:finan/domain/services/pluggy_classifier.dart';

String pluggyStatusMessage(int status, Map<String, Object?> body) {
  return switch (body['codeDescription']) {
    'CLIENT_KEYS_UNAUTHORIZED' =>
      'O client id ou o client secret foi recusado pelo Pluggy. Copie os dois de novo, da mesma aplicação.',
    'CLIENT_DISABLED' => 'A aplicação está desativada no painel do Pluggy.',
    'ITEM_USER_ALREADY_EXISTS' =>
      'Esse banco ainda existe no painel. Use «Informar itens do painel» ou autorize outro banco no Connect.',
    'LIST_ITEMS_FEATURE_NOT_ENABLED' =>
      'A listagem de itens não está liberada nesta aplicação. Use Conectar banco para cada instituição.',
    _ => 'Não foi possível falar com o Pluggy ($status).',
  };
}

class PluggyHttpGateway implements PluggyGateway {
  const PluggyHttpGateway({this.classifier = const PluggyClassifier()});

  final PluggyClassifier classifier;
  static final Map<String, ({String key, DateTime expires})> _keys = {};

  @override
  Future<PluggyItemListing> listItems({
    required String clientId,
    required String clientSecret,
  }) async {
    final apiKey = await _apiKey(clientId, clientSecret);
    final items = <PluggyItem>[];
    var next = '';
    for (var page = 0; page < 10; page++) {
      final reply = await _send(
        method: 'GET',
        uri: _itemsUri(next),
        apiKey: apiKey,
      );
      if (reply.status == 403) {
        return PluggyItemListing(items: items, listingEnabled: false);
      }
      if (reply.status < 200 || reply.status >= 300) {
        throw ValidationException(pluggyStatusMessage(reply.status, reply.body));
      }
      final results = reply.body['results'] as List<Object?>? ?? const [];
      for (final item in results) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! String || id.isEmpty) continue;
        final connector = item['connector'];
        final rawName = connector is Map ? connector['name'] : null;
        final name = rawName is String && rawName.trim().isNotEmpty
            ? rawName.trim()
            : 'Conexão';
        final status = item['status'];
        items.add(
          PluggyItem(
            id: id,
            connectorName: name,
            status: status is String ? status : null,
          ),
        );
      }
      final cursor = reply.body['next'];
      if (cursor is! String || cursor.isEmpty) break;
      next = cursor;
    }
    return PluggyItemListing(items: items, listingEnabled: true);
  }

  @override
  Future<String> connectToken({
    required String clientId,
    required String clientSecret,
    required String clientUserId,
  }) async {
    final apiKey = await _apiKey(clientId, clientSecret);
    final reply = await _send(
      method: 'POST',
      uri: Uri.parse('https://api.pluggy.ai/connect_token'),
      apiKey: apiKey,
      jsonBody: {
        'options': {
          'clientUserId': clientUserId,
          'avoidDuplicates': true,
        },
      },
    );
    if (reply.status < 200 || reply.status >= 300) {
      throw ValidationException(pluggyStatusMessage(reply.status, reply.body));
    }
    final token = reply.body['accessToken'] as String?;
    if (token == null || token.isEmpty) {
      throw const ValidationException('O Pluggy Connect não devolveu um token.');
    }
    return token;
  }

  @override
  Future<List<PluggyRemoteAccount>> accounts({
    required String clientId,
    required String clientSecret,
    required String itemId,
  }) async {
    final apiKey = await _apiKey(clientId, clientSecret);
    final body = await _get(
      apiKey,
      Uri.parse('https://api.pluggy.ai/accounts?itemId=$itemId'),
    );
    final results = body['results'] as List<Object?>? ?? const [];
    return [
      for (final item in results)
        if (item is Map)
          PluggyRemoteAccount(
            id: item['id']! as String,
            name: (item['marketingName'] ?? item['name'] ?? 'Conta') as String,
            kind: (item['type'] as String?) ?? 'BANK',
            itemId: itemId,
            creditLimit: _creditLimit(item['creditData']),
            brand: _text(_field(item['creditData'], 'brand')),
            lastFourDigits: _lastFour(item['number']),
            closingDay: _dayOf(_field(item['creditData'], 'balanceCloseDate')),
            dueDay: _dayOf(_field(item['creditData'], 'balanceDueDate')),
          ),
    ];
  }

  @override
  Future<List<PluggyRemoteTransaction>> transactions({
    required String clientId,
    required String clientSecret,
    required String accountId,
    required DateTime from,
    required DateTime to,
  }) async {
    final apiKey = await _apiKey(clientId, clientSecret);
    final fromIso = _day(from);
    final toIso = _day(to);
    final rows = <PluggyRemoteTransaction>[];
    var page = 1;
    while (page <= 20) {
      final body = await _get(
        apiKey,
        Uri.parse(
          'https://api.pluggy.ai/transactions?accountId=$accountId'
          '&from=$fromIso&to=$toIso&page=$page&pageSize=500',
        ),
      );
      final results = body['results'] as List<Object?>? ?? const [];
      for (final item in results) {
        if (item is! Map) continue;
        final amount = item['amount'];
        if (amount is! num) continue;
        final rawDate = item['date'] as String?;
        if (rawDate == null) continue;
        rows.add(
          PluggyRemoteTransaction(
            id: item['id']! as String,
            accountId: accountId,
            description: (item['description'] as String?)?.trim().isNotEmpty == true
                ? (item['description'] as String).trim()
                : 'Lançamento',
            date: _localDate(rawDate),
            amount: Money(classifier.cents(amount)),
            type: (item['type'] as String?) ?? 'DEBIT',
            status: (item['status'] as String?) ?? 'PENDING',
            operationType: item['operationType'] as String?,
            category: _text(item['category']),
          ),
        );
      }
      final totalPages = body['totalPages'];
      if (totalPages is num && page >= totalPages) break;
      if (results.length < 500) break;
      page++;
    }
    return rows;
  }

  Future<String> _apiKey(String clientId, String clientSecret) async {
    final now = DateTime.now().toUtc();
    final cached = _keys[clientId];
    if (cached != null && now.isBefore(cached.expires)) return cached.key;
    final body = await _request(
      method: 'POST',
      uri: Uri.parse('https://api.pluggy.ai/auth'),
      jsonBody: {'clientId': clientId, 'clientSecret': clientSecret},
    );
    final apiKey = body['apiKey'] as String?;
    if (apiKey == null || apiKey.isEmpty) {
      throw const ValidationException('O Pluggy não devolveu uma chave.');
    }
    _keys[clientId] = (
      key: apiKey,
      expires: now.add(const Duration(minutes: 90)),
    );
    return apiKey;
  }

  Future<Map<String, Object?>> _get(String apiKey, Uri uri) {
    return _request(method: 'GET', uri: uri, apiKey: apiKey);
  }

  Future<Map<String, Object?>> _request({
    required String method,
    required Uri uri,
    String? apiKey,
    Map<String, Object?>? jsonBody,
  }) async {
    final reply = await _send(
      method: method,
      uri: uri,
      apiKey: apiKey,
      jsonBody: jsonBody,
    );
    if (reply.status < 200 || reply.status >= 300) {
      throw ValidationException(pluggyStatusMessage(reply.status, reply.body));
    }
    return reply.body;
  }

  Future<({int status, Map<String, Object?> body})> _send({
    required String method,
    required Uri uri,
    String? apiKey,
    Map<String, Object?>? jsonBody,
  }) async {
    final client = HttpClient();
    try {
      final request = method == 'POST'
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (apiKey != null) request.headers.set('X-API-KEY', apiKey);
      if (jsonBody != null) {
        final bytes = utf8.encode(jsonEncode(jsonBody));
        request.headers.contentType = ContentType.json;
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      Object? decoded;
      try {
        decoded = text.isEmpty ? null : jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
      final body = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
      return (status: response.statusCode, body: body);
    } on ValidationException {
      rethrow;
    } catch (_) {
      throw const ValidationException('Não foi possível falar com o Pluggy.');
    } finally {
      client.close();
    }
  }

  Uri _itemsUri(String next) {
    if (next.isEmpty) return Uri.parse('https://api.pluggy.ai/v2/items');
    if (next.startsWith('http')) return Uri.parse(next);
    if (next.startsWith('/')) return Uri.parse('https://api.pluggy.ai$next');
    return Uri.parse('https://api.pluggy.ai/v2/items$next');
  }

  Money? _creditLimit(Object? credit) {
    final raw = _field(credit, 'creditLimit');
    if (raw is! num || raw < 0) return null;
    return Money(classifier.cents(raw));
  }

  Object? _field(Object? source, String key) {
    if (source is! Map) return null;
    return source[key];
  }

  String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _lastFour(Object? number) {
    if (number is! String) return null;
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return null;
    return digits.substring(digits.length - 4);
  }

  int? _dayOf(Object? raw) {
    if (raw is! String || raw.length < 10) return null;
    final head = raw.substring(0, 10);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(head)) return null;
    final day = int.tryParse(head.substring(8));
    if (day == null || day < 1 || day > 31) return null;
    return day;
  }

  String _day(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  LocalDate _localDate(String raw) {
    if (raw.length == 10) return LocalDate.parse(raw);
    final utc = DateTime.parse(raw).toUtc();
    final saoPaulo = utc.subtract(const Duration(hours: 3));
    return LocalDate(saoPaulo.year, saoPaulo.month, saoPaulo.day);
  }
}
