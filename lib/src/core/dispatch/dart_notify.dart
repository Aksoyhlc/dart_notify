import 'dart:async';
import 'dart:math';

import '../../shared/utils/uuid.dart';
import '../delivery/delivery_context.dart';
import '../delivery/delivery_result.dart';
import '../delivery/diagnostics/delivery_diagnostic.dart';
import '../delivery/errors/delivery_error.dart';
import '../delivery/errors/notify_delivery_exception.dart';
import '../delivery/retry/retry_policy.dart';
import '../enums/delivery_status.dart';
import '../notification/notification_options.dart';
import '../notification/notification_target.dart';
import '../notification/notify_message.dart';
import '../provider/notification_provider.dart';
import '../provider/provider_response.dart';
import '../routing/delivery_destination.dart';
import '../routing/provider_destination.dart';
import '../typedefs/delivery_diagnostic_handler.dart';
import '../utils/delivery_limiter.dart';
import 'dispatch_report.dart';

/// Routes notifications to destinations and caps concurrent sends per instance.
final class DartNotify {
  DartNotify({
    required Iterable<DeliveryDestination> destinations,
    Map<String, List<String>> groups = const {},
    RetryPolicy? retryPolicy,
    this.maxConcurrent = 4,
    this.onUnexpectedError,
    Future<void> Function(Duration)? wait,
  })  : retryPolicy = retryPolicy ?? RetryPolicy(),
        _wait = wait ?? _defaultWait,
        _limiter = DeliveryLimiter(maxConcurrent) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent');
    }
    for (final destination in destinations) {
      if (destination.id.trim().isEmpty ||
          destination.providerId.trim().isEmpty) {
        throw ArgumentError('Destination and provider IDs must not be empty.');
      }
      if (_destinations.containsKey(destination.id)) {
        throw ArgumentError('Duplicate destination ID: ${destination.id}');
      }
      _destinations[destination.id] = destination;
    }
    for (final entry in groups.entries) {
      if (entry.key.trim().isEmpty) {
        throw ArgumentError('Group name must not be empty.');
      }
      for (final id in entry.value) {
        if (!_destinations.containsKey(id)) {
          throw ArgumentError(
              'Unknown destination "$id" in group "${entry.key}".');
        }
      }
      _groups[entry.key] = List.unmodifiable(entry.value);
    }
  }

  final RetryPolicy retryPolicy;

  /// Includes direct sends, concurrent batches, retries and backoff waits.
  final int maxConcurrent;

  /// Opt-in access to raw failures. The handler must stay synchronous and
  /// redact secrets before logging.
  final DeliveryDiagnosticHandler? onUnexpectedError;
  final Future<void> Function(Duration) _wait;
  final DeliveryLimiter _limiter;
  final Map<String, DeliveryDestination> _destinations = {};
  final Map<String, List<String>> _groups = {};

  static Future<void> _defaultWait(Duration delay) =>
      Future<void>.delayed(delay);

  /// All selected IDs and option overrides are validated before dispatch starts.
  /// Each override replaces the destination's default options for this send.
  Future<DispatchReport> send(
    NotifyMessage message, {
    Iterable<String> to = const [],
    Iterable<String> groups = const [],
    Map<String, NotificationOptions> options = const {},
  }) async {
    final ids = <String>{};
    for (final id in to) {
      if (!_destinations.containsKey(id)) {
        throw ArgumentError('Unknown destination: $id');
      }
      ids.add(id);
    }
    for (final group in groups) {
      final members = _groups[group];
      if (members == null) throw ArgumentError('Unknown group: $group');
      ids.addAll(members);
    }
    if (ids.isEmpty) {
      throw ArgumentError(
          'Select at least one destination using to or groups.');
    }
    final overrides = Map<String, NotificationOptions>.of(options);
    for (final entry in overrides.entries) {
      if (!ids.contains(entry.key)) {
        throw ArgumentError(
            'Options require a selected destination: ${entry.key}');
      }
      _destinations[entry.key]!.validateOptions(entry.value);
    }

    final destinations = [for (final id in ids) _destinations[id]!];
    final results = List<DeliveryResult?>.filled(destinations.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < destinations.length) {
        final index = next++;
        final destination = destinations[index];
        results[index] = await _deliver(
          destination,
          message,
          options: overrides[destination.id],
        );
      }
    }

    await Future.wait([
      for (var i = 0; i < min(maxConcurrent, destinations.length); i++)
        worker(),
    ]);
    return DispatchReport(results.cast<DeliveryResult>());
  }

  /// Sends to a dynamic recipient through the same concurrency limit and retry
  /// policy.
  Future<DeliveryResult>
      sendDirect<T extends NotificationTarget, O extends NotificationOptions>(
    NotifyMessage message, {
    required NotificationProvider<T, O> provider,
    required T target,
    O? options,
    String destinationId = 'direct',
  }) async =>
          _deliver(
            ProviderDestination<T, O>(
              id: destinationId,
              provider: provider,
              target: target,
              options: options,
            ),
            message,
          );

  Future<DeliveryResult> _deliver(
    DeliveryDestination destination,
    NotifyMessage message, {
    NotificationOptions? options,
  }) async {
    if (message.attachments.isNotEmpty && !destination.supportsAttachments) {
      return DeliveryResult(
        destinationId: destination.id,
        providerId: destination.providerId,
        status: DeliveryStatus.failed,
        attempts: 1,
        elapsed: Duration.zero,
        error: DeliveryError(
          code: 'attachment_unsupported',
          message:
              'Provider "${destination.providerId}" does not support attachments.',
        ),
      );
    }
    return _limiter.run(() async {
      final stopwatch = Stopwatch()..start();
      final idempotencyKey = generateUuidV4();
      var attempts = 0;
      while (true) {
        attempts++;
        final response = await _attempt(
          destination,
          message,
          DeliveryContext(idempotencyKey: idempotencyKey, attempt: attempts),
          options,
        );
        final canRetry = (response.status == DeliveryStatus.failed ||
                response.status == DeliveryStatus.unknown) &&
            response.error?.retryable == true &&
            destination.supportsSafeRetry &&
            attempts < retryPolicy.maxAttempts;
        if (canRetry) {
          await _wait(
              retryPolicy.delayFor(attempts, retryAfter: response.retryAfter));
          continue;
        }
        stopwatch.stop();
        return DeliveryResult(
          destinationId: destination.id,
          providerId: destination.providerId,
          status: response.status,
          attempts: attempts,
          elapsed: stopwatch.elapsed,
          messageId: response.messageId,
          error: response.error,
        );
      }
    });
  }

  Future<ProviderResponse> _attempt(
    DeliveryDestination destination,
    NotifyMessage message,
    DeliveryContext context,
    NotificationOptions? options,
  ) async {
    try {
      return await destination.deliver(message, context, options: options);
    } on NotifyDeliveryException catch (error) {
      return ProviderResponse(
        status: error.status,
        error: error.error,
        retryAfter: error.retryAfter,
      );
    } catch (error, stackTrace) {
      try {
        onUnexpectedError?.call(DeliveryDiagnostic(
          destinationId: destination.id,
          providerId: destination.providerId,
          attempt: context.attempt,
          error: error,
          stackTrace: stackTrace,
        ));
      } catch (_) {
        // Diagnostics must not change a delivery outcome or block other sends.
      }
      return const ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'unexpected_error',
          message: 'Unexpected provider error; outcome is unknown.',
        ),
      );
    }
  }
}
