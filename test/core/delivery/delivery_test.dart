import 'package:dart_notify/dart_notify.dart';
import 'package:test/test.dart';

void main() {
  DeliveryResult result(DeliveryStatus status) => DeliveryResult(
        destinationId: status.name,
        providerId: 'provider',
        status: status,
        attempts: 1,
        elapsed: Duration.zero,
      );

  test('individual results distinguish full and partial acceptance', () {
    for (final status in DeliveryStatus.values) {
      final delivery = result(status);
      expect(delivery.isFullyAccepted, status == DeliveryStatus.accepted);
      expect(
          delivery.hasAcceptedDeliveries,
          status == DeliveryStatus.accepted ||
              status == DeliveryStatus.partiallyAccepted);
    }
  });

  test('reports count rejection, uncertainty and skipping separately', () {
    final report = DispatchReport(DeliveryStatus.values.map(result));
    expect(report.isFullyAccepted, isFalse);
    expect(report.hasAcceptedDeliveries, isTrue);
    expect(report.isPartiallyAccepted, isTrue);
    expect(report.hasFailures, isTrue);
    expect(report.acceptedCount, 2);
    expect(report.fullyAcceptedCount, 1);
    expect(report.partialCount, 1);
    expect(report.failedCount, 1);
    expect(report.unknownCount, 1);
    expect(report.skippedCount, 1);
  });

  test('partial and skipped outcomes are not definite delivery failures', () {
    final report = DispatchReport([
      result(DeliveryStatus.partiallyAccepted),
      result(DeliveryStatus.skipped),
    ]);
    expect(report.hasFailures, isFalse);
    expect(report.isFullyAccepted, isFalse);
    expect(report.isPartiallyAccepted, isTrue);
  });

  test('empty reports do not imply acceptance', () {
    final report = DispatchReport([]);
    expect(report.isFullyAccepted, isFalse);
    expect(report.hasAcceptedDeliveries, isFalse);
    expect(report.isPartiallyAccepted, isFalse);
    expect(report.hasFailures, isFalse);
  });
}
