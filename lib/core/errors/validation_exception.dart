import 'package:finan/core/errors/app_exception.dart';

class ValidationException extends AppException {
  const ValidationException(super.message) : super(code: 'validation');
}
