import 'package:finan/core/date/local_date.dart';

/// Calendário de dias úteis bancários com os feriados nacionais
/// (mesma base do calendário ANBIMA usado pelo CDI).
///
/// Feriados móveis derivam da Páscoa: Carnaval (segunda e terça),
/// Sexta-feira Santa e Corpus Christi.
class BusinessCalendar {
  const BusinessCalendar();

  bool isBusinessDay(LocalDate date) {
    final weekday = DateTime.utc(date.year, date.month, date.day).weekday;
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return false;
    }
    return !isHoliday(date);
  }

  bool isHoliday(LocalDate date) => holidays(date.year).contains(date);

  /// Feriados nacionais do ano.
  Set<LocalDate> holidays(int year) {
    final easter = easterSunday(year);
    return {
      LocalDate(year, 1, 1), // Confraternização Universal
      LocalDate(year, 4, 21), // Tiradentes
      LocalDate(year, 5, 1), // Dia do Trabalho
      LocalDate(year, 9, 7), // Independência
      LocalDate(year, 10, 12), // Nossa Senhora Aparecida
      LocalDate(year, 11, 2), // Finados
      LocalDate(year, 11, 15), // Proclamação da República
      if (year >= 2024)
        LocalDate(year, 11, 20), // Consciência Negra (Lei 14.759/2023)
      LocalDate(year, 12, 25), // Natal
      easter.addDays(-48), // Carnaval (segunda)
      easter.addDays(-47), // Carnaval (terça)
      easter.addDays(-2), // Sexta-feira Santa
      easter.addDays(60), // Corpus Christi
    };
  }

  /// Domingo de Páscoa (algoritmo de Meeus/Jones/Butcher, calendário gregoriano).
  static LocalDate easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = (h + l - 7 * m + 114) % 31 + 1;
    return LocalDate(year, month, day);
  }

  /// Dias úteis em [from, to): conta [from] e exclui [to].
  int businessDaysBetween(LocalDate from, LocalDate to) {
    var count = 0;
    for (var day = from; day < to; day = day.addDays(1)) {
      if (isBusinessDay(day)) count++;
    }
    return count;
  }

  /// Dias corridos entre as datas.
  static int calendarDays(LocalDate from, LocalDate to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}
