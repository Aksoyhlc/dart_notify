import '../enums/delivery_status.dart';
import 'errors/delivery_error.dart';

/// Outcome of one destination send, including retry count and elapsed time.
final class DeliveryResult {
  /// Creates a result for a single destination.
  const DeliveryResult({
    required this.destinationId,
    required this.providerId,
    required this.status,
    required this.attempts,
    required this.elapsed,
    this.messageId,
    this.error,
  });

  /// Registered destination ID, or the direct-send ID.
  final String destinationId;

  /// ID of the provider that handled the send.
  final String providerId;

  /// Final status after retries.
  final DeliveryStatus status;

  /// Provider calls made, starting at 1.
  final int attempts;

  /// Time spent delivering, excluding FIFO admission time.
  final Duration elapsed;

  /// Upstream message ID when the provider returned one.
  final String? messageId;

  /// Failure details for failed or unknown outcomes.
  final DeliveryError? error;

  /// True when the destination is fully accepted.
  bool get isFullyAccepted => status == DeliveryStatus.accepted;

  /// True for full or partial acceptance.
  bool get hasAcceptedDeliveries =>
      status == DeliveryStatus.accepted ||
      status == DeliveryStatus.partiallyAccepted;
}
