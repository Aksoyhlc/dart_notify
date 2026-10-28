import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/delivery/errors/delivery_error.dart';
import '../../core/delivery/errors/notify_delivery_exception.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/notification/notify_attachment.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/transport/multipart_file_part.dart';
import '../../shared/transport/multipart_http_transport.dart';
import '../../shared/utils/parse_retry_after.dart';
import 'config/telegram_config.dart';
import 'enums/telegram_parse_mode.dart';
import 'options/telegram_options.dart';
import 'targets/telegram_target.dart';

/// Telegram Bot API adapter. Call close() when finished.
final class TelegramProvider
    extends NotificationProvider<TelegramTarget, TelegramOptions> {
  TelegramProvider({
    required this.id,
    required this.config,
    http.Client? client,
  })  : _json = JsonHttpTransport(client: client),
        _multipart = MultipartHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final TelegramConfig config;
  final JsonHttpTransport _json;
  final MultipartHttpTransport _multipart;

  static const int _maxTextRunes = 4096;
  static const int _maxCaptionRunes = 1024;
  static const int _maxDocumentBytes = 50 * 1024 * 1024;

  @override
  bool get supportsSafeRetry => false;

  @override
  bool get supportsAttachments => true;

  void close() {
    _json.close();
    _multipart.close();
  }

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required TelegramTarget target,
    required DeliveryContext context,
    TelegramOptions? options,
  }) async {
    final settings = options ?? TelegramOptions();
    final text = _messageText(message, settings);
    if (message.attachments.isEmpty) {
      if (text.runes.length > _maxTextRunes) {
        return _limit('telegram_message_too_long',
            'Telegram text must not exceed 4096 characters.');
      }
      final response = await _sendJson(
        'sendMessage',
        _payload(target, settings, text: text),
      );
      return _readResponse(response);
    }
    if (message.attachments.length != 1) {
      return _limit('telegram_attachment_limit',
          'Telegram accepts exactly one attachment per send.');
    }
    final attachment = message.attachments.single;
    if (attachment.bytes.length > _maxDocumentBytes) {
      return _limit('telegram_attachment_limit',
          'Telegram attachments must not exceed 50 MB.');
    }
    if (text.runes.length > _maxCaptionRunes) {
      return _limit('telegram_attachment_limit',
          'Telegram captions must not exceed 1024 characters.');
    }
    final response = await _sendDocument(target, settings, text, attachment);
    return _readResponse(response);
  }

  Map<String, Object?> _payload(
    TelegramTarget target,
    TelegramOptions options, {
    String? text,
    String? caption,
  }) =>
      {
        'chat_id': target.chatId,
        if (text != null) 'text': text,
        if (caption != null) 'caption': caption,
        if (options.parseMode.wireValue != null)
          'parse_mode': options.parseMode.wireValue,
        if (options.silent) 'disable_notification': true,
        if (options.protectContent) 'protect_content': true,
        if (options.threadId != null) 'message_thread_id': options.threadId,
        if (options.replyToMessageId != null)
          'reply_to_message_id': options.replyToMessageId,
        if (options.disableLinkPreview)
          'link_preview_options': {'is_disabled': true},
      };

  Map<String, String> _formFields(
    TelegramTarget target,
    TelegramOptions options, {
    String? caption,
  }) =>
      {
        'chat_id': target.chatId,
        if (caption != null) 'caption': caption,
        if (options.parseMode.wireValue != null)
          'parse_mode': options.parseMode.wireValue!,
        if (options.silent) 'disable_notification': 'true',
        if (options.protectContent) 'protect_content': 'true',
        if (options.threadId != null)
          'message_thread_id': options.threadId.toString(),
        if (options.replyToMessageId != null)
          'reply_to_message_id': options.replyToMessageId.toString(),
      };

  Future<http.Response> _sendJson(
    String method,
    Map<String, Object?> payload,
  ) async {
    try {
      return await _json.send(
        endpoint: _methodEndpoint(method),
        payload: payload,
        timeout: config.timeout,
      );
    } on TimeoutException {
      throw _transportFailure('telegram_timeout', 'Telegram request timed out');
    } on http.ClientException {
      throw _transportFailure(
          'telegram_network_error', 'Telegram connection failed');
    } on SocketException {
      throw _transportFailure(
          'telegram_network_error', 'Telegram connection failed');
    }
  }

  Future<http.Response> _sendDocument(
    TelegramTarget target,
    TelegramOptions options,
    String text,
    NotifyAttachment attachment,
  ) async {
    try {
      return await _multipart.send(
        endpoint: _methodEndpoint('sendDocument'),
        fields: _formFields(
          target,
          options,
          caption: text.trim().isEmpty ? null : text,
        ),
        files: [
          MultipartFilePart(
            field: 'document',
            fileName: attachment.fileName,
            bytes: attachment.bytes,
            contentType: attachment.contentType,
          ),
        ],
        timeout: config.timeout,
      );
    } on TimeoutException {
      throw _transportFailure('telegram_timeout', 'Telegram request timed out');
    } on http.ClientException {
      throw _transportFailure(
          'telegram_network_error', 'Telegram connection failed');
    } on SocketException {
      throw _transportFailure(
          'telegram_network_error', 'Telegram connection failed');
    }
  }

  String _messageText(NotifyMessage message, TelegramOptions options) {
    final body =
        options.parseMode == TelegramParseMode.html && message.htmlBody != null
            ? message.htmlBody!
            : message.body.trim().isEmpty
                ? (message.htmlBody ?? '')
                : message.body;
    final title = message.title;
    if (title == null || title.isEmpty) return body;
    final formattedTitle = switch (options.parseMode) {
      TelegramParseMode.plain => title,
      TelegramParseMode.html => _escapeHtml(title),
      TelegramParseMode.markdownV2 => _escapeMarkdownV2(title),
    };
    return body.isEmpty ? formattedTitle : '$formattedTitle\n$body';
  }

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _escapeMarkdownV2(String value) => value.replaceAllMapped(
        RegExp(r'([_\*\[\]\(\)~`>#+\-=|{}.!\\])'),
        (match) => '\\${match[0]}',
      );

  NotifyDeliveryException _transportFailure(String code, String message) =>
      NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: code,
          message: '$message; acceptance is unknown.',
          retryable: true,
        ),
      );

  Uri _methodEndpoint(String method) {
    final base = config.endpoint.path.replaceAll(RegExp(r'/+$'), '');
    return config.endpoint.replace(path: '$base/bot${config.botToken}/$method');
  }

  ProviderResponse _readResponse(http.Response response) {
    Map<String, dynamic>? decoded;
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) decoded = body;
    } on FormatException {
      decoded = null;
    }
    final status = response.statusCode;
    if (status == 200 && decoded != null && decoded['ok'] == true) {
      final result = decoded['result'];
      final messageId = result is Map ? result['message_id'] : null;
      if ((messageId is int && messageId > 0) ||
          (messageId is String && messageId.trim().isNotEmpty)) {
        return ProviderResponse(
          status: DeliveryStatus.accepted,
          messageId: messageId.toString(),
        );
      }
    }
    final upstreamCode = decoded?['error_code'];
    final code = upstreamCode is int ? upstreamCode : null;
    if (code == 429) {
      final parameters = decoded?['parameters'];
      final seconds = parameters is Map ? parameters['retry_after'] : null;
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: seconds is int
            ? Duration(seconds: seconds)
            : parseRetryAfter(response.headers['retry-after']),
        error: DeliveryError(
          code: 'telegram_429',
          message: 'Telegram rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 500 || (code != null && code >= 500)) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'telegram_${code ?? 'http_$status'}',
          message: 'Telegram returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (code != null) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: 'telegram_$code',
          message: 'Telegram rejected the request (code $code).',
          httpStatus: status,
        ),
      );
    }
    if (status >= 200 && status < 300) {
      return const ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'telegram_invalid_response',
          message: 'Telegram returned an unexpected response.',
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'telegram_http_$status',
        message: 'Telegram returned HTTP $status.',
        httpStatus: status,
        retryable: status == 408,
      ),
    );
  }

  ProviderResponse _limit(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );
}
