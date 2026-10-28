final class DeliveryError {
  const DeliveryError({
    required this.code,
    required this.message,
    this.httpStatus,
    this.retryable = false,
  });

  final String code;
  final String message;
  final int? httpStatus;
  final bool retryable;

  @override
  String toString() => '$code: $message';
}
