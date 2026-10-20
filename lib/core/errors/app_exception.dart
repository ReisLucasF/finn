class AppException implements Exception {
  const AppException(this.message, {this.code = 'app'});

  final String message;
  final String code;

  @override
  String toString() => message;
}
