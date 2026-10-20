class AppConfig {
  const AppConfig._();

  static const String appName = 'Finn';
  static const String defaultCurrency = 'BRL';
  static const String defaultLocale = 'pt_BR';
  static const String defaultTimezone = 'America/Sao_Paulo';
  static const int defaultFinancialMonthStart = 1;
  static const String databaseFileName = 'finan.db';
  static const int databaseVersion = 16;
  static const int transactionPageSize = 40;
}
