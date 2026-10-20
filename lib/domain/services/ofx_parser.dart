import 'dart:typed_data';

import 'package:finan/domain/entities/parsed_ofx_transaction.dart';

abstract class OfxParser {
  List<ParsedOfxTransaction> parseBytes(Uint8List bytes);
}
