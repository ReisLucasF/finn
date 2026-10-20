enum SyncState {
  local('local'),
  pendingSync('pending_sync'),
  synced('synced'),
  syncError('sync_error'),
  conflict('conflict');

  const SyncState(this.value);
  final String value;
}
