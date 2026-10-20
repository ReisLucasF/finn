import 'package:finan/infrastructure/pluggy/pluggy_http_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('401 do Pluggy explica se as chaves foram recusadas ou a aplicação está desligada', () {
    expect(
      pluggyStatusMessage(401, {'codeDescription': 'CLIENT_KEYS_UNAUTHORIZED'}),
      contains('client secret'),
    );
    expect(
      pluggyStatusMessage(401, {'codeDescription': 'CLIENT_DISABLED'}),
      contains('desativada'),
    );
    expect(pluggyStatusMessage(500, const {}), 'Não foi possível falar com o Pluggy (500).');
    expect(
      pluggyStatusMessage(400, {'codeDescription': 'ITEM_USER_ALREADY_EXISTS'}),
      contains('Informar itens do painel'),
    );
  });
}
