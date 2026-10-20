import 'package:finan/core/errors/database_exception.dart';
import 'package:finan/core/log/app_logger.dart';

const _logger = AppLogger('sqlite');

Future<T> guardSqlite<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on DatabaseException {
    rethrow;
  } catch (error) {
    _logger.error('Falha de banco (${error.runtimeType})');
    throw const DatabaseException('Não foi possível acessar os dados locais.');
  }
}
