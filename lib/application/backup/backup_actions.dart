import 'dart:typed_data';

import 'package:finan/domain/repositories/backup_store.dart';

class CreateBackup {
  const CreateBackup({required BackupStore store}) : _store = store;

  final BackupStore _store;

  Future<Uint8List> call() => _store.exportZip();
}

class RestoreBackup {
  const RestoreBackup({required BackupStore store}) : _store = store;

  final BackupStore _store;

  Future<void> call(Uint8List bytes) => _store.importZip(bytes);
}
