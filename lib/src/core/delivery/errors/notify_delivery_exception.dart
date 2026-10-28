import '../../enums/delivery_status.dart';
import 'delivery_error.dart';

/// A provider may throw this for anticipated transport or API failures.
/// The safe message must never contain tokens, authorization headers or SMTP
/// credentials; DartNotify replaces unexpected errors with a generic result.
final class NotifyDeliveryException implements Exception {
  const NotifyDeliveryException({
    required this.status,
    required this.error,
    this.retryAfter,
  });

  final DeliveryStatus status;
  final DeliveryError error;
  final Duration? retryAfter;

  @override
  String toString() => 'NotifyDeliveryException(${error.code})';
}
