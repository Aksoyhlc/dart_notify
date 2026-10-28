import '../delivery/errors/delivery_error.dart';
import '../enums/delivery_status.dart';

/// Outcome of one provider call, before the dispatcher decides whether to
/// retry.
final class ProviderResponse {
  /// Creates a response for a single provider attempt.
  const ProviderResponse({
    required this.status,
    this.messageId,
    this.error,
    this.retryAfter,
  });

  /// Outcome reported by the provider attempt.
  final DeliveryStatus status;

  /// Upstream message ID when the provider returned one.
  final String? messageId;

  /// Failure details for failed or unknown outcomes.
  final DeliveryError? error;

  /// Server-requested wait before retrying an ambiguous failure.
  final Duration? retryAfter;

  /// Shorthand for a fully accepted attempt.
  const ProviderResponse.accepted({String? messageId})
      : this(status: DeliveryStatus.accepted, messageId: messageId);
}
