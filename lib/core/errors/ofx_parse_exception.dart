import 'package:finan/core/errors/app_exception.dart';

class OfxParseException extends AppException {
  const OfxParseException(super.message) : super(code: 'ofx_parse');
}
