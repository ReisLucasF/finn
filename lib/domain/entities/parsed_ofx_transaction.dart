import 'package:finan/core/date/local_date.dart';
import 'package:finan/core/money/money.dart';

class ParsedOfxTransaction {
  const ParsedOfxTransaction({
    required this.postedAtRaw,
    required this.postedDate,
    required this.signedAmount,
    this.fitId,
    this.trnType,
    this.name,
    this.memo,
    this.checkNumber,
    this.referenceNumber,
  });

  final String? fitId;
  final String? trnType;
  final String postedAtRaw;
  final LocalDate postedDate;
  final Money signedAmount;
  final String? name;
  final String? memo;
  final String? checkNumber;
  final String? referenceNumber;

  Money get absoluteAmount => Money(signedAmount.cents.abs());
}
