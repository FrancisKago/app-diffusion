class AppException implements Exception {
  AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'AppException: $message'
      : 'AppException: $message (cause: $cause)';
}
