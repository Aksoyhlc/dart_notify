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
import 'config/gotify_config.dart';
import 'options/gotify_options.dart';
import 'targets/gotify_target.dart';

/// Gotify server adapter. Call close() when finished.
final class GotifyProvider
    extends NotificationProvider<GotifyTarget, GotifyOptions> {
  GotifyProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final GotifyConfig config;
  final JsonHttpTransport _transport;

  @override
  bool get supportsSafeRetry => false;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required GotifyTarget target,
    required DeliveryContext context,
    GotifyOptions? options,
  }) async {
    final settings = options ?? GotifyOptions();
    final payload = <String, Object?>{
      if (message.title != null) 'title': message.title,
      'message':
          message.body.trim().isEmpty ? (message.htmlBody ?? '') : message.body,
      'priority': settings.priority ?? _defaultPriority(message.priority),
      'extras': {
        'client::display': {
          'contentType': settings.markdown ? 'text/markdown' : 'text/plain',
        },
      },
    };
    final http.Response response;
    try {
      response = await _transport.send(
        endpoint: _endpoint(),
        payload: payload,
        timeout: config.timeout,
        headers: {
          'x-gotify-key': target.appToken,
          if (config.clientToken != null)
            'authorization': 'Bearer ${config.clientToken}',
        },
      );
    } on TimeoutException {
      throw _transportFailure('gotify_timeout', 'Gotify request timed out');
    } on http.ClientException {
      throw _transportFailure(
          'gotify_network_error', 'Gotify connection failed');
    } on SocketException {
      throw _transportFailure(
          'gotify_network_error', 'Gotify connection failed');
    }
    return _readResponse(response);
  }

  int _defaultPriority(NotifyPriority priority) => switch (priority) {
        NotifyPriority.low => 2,
        NotifyPriority.normal => 5,
        NotifyPriority.high => 8,
      };

  Uri _endpoint() {
    final base = config.baseUrl.path.replaceAll(RegExp(r'/+$'), '');
    return config.baseUrl.replace(path: '$base/message');
  }

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
        final id = body is Map ? body['id'] : null;
        if (id != null) {
          return ProviderResponse(
            status: DeliveryStatus.accepted,
            messageId: id.toString(),
          );
        }
      } on FormatException {
        // Malformed JSON; report unknown acceptance below.
      }
      return const ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'gotify_invalid_response',
          message: 'Gotify returned an unexpected success response.',
        ),
      );
    }
    if (status == 429) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
        error: DeliveryError(
          code: 'gotify_429',
          message: 'Gotify rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 500) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'gotify_http_$status',
          message: 'Gotify returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'gotify_http_$status',
        message: 'Gotify returned HTTP $status.',
        httpStatus: status,
        retryable: status == 408,
      ),
    );
  }
}
