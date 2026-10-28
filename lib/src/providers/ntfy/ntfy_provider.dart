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
import '../../shared/transport/json_http_transport.dart';
import '../../shared/utils/parse_retry_after.dart';
import 'config/ntfy_config.dart';
import 'enums/ntfy_priority.dart';
import 'options/ntfy_options.dart';
import 'targets/ntfy_target.dart';
import 'utils/format_ntfy_delay.dart';

/// ntfy JSON publish adapter. Call close() when finished.
final class NtfyProvider extends NotificationProvider<NtfyTarget, NtfyOptions> {
  NtfyProvider({
    required this.id,
    NtfyConfig? config,
    http.Client? client,
  })  : config = config ?? NtfyConfig(),
        _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final NtfyConfig config;
  final JsonHttpTransport _transport;

  static const int _maxTitleRunes = 256;
  static const int _maxMessageBytes = 4096;

  @override
  bool get supportsSafeRetry => false;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required NtfyTarget target,
    required DeliveryContext context,
    NtfyOptions? options,
  }) async {
    final settings = options ?? NtfyOptions();
    if (message.title != null && message.title!.runes.length > _maxTitleRunes) {
      return _failure(
          'ntfy_title_too_long', 'ntfy titles must not exceed 256 characters.');
    }
    final text = (settings.markdown || message.body.trim().isEmpty) &&
            message.htmlBody != null
        ? message.htmlBody!
        : message.body;
    if (utf8.encode(text).length > _maxMessageBytes) {
      return _failure('ntfy_message_too_large',
          'ntfy messages must not exceed 4096 bytes.');
    }
    final payload = <String, Object?>{
      'topic': target.topic,
      'message': text,
      if (message.title != null) 'title': message.title,
      'priority':
          (settings.priority ?? _defaultPriority(message.priority)).value,
      if (settings.tags.isNotEmpty) 'tags': settings.tags,
      if (settings.click != null) 'click': settings.click.toString(),
      if (settings.icon != null) 'icon': settings.icon.toString(),
      if (settings.markdown) 'markdown': true,
      if (settings.delay != null) 'delay': formatNtfyDelay(settings.delay!),
      if (settings.attachUrl != null) 'attach': settings.attachUrl.toString(),
    };
    final http.Response response;
    try {
      response = await _transport.send(
        endpoint: config.baseUrl,
        payload: payload,
        timeout: config.timeout,
        headers: {
          if (config.authToken != null)
            'authorization': 'Bearer ${config.authToken}',
        },
      );
    } on TimeoutException {
      throw _transportFailure('ntfy_timeout', 'ntfy request timed out');
    } on http.ClientException {
      throw _transportFailure('ntfy_network_error', 'ntfy connection failed');
    } on SocketException {
      throw _transportFailure('ntfy_network_error', 'ntfy connection failed');
    }
    return _readResponse(response);
  }

  NtfyPriority _defaultPriority(NotifyPriority priority) => switch (priority) {
        NotifyPriority.low => NtfyPriority.low,
        NotifyPriority.normal => NtfyPriority.defaultPriority,
        NotifyPriority.high => NtfyPriority.high,
      };

  NotifyDeliveryException _transportFailure(String code, String message) =>
      NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: code,
          message: '$message; acceptance is unknown.',
          retryable: true,
        ),
      );

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      try {
        final body = jsonDecode(response.body);
        final messageId = body is Map ? body['id'] : null;
        if (messageId is String && messageId.isNotEmpty) {
          return ProviderResponse(
            status: DeliveryStatus.accepted,
            messageId: messageId,
          );
        }
      } on FormatException {
        // Malformed JSON; report unknown acceptance below.
      }
      return const ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'ntfy_invalid_response',
          message: 'ntfy returned an unexpected success response.',
        ),
      );
    }
    if (status == 429) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
        error: DeliveryError(
          code: 'ntfy_429',
          message: 'ntfy rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 500) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'ntfy_http_$status',
          message: 'ntfy returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'ntfy_http_$status',
        message: 'ntfy returned HTTP $status.',
        httpStatus: status,
        retryable: status == 408,
      ),
    );
  }

  ProviderResponse _failure(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );
}
