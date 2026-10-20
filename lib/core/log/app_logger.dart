import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

class AppLogger {
  const AppLogger([this.name = 'finan']);

  final String name;

  void debug(String message) => _log(LogLevel.debug, message);

  void info(String message) => _log(LogLevel.info, message);

  void warning(String message) => _log(LogLevel.warning, message);

  void error(String message) => _log(LogLevel.error, message);

  void _log(LogLevel level, String message) {
    developer.log(message, name: name, level: _severity(level));
  }

  int _severity(LogLevel level) {
    return switch (level) {
      LogLevel.debug => 500,
      LogLevel.info => 800,
      LogLevel.warning => 900,
      LogLevel.error => 1000,
    };
  }
}
