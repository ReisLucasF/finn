import 'package:finan/core/date/local_date.dart';

class Clock {
  Clock({DateTime Function()? nowUtc, LocalDate Function()? today})
    : nowUtc = nowUtc ?? _defaultNowUtc,
      today = today ?? _defaultToday;

  final DateTime Function() nowUtc;
  final LocalDate Function() today;

  static DateTime _defaultNowUtc() => DateTime.now().toUtc();

  static LocalDate _defaultToday() => LocalDate.fromDateTime(DateTime.now());
}
