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
import 'config/discord_config.dart';
import 'options/discord_options.dart';
import 'targets/discord_target.dart';

/// Discord channel webhook adapter. Call close() when finished.
final class DiscordProvider
    extends NotificationProvider<DiscordTarget, DiscordOptions> {
  DiscordProvider({
    required this.id,
    DiscordConfig? config,
    http.Client? client,
  })  : config = config ?? DiscordConfig(),
        _json = JsonHttpTransport(client: client),
        _multipart = MultipartHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final DiscordConfig config;
  final JsonHttpTransport _json;
  final MultipartHttpTransport _multipart;

  static const int _maxContentRunes = 2000;
  static const int _maxEmbeds = 10;
  static const int _maxEmbedRunes = 6000;
  static const int _maxFiles = 10;
  static const int _maxFileBytes = 25 * 1024 * 1024;

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
    required DiscordTarget target,
    required DeliveryContext context,
    DiscordOptions? options,
  }) async {
    final settings = options ?? DiscordOptions();
    final content = _content(message);
    if (content.runes.length > _maxContentRunes) {
      return _failure('discord_content_too_long',
          'Discord content must not exceed 2000 characters.');
    }
    if (settings.embeds.length > _maxEmbeds) {
      return _failure('discord_embed_limit',
          'Discord accepts at most 10 embeds per message.');
    }
    final embedCharacters = settings.embeds
        .fold<int>(0, (sum, embed) => sum + embed.characterCount);
    if (embedCharacters > _maxEmbedRunes) {
      return _failure('discord_embed_limit',
          'Discord embeds must not exceed 6000 characters in total.');
    }
    if (content.trim().isEmpty && settings.embeds.isEmpty) {
      return _failure('discord_empty_content',
          'Discord requires message text or at least one embed.');
    }
    if (message.attachments.length > _maxFiles ||
        message.attachments.any((file) => file.bytes.length > _maxFileBytes)) {
      return _failure('discord_attachment_limit',
          'Discord accepts at most 10 files of 25 MB each.');
    }
    final payload = _payload(message, settings, content);
    final endpoint = _endpoint(target);
    final http.Response response;
    try {
      response = message.attachments.isEmpty
          ? await _json.send(
              endpoint: endpoint,
              payload: payload,
              timeout: config.timeout,
            )
          : await _multipart.send(
              endpoint: endpoint,
              fields: {'payload_json': jsonEncode(payload)},
              files: _files(message.attachments),
              timeout: config.timeout,
            );
    } on TimeoutException {
      throw _transportFailure('discord_timeout', 'Discord request timed out');
    } on http.ClientException {
      throw _transportFailure(
          'discord_network_error', 'Discord connection failed');
    } on SocketException {
      throw _transportFailure(
          'discord_network_error', 'Discord connection failed');
    }
    return _readResponse(response);
  }

  Map<String, Object?> _payload(
    NotifyMessage message,
    DiscordOptions options,
    String content,
  ) =>
      {
        'content': content,
        if (config.username != null) 'username': config.username,
        if (config.avatarUrl != null) 'avatar_url': config.avatarUrl.toString(),
        'allowed_mentions': {'parse': options.allowedMentions},
        if (options.tts) 'tts': true,
        if (options.suppressEmbeds) 'flags': 4,
        if (options.embeds.isNotEmpty)
          'embeds': [for (final embed in options.embeds) embed.toJson()],
      };

  String _content(NotifyMessage message) {
    final body =
        message.body.trim().isEmpty ? (message.htmlBody ?? '') : message.body;
    final title = message.title;
    if (title == null || title.isEmpty) return body;
    return body.isEmpty ? title : '$title\n$body';
  }

  Iterable<MultipartFilePart> _files(Iterable<NotifyAttachment> attachments) =>
      [
        for (final (index, file) in attachments.indexed)
          MultipartFilePart(
            field: 'files[$index]',
            fileName: file.fileName,
            bytes: file.bytes,
            contentType: file.contentType,
          ),
      ];

  Uri _endpoint(DiscordTarget target) => target.webhookUrl.replace(
        queryParameters: {
          ...target.webhookUrl.queryParameters,
          'wait': 'true',
          if (config.threadId != null) 'thread_id': config.threadId!,
        },
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

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    if (status == 204) {
      return const ProviderResponse(status: DeliveryStatus.accepted);
    }
    if (status == 200) {
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
          code: 'discord_invalid_response',
          message: 'Discord returned an unexpected success response.',
        ),
      );
    }
    if (status == 429) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: _retryAfter(response),
        error: DeliveryError(
          code: 'discord_429',
          message: 'Discord rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 500) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'discord_http_$status',
          message: 'Discord returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'discord_http_$status',
        message: 'Discord returned HTTP $status.',
        httpStatus: status,
        retryable: status == 408,
      ),
    );
  }

  Duration? _retryAfter(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final seconds = body['retry_after'];
        if (seconds is num) {
          return Duration(milliseconds: (seconds * 1000).ceil());
        }
      }
    } on FormatException {
      // Fall back to the standard header.
    }
    return parseRetryAfter(response.headers['retry-after']);
  }

  ProviderResponse _failure(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );
}
