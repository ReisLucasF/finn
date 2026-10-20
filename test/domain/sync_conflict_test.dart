import 'package:finan/domain/services/sync_conflict_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('só um lado mudou: sem conflito', () {
    expect(
      detectSyncConflict(
        baseVersion: 1,
        localVersion: 2,
        localFingerprint: '500',
        remoteVersion: 1,
        remoteFingerprint: '500',
      ),
      isNull,
    );
  });

  test('os dois lados mudaram o valor: conflito', () {
    final conflict = detectSyncConflict(
      baseVersion: 1,
      localVersion: 2,
      localFingerprint: '500',
      remoteVersion: 2,
      remoteFingerprint: '550',
    );
    expect(conflict, isNotNull);
    expect(conflict!.localVersion, 2);
    expect(conflict.remoteVersion, 2);
  });

  test('mesma alteração nos dois lados: sem conflito', () {
    expect(
      detectSyncConflict(
        baseVersion: 1,
        localVersion: 2,
        localFingerprint: '500',
        remoteVersion: 2,
        remoteFingerprint: '500',
      ),
      isNull,
    );
  });
}
