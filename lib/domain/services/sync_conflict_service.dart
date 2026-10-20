class SyncConflict {
  const SyncConflict({required this.localVersion, required this.remoteVersion});

  final int localVersion;
  final int remoteVersion;
}

/// Dois lados alteraram a mesma base com conteúdo diferente.
/// Não escolhe um vencedor.
SyncConflict? detectSyncConflict({
  required int baseVersion,
  required int localVersion,
  required String localFingerprint,
  required int remoteVersion,
  required String remoteFingerprint,
}) {
  final localChanged = localVersion > baseVersion;
  final remoteChanged = remoteVersion > baseVersion;
  if (!localChanged || !remoteChanged) return null;
  if (localFingerprint == remoteFingerprint) return null;
  return SyncConflict(localVersion: localVersion, remoteVersion: remoteVersion);
}
