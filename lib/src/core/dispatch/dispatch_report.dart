import '../delivery/delivery_result.dart';
import '../enums/delivery_status.dart';

/// Aggregate result for one send call, in destination selection order.
final class DispatchReport {
  /// Wraps the per-destination results in an unmodifiable list.
  DispatchReport(Iterable<DeliveryResult> results)
      : results = List.unmodifiable(results);

  /// One result per selected destination, in selection order.
  final List<DeliveryResult> results;

  /// True only when every destination is fully accepted.
  bool get isFullyAccepted =>
      results.isNotEmpty &&
      results.every((r) => r.status == DeliveryStatus.accepted);

  /// True when at least one destination has full or partial acceptance.
  bool get hasAcceptedDeliveries => results.any((r) => r.hasAcceptedDeliveries);

  /// True when at least one destination failed or has unknown acceptance.
  bool get hasFailures => failedCount > 0 || unknownCount > 0;

  /// True when some destination was accepted but the report is not fully
  /// accepted.
  bool get isPartiallyAccepted => hasAcceptedDeliveries && !isFullyAccepted;

  /// Destinations with full or partial acceptance, not the number of recipients.
  int get acceptedCount => results.where((r) => r.hasAcceptedDeliveries).length;

  /// Destinations whose result is fully accepted.
  int get fullyAcceptedCount => results.where((r) => r.isFullyAccepted).length;

  /// Destinations with partial acceptance.
  int get partialCount =>
      results.where((r) => r.status == DeliveryStatus.partiallyAccepted).length;

  /// Destinations rejected by their provider.
  int get failedCount =>
      results.where((r) => r.status == DeliveryStatus.failed).length;

  /// Destinations whose acceptance could not be determined.
  int get unknownCount =>
      results.where((r) => r.status == DeliveryStatus.unknown).length;

  /// Destinations the provider skipped without creating a notification.
  int get skippedCount =>
      results.where((r) => r.status == DeliveryStatus.skipped).length;
}
