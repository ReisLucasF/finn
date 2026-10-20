import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finan/core/errors/validation_exception.dart';

class PickedBackup {
  const PickedBackup({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// No Android, a extensão `zip` vira o MIME `application/zip`.
/// O seletor então mostra o `.financebackup`, mas não deixa tocá-lo.
Future<PickedBackup?> pickFinanceBackup({required String dialogTitle}) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: Platform.isAndroid
        ? const ['financebackup']
        : const ['financebackup', 'zip'],
    dialogTitle: dialogTitle,
  );
  if (files.isEmpty) return null;
  final file = files.first;
  final lower = file.name.toLowerCase();
  if (!lower.endsWith('.financebackup') && !lower.endsWith('.zip')) {
    throw const ValidationException('Escolha um arquivo .financebackup.');
  }
  return PickedBackup(name: file.name, bytes: await file.readAsBytes());
}
