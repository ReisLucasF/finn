import 'dart:convert';
import 'dart:typed_data';

import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/errors/ofx_parse_exception.dart';
import 'package:finan/domain/entities/parsed_ofx_transaction.dart';
import 'package:finan/domain/services/ofx_amount.dart';
import 'package:finan/domain/services/ofx_parser.dart';

class OfxStatementParser implements OfxParser {
  const OfxStatementParser();

  @override
  List<ParsedOfxTransaction> parseBytes(Uint8List bytes) {
    return parse(decodeOfxBytes(bytes));
  }

  List<ParsedOfxTransaction> parse(String content) {
    final source = content.replaceFirst('\uFEFF', '').trim();
    if (source.isEmpty || !_looksLikeOfx(source)) {
      throw const OfxParseException('O arquivo não parece um OFX válido.');
    }
    final blocks = _transactionBlocks(source);
    if (blocks.isEmpty) {
      throw const OfxParseException(
        'Nenhum lançamento encontrado no arquivo.',
      );
    }
    final parsed = <ParsedOfxTransaction>[];
    for (final block in blocks) {
      final item = _readTransaction(block);
      if (item != null) parsed.add(item);
    }
    if (parsed.isEmpty) {
      throw const OfxParseException(
        'Nenhum lançamento válido encontrado no arquivo.',
      );
    }
    return parsed;
  }

  bool _looksLikeOfx(String source) {
    final upper = source.toUpperCase();
    return upper.contains('<OFX>') ||
        upper.contains('OFXHEADER') ||
        upper.contains('<STMTTRN') ||
        upper.contains('<CCSTMTTRN');
  }

  List<String> _transactionBlocks(String source) {
    final closed = RegExp(
      r'<(STMTTRN|CCSTMTTRN)\b[^>]*>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(source);
    if (closed.isNotEmpty) {
      return [for (final match in closed) match.group(2)!];
    }
    final opens = RegExp(
      r'<(STMTTRN|CCSTMTTRN)\b[^>]*>',
      caseSensitive: false,
    ).allMatches(source).toList();
    final blocks = <String>[];
    for (var index = 0; index < opens.length; index++) {
      final start = opens[index].end;
      final end = index + 1 < opens.length
          ? opens[index + 1].start
          : source.length;
      var body = source.substring(start, end);
      final closer = body.toUpperCase().indexOf('</BANKTRANLIST');
      if (closer >= 0) body = body.substring(0, closer);
      blocks.add(body);
    }
    return blocks;
  }

  ParsedOfxTransaction? _readTransaction(String block) {
    final amountRaw = _tag(block, 'TRNAMT');
    final postedRaw = _tag(block, 'DTPOSTED');
    if (amountRaw == null || postedRaw == null) return null;
    final amount = tryParseOfxAmount(amountRaw);
    final date = _date(postedRaw);
    if (amount == null || amount.cents == 0 || date == null) return null;
    return ParsedOfxTransaction(
      fitId: _tag(block, 'FITID'),
      trnType: _tag(block, 'TRNTYPE'),
      postedAtRaw: postedRaw,
      postedDate: date,
      signedAmount: amount,
      name: _tag(block, 'NAME'),
      memo: _tag(block, 'MEMO'),
      checkNumber: _tag(block, 'CHECKNUM'),
      referenceNumber: _tag(block, 'REFNUM'),
    );
  }

  String? _tag(String block, String tag) {
    final match = RegExp(
      '<$tag>([^<\\r\\n]*)',
      caseSensitive: false,
    ).firstMatch(block);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  LocalDate? _date(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) return null;
    final year = int.tryParse(digits.substring(0, 4));
    final month = int.tryParse(digits.substring(4, 6));
    final day = int.tryParse(digits.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    final probe = DateTime.utc(year, month, day);
    if (probe.year != year || probe.month != month || probe.day != day) {
      return null;
    }
    return LocalDate(year, month, day);
  }
}

String decodeOfxBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}
