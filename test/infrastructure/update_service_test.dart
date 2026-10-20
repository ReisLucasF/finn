import 'package:finan/infrastructure/update/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareVersions', () {
    test('igualdade e prefixo v', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('v1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.0.0', 'V1.0.0'), 0);
    });

    test('ordem semântica', () {
      expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersions('1.1.0', '1.0.9'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('comprimentos diferentes', () {
      expect(compareVersions('1.0', '1.0.0'), 0);
      expect(compareVersions('1.0.1', '1.0'), greaterThan(0));
    });
  });
}
