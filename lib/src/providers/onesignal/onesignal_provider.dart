import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/delivery/errors/delivery_error.dart';
import '../../core/delivery/errors/notify_delivery_exception.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/enums/notify_priority.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/utils/parse_retry_after.dart';
import 'config/onesignal_config.dart';
import 'options/onesignal_options.dart';
import 'targets/onesignal_target.dart';

/// OneSignal Create Push Notification API client. Call close() when finished.
/// Provider credentials belong on a trusted server, never in a client binary.
final class OneSignalProvider
    extends NotificationProvider<OneSignalTarget, OneSignalOptions> {
  OneSignalProvider({
    required this.id,
    required this.config,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID required');
  }

  @override
  final String id;
  final OneSignalConfig config;
  final http.Client _client;
  final bool _ownsClient;

  @override
  bool get supportsSafeRetry => true;

  /// Only closes internally allocated http clients.
  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required OneSignalTarget target,
    required DeliveryContext context,
    OneSignalOptions? options,
  }) async {
    final payload = _createPayload(message, target, context, options);
    final response = await _post(payload);
    return _readResponse(response);
  }

  Map<String, Object?> _createPayload(
    NotifyMessage message,
    OneSignalTarget target,
    DeliveryContext context,
    OneSignalOptions? options,
  ) {
    if (message.body.trim().isEmpty) {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: 'invalid_push_body',
          message: 'OneSignal push requires a non-empty text body.',
        ),
      );
    }
    final language = options?.language ?? 'en';
    final contents = <String, String>{
      'en': message.body,
      language: message.body,
      ...?options?.localizedBodies,
    };
    final headings = <String, String>{
      if (message.title != null) 'en': message.title!,
      if (message.title != null) language: message.title!,
      ...?options?.localizedTitles,
    };
    return <String, Object?>{
      'app_id': config.appId,
      'contents': contents,
      if (headings.isNotEmpty) 'headings': headings,
      ...target.toJson(),
      if (message.data.isNotEmpty) 'data': message.data,
      'priority': switch (message.priority) {
        NotifyPriority.low => 5,
        NotifyPriority.normal => 5,
        NotifyPriority.high => 10,
      },
      'idempotency_key': context.idempotencyKey,
      ...?options?.toJson(),
    };
  }

  Future<http.Response> _post(Map<String, Object?> payload) async {
    try {
      return await _client
          .post(
            config.endpoint,
            headers: {
              'Authorization': 'Key ${config.apiKey}',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(config.timeout);
    } on TimeoutException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'onesignal_timeout',
          message: 'OneSignal request timed out; delivery outcome unknown.',
          retryable: true,
        ),
      );
    } on http.ClientException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'onesignal_network_error',
          message: 'OneSignal connection failed; delivery outcome unknown.',
          retryable: true,
        ),
      );
    } on SocketException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'onesignal_network_error',
          message: 'OneSignal connection failed; delivery outcome unknown.',
          retryable: true,
        ),
      );
    }
  }

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      final temporary = status == 408 || status == 429 || status >= 500;
      throw NotifyDeliveryException(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: 'onesignal_http_$status',
          message: 'OneSignal returned HTTP $status.',
          httpStatus: status,
          retryable: temporary,
        ),
        retryAfter: parseRetryAfter(response.headers['retry-after']),
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'onesignal_invalid_response',
          message: 'OneSignal success response is not valid JSON.',
        ),
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'onesignal_invalid_response',
          message: 'OneSignal response has an unexpected shape.',
        ),
      );
    }
    final notificationId = decoded['id'];
    final errors = decoded['errors'];
    if (!decoded.containsKey('id') ||
        (notificationId != null && notificationId is! String) ||
        (errors != null && errors is! List && errors is! Map)) {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'onesignal_invalid_response',
          message: 'OneSignal response has an unexpected shape.',
        ),
      );
    }
    final hasErrors = errors != null &&
        (errors is! List || errors.isNotEmpty) &&
        (errors is! Map || errors.isNotEmpty);

    if (notificationId is! String || notificationId.isEmpty) {
      return const ProviderResponse(
        status: DeliveryStatus.skipped,
        error: DeliveryError(
          code: 'onesignal_no_recipients',
          message:
              'OneSignal did not create a notification (no eligible targets).',
        ),
      );
    }
    return ProviderResponse(
      status: hasErrors
          ? DeliveryStatus.partiallyAccepted
          : DeliveryStatus.accepted,
      messageId: notificationId,
      error: hasErrors
          ? const DeliveryError(
              code: 'onesignal_partial_rejection',
              message:
                  'OneSignal accepted a notification but rejected some targets.',
            )
          : null,
    );
  }
}
