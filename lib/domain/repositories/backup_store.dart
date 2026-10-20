import 'dart:typed_data';

abstract class BackupStore {
  Future<Uint8List> exportZip();

  Future<void> importZip(Uint8List bytes);
}
