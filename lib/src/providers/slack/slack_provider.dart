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
import 'config/slack_config.dart';
import 'options/slack_options.dart';
import 'targets/slack_target.dart';

/// Slack chat.postMessage adapter. Call close() when finished.
final class SlackProvider
    extends NotificationProvider<SlackTarget, SlackOptions> {
  SlackProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final SlackConfig config;
  final JsonHttpTransport _transport;

  static const int _maxBlocks = 50;
  static const int _maxTextRunes = 40000;

  @override
  bool get supportsSafeRetry => false;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required SlackTarget target,
    required DeliveryContext context,
    SlackOptions? options,
  }) async {
    final settings = options ?? SlackOptions();
    final body =
        message.body.trim().isEmpty ? (message.htmlBody ?? '') : message.body;
    final text = message.title == null || message.title!.isEmpty
        ? body
        : body.isEmpty
            ? message.title!
            : '${message.title}\n$body';
    if (settings.blocks.length > _maxBlocks ||
        !_isJsonSerializable(settings.blocks)) {
      return _failure('slack_invalid_blocks',
          'Slack blocks must be JSON-serializable and at most 50 entries.');
    }
    if (_containsOversizedBlockText(settings.blocks)) {
      return _failure('slack_invalid_blocks',
          'Slack block text must not exceed 3000 characters.');
    }
    if (settings.blocks.isNotEmpty && text.trim().isEmpty) {
      return _failure('slack_invalid_blocks',
          'Slack blocks require a nonblank text fallback.');
    }
    if (text.runes.length > _maxTextRunes) {
      return _failure('slack_text_too_long',
          'Slack text must not exceed 40000 characters.');
    }
    final payload = <String, Object?>{
      'channel': target.channel,
      'text': text,
      if (settings.blocks.isNotEmpty) 'blocks': settings.blocks,
      if (settings.threadTs != null) 'thread_ts': settings.threadTs,
      'mrkdwn': settings.mrkdwn,
      'unfurl_links': settings.unfurlLinks,
      'unfurl_media': settings.unfurlMedia,
      if (settings.username != null) 'username': settings.username,
      if (settings.iconEmoji != null) 'icon_emoji': settings.iconEmoji,
    };
    final http.Response response;
    try {
      response = await _transport.send(
        endpoint: config.endpoint,
        payload: payload,
        timeout: config.timeout,
        headers: {'authorization': 'Bearer ${config.token}'},
      );
    } on TimeoutException {
      throw _transportFailure('slack_timeout', 'Slack request timed out');
    } on http.ClientException {
      throw _transportFailure('slack_network_error', 'Slack connection failed');
    } on SocketException {
      throw _transportFailure('slack_network_error', 'Slack connection failed');
    }
    return _readResponse(response);
  }

  bool _isJsonSerializable(Object? value) {
    try {
      jsonEncode(value);
      return true;
    } on JsonUnsupportedObjectError {
      return false;
    }
  }

  bool _containsOversizedBlockText(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key == 'text' &&
            entry.value is String &&
            (entry.value as String).runes.length > 3000) {
          return true;
        }
        if (_containsOversizedBlockText(entry.value)) return true;
      }
    } else if (value is Iterable) {
      for (final item in value) {
        if (_containsOversizedBlockText(item)) return true;
      }
    }
    return false;
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
    if (status == 429) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
        error: DeliveryError(
          code: 'slack_429',
          message: 'Slack rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 500) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'slack_http_$status',
          message: 'Slack returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 200 && status < 300) {
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['ok'] == true) {
          final ts = body['ts'];
          return ProviderResponse(
            status: DeliveryStatus.accepted,
            messageId: ts is String ? ts : null,
          );
        }
        if (body is Map) {
          return ProviderResponse(
            status: DeliveryStatus.failed,
            error: DeliveryError(
              code: 'slack_${_normalizeError(body['error'])}',
              message: 'Slack rejected the request.',
              httpStatus: status,
            ),
          );
        }
      } on FormatException {
        // Malformed JSON; report the unexpected response below.
      }
      return const ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'slack_invalid_response',
          message: 'Slack returned an unexpected response.',
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'slack_http_$status',
        message: 'Slack returned HTTP $status.',
        httpStatus: status,
        retryable: status == 408,
      ),
    );
  }

  String _normalizeError(Object? error) {
    if (error is! String || error.trim().isEmpty) return 'unknown_error';
    final normalized =
        error.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    return normalized.length > 64 ? normalized.substring(0, 64) : normalized;
  }

  ProviderResponse _failure(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );
}
