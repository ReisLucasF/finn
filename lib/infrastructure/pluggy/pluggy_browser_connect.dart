import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finan/core/errors/validation_exception.dart';
import 'package:finan/domain/pluggy/pluggy_item_id.dart';
import 'package:finan/domain/pluggy/pluggy_models.dart';
import 'package:finan/domain/repositories/pluggy_connect.dart';

class PluggyBrowserConnect implements PluggyConnect {
  Completer<void>? _cancelled;

  @override
  Future<List<PluggyItem>> open({required String connectToken}) async {
    final cancelled = Completer<void>();
    _cancelled = cancelled;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final result = Completer<List<PluggyItem>>();
    final callback = 'http://127.0.0.1:${server.port}/done';
    final html = _html(connectToken, callback);
    try {
      server.listen((request) => _answer(request, result, html));
      final opened = await Process.run('cmd', [
        '/c',
        'start',
        '',
        'http://127.0.0.1:${server.port}/',
      ]);
      if (opened.exitCode != 0) {
        throw const ValidationException('Não foi possível abrir o navegador.');
      }
      return await Future.any<List<PluggyItem>>([
        result.future,
        cancelled.future.then((_) => const <PluggyItem>[]),
        Future<List<PluggyItem>>.delayed(
          const Duration(minutes: 10),
          () => const <PluggyItem>[],
        ),
      ]);
    } finally {
      if (identical(_cancelled, cancelled)) _cancelled = null;
      await server.close(force: true);
    }
  }

  @override
  void cancel() {
    final cancelled = _cancelled;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
  }

  Future<void> _answer(
    HttpRequest request,
    Completer<List<PluggyItem>> result,
    String html,
  ) async {
    final path = request.uri.path;
    if (path == '/' || path.isEmpty) {
      request.response.headers.contentType = ContentType.html;
      request.response.write(html);
      await request.response.close();
      return;
    }
    if (path != '/done') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final params = request.uri.queryParameters;
    final items = _itemsFrom(params);
    final error = params['error'];
    final already = error == 'ITEM_USER_ALREADY_EXISTS';
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      _donePage(
        items.isNotEmpty
            ? already
                  ? 'Esse banco já estava ligado. Pode voltar ao Finn e autorizar outro.'
                  : 'Conexão recebida. Pode voltar ao Finn.'
            : _clean(error ?? 'A conexão não foi concluída.'),
      ),
    );
    await request.response.close();
    if (result.isCompleted) return;
    if (items.isNotEmpty) {
      result.complete(items);
      return;
    }
    if (error != null) {
      result.completeError(
        ValidationException(
          already
              ? 'Esse banco já está ligado. No Pluggy Connect, autorize outro banco do Meu Pluggy.'
              : _clean(error),
        ),
      );
    }
  }

  List<PluggyItem> _itemsFrom(Map<String, String> params) {
    final name = _clip(params['name'] ?? '');
    final connector = name.isEmpty ? 'Conexão' : name;
    final ids = <String>{
      if (isPluggyItemId(params['id'])) params['id']!.trim(),
      for (final part in (params['ids'] ?? '').split(','))
        if (isPluggyItemId(part)) part.trim(),
    };
    return [
      for (final id in ids) PluggyItem(id: id, connectorName: connector),
    ];
  }

  String _clean(String raw) {
    final text = _clip(raw);
    if (text.isEmpty || text == '1') {
      return 'A conexão não foi concluída. Pode voltar ao Finn.';
    }
    if (text == 'ITEM_USER_ALREADY_EXISTS') {
      return 'Esse banco ainda existe no painel do Pluggy. '
          'Desligar no Finn não apaga o item lá. '
          'Use «Informar itens do painel» com o item id, '
          'ou no Connect escolha outro banco do Meu Pluggy.';
    }
    return text;
  }

  String _clip(String raw) {
    final text = raw.replaceAll(RegExp(r'[\u0000-\u001F]'), ' ').trim();
    return text.length > 180 ? text.substring(0, 180) : text;
  }

  String _html(String connectToken, String callback) {
    return '''
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <title>Conectar banco</title>
  <script src="https://cdn.pluggy.ai/pluggy-connect/v2.8.2/pluggy-connect.js"></script>
</head>
<body>
  <p>Abrindo o Pluggy Connect…</p>
  <script>
    const token = ${jsonEncode(connectToken)};
    const callback = ${jsonEncode(callback)};
    const finish = (item, extra) => {
      const id = item && item.id ? item.id : '';
      const connector = item && item.connector && item.connector.name
        ? item.connector.name
        : 'Conexão';
      let url = callback
        + '?id=' + encodeURIComponent(id)
        + '&name=' + encodeURIComponent(connector);
      if (extra) url += '&' + extra;
      window.location.href = url;
    };
    const widget = new PluggyConnect({
      connectToken: token,
      includeSandbox: false,
      onEvent: (payload) => {
        const item = payload && (payload.item || (payload.data && payload.data.item));
        if (item && item.id) window.__pluggyItem = item;
      },
      onSuccess: (data) => {
        finish(data && (data.item || data));
      },
      onError: (error) => {
        const data = error && error.data;
        const existing = (data && data.items) || (error && error.items) || [];
        const ids = Array.isArray(existing)
          ? existing.filter((value) => typeof value === 'string' || (value && value.id))
              .map((value) => typeof value === 'string' ? value : value.id)
          : [];
        if (ids.length) {
          const item = window.__pluggyItem || { id: ids[0], connector: { name: 'MeuPluggy' } };
          finish(item, 'ids=' + encodeURIComponent(ids.join(',')) + '&error=ITEM_USER_ALREADY_EXISTS');
          return;
        }
        const item = (data && data.item) || window.__pluggyItem;
        if (item && item.id) {
          finish(item);
          return;
        }
        const code = (error && error.codeDescription) || (data && data.codeDescription) || '';
        const message = code === 'ITEM_USER_ALREADY_EXISTS'
          ? 'ITEM_USER_ALREADY_EXISTS'
          : (error && error.message ? String(error.message) : '1');
        window.location.href = callback + '?error=' + encodeURIComponent(message);
      }
    });
    widget.init();
  </script>
</body>
</html>
''';
  }

  String _donePage(String message) {
    final safe = const HtmlEscape().convert(message);
    return '<!DOCTYPE html><html lang="pt-BR"><meta charset="utf-8"><title>Finn</title><p>$safe</p></html>';
  }
}
