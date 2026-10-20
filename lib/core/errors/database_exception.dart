import 'package:finan/core/errors/app_exception.dart';

class DatabaseException extends AppException {
  const DatabaseException(super.message) : super(code: 'database');
}
