import 'dart:convert';

import 'package:crypto/crypto.dart';

String ofxFingerprint({
  required String accountId,
  required String? fitId,
  required int amountCents,
  required String dateIso,
  required String normalizedDescription,
}) {
  final payload = [
    accountId,
    fitId ?? '',
    amountCents.toString(),
    dateIso,
    normalizedDescription,
  ].join('|');
  return sha256.convert(utf8.encode(payload)).toString();
}
