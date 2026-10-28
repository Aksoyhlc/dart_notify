import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/delivery/errors/delivery_error.dart';
import '../../core/delivery/errors/notify_delivery_exception.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/utils/parse_retry_after.dart';
import 'config/webhook_config.dart';
import 'options/webhook_options.dart';
import 'targets/webhook_target.dart';

final class WebhookProvider
    extends NotificationProvider<WebhookTarget, WebhookOptions> {
  WebhookProvider({required this.id, required this.config, http.Client? client})
      : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final WebhookConfig config;
  final JsonHttpTransport _transport;

  @override
  bool get supportsSafeRetry => config.idempotencyHeader != null;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required WebhookTarget target,
    required DeliveryContext context,
    WebhookOptions? options,
  }) async {
    final payload = options?.payload ??
        config.payloadBuilder?.call(message) ??
        _defaultPayload(message);
    final headers = <String, String>{
      ...config.headers,
      ...?options?.headers,
      if (config.idempotencyHeader != null)
        config.idempotencyHeader!: context.idempotencyKey,
    };
    final http.Response response;
    try {
      response = await _transport.send(
          endpoint: target.endpoint,
          payload: payload,
          timeout: config.timeout,
          method: (options?.method ?? config.method).name.toUpperCase(),
          headers: headers);
    } on JsonUnsupportedObjectError {
      return const ProviderResponse(
          status: DeliveryStatus.failed,
          error: DeliveryError(
              code: 'webhook_invalid_payload',
              message: 'Webhook payload must be JSON-serializable.'));
    } on TimeoutException {
      throw const NotifyDeliveryException(
          status: DeliveryStatus.unknown,
          error: DeliveryError(
              code: 'webhook_timeout',
              message: 'Webhook request timed out; acceptance is unknown.',
              retryable: true));
    } on http.ClientException {
      throw const NotifyDeliveryException(
          status: DeliveryStatus.unknown,
          error: DeliveryError(
              code: 'webhook_network_error',
              message: 'Webhook connection failed; acceptance is unknown.',
              retryable: true));
    } on SocketException {
      throw const NotifyDeliveryException(
          status: DeliveryStatus.unknown,
          error: DeliveryError(
              code: 'webhook_network_error',
              message: 'Webhook connection failed; acceptance is unknown.',
              retryable: true));
    }
    return _readResponse(response);
  }

  Map<String, Object?> _defaultPayload(NotifyMessage message) => {
        if (message.title != null) 'title': message.title,
        'body': message.body,
        if (message.htmlBody != null) 'htmlBody': message.htmlBody,
        'priority': message.priority.name,
        if (message.data.isNotEmpty) 'data': message.data,
      };

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return const ProviderResponse.accepted();
    final uncertain = status == 408 || status >= 500;
    return ProviderResponse(
      status: uncertain ? DeliveryStatus.unknown : DeliveryStatus.failed,
      error: DeliveryError(
          code: 'webhook_http_$status',
          message: 'Webhook returned HTTP $status.',
          httpStatus: status,
          retryable: uncertain || status == 429),
      retryAfter: parseRetryAfter(response.headers['retry-after']),
    );
  }
}
