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
import '../../shared/email/email_address.dart';
import '../../shared/email/email_options.dart';
import '../../shared/email/email_target.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/utils/parse_retry_after.dart';
import '../../shared/utils/validate_https_endpoint.dart';
import 'config/resend_config.dart';

/// Resend email API adapter. Call close() when finished.
final class ResendProvider
    extends NotificationProvider<EmailTarget, EmailOptions> {
  ResendProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
    validateHttpsEndpoint(_endpoint);
  }

  @override
  final String id;
  final ResendConfig config;
  final JsonHttpTransport _transport;

  static const int _maxRecipients = 50;
  static const int _maxAttachmentBytes = 40 * 1024 * 1024;

  Uri get _endpoint =>
      config.endpoint ?? Uri.parse('https://api.resend.com/emails');

  @override
  bool get supportsSafeRetry => true;

  @override
  bool get supportsAttachments => true;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required EmailTarget target,
    required DeliveryContext context,
    EmailOptions? options,
  }) async {
    if (target.to.isEmpty) {
      return _failure('resend_recipient_required',
          'Resend requires at least one "to" recipient.');
    }
    if (target.to.length > _maxRecipients) {
      return _failure('resend_recipient_limit',
          'Resend accepts at most 50 "to" recipients.');
    }
    final attachments = _attachments(message.attachments);
    if (attachments == null) {
      return _failure('resend_attachment_limit',
          'Resend accepts at most 40 MB of base64 attachments.');
    }
    final payload = <String, Object?>{
      'from': _formatAddress(config.from),
      'to': [for (final address in target.to) _formatAddress(address)],
      if (target.cc.isNotEmpty)
        'cc': [for (final address in target.cc) _formatAddress(address)],
      if (target.bcc.isNotEmpty)
        'bcc': [for (final address in target.bcc) _formatAddress(address)],
      'subject': message.title ?? '(no subject)',
      if (message.body.trim().isNotEmpty) 'text': message.body,
      if (message.htmlBody != null) 'html': message.htmlBody,
      if (options != null && options.replyTo.isNotEmpty)
        'reply_to': [
          for (final address in options.replyTo) _formatAddress(address)
        ],
      if (attachments.isNotEmpty) 'attachments': attachments,
    };
    final http.Response response;
    try {
      response = await _transport.send(
        endpoint: _endpoint,
        payload: payload,
        timeout: config.timeout,
        headers: {
          'authorization': 'Bearer ${config.apiKey}',
          'idempotency-key': context.idempotencyKey,
        },
      );
    } on TimeoutException {
      throw _transportFailure('resend_timeout', 'Resend request timed out');
    } on http.ClientException {
      throw _transportFailure(
          'resend_network_error', 'Resend connection failed');
    } on SocketException {
      throw _transportFailure(
          'resend_network_error', 'Resend connection failed');
    }
    return _readResponse(response);
  }

  List<Map<String, Object?>>? _attachments(
    Iterable<NotifyAttachment> files,
  ) {
    final list = files.toList();
    var encodedLength = 0;
    for (final file in list) {
      encodedLength += 4 * ((file.bytes.length + 2) ~/ 3);
      if (encodedLength > _maxAttachmentBytes) return null;
    }
    return [
      for (final file in list)
        {
          'filename': file.fileName,
          'content': base64Encode(file.bytes),
          'content_type': file.contentType,
        },
    ];
  }

  String _formatAddress(EmailAddress address) {
    final name = address.name;
    if (name == null || name.isEmpty) return address.address;
    return '$name <${address.address}>';
  }

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
          code: 'resend_invalid_response',
          message: 'Resend returned an unexpected success response.',
        ),
      );
    }
    return _httpFailure(response);
  }

  ProviderResponse _httpFailure(http.Response response) {
    final status = response.statusCode;
    final name = _errorName(response.body);
    final retryAfter = parseRetryAfter(response.headers['retry-after']);
    if (status == 429) {
      final quota =
          name == 'daily_quota_exceeded' || name == 'monthly_quota_exceeded';
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: quota ? null : retryAfter,
        error: DeliveryError(
          code: quota ? 'resend_quota_exceeded' : 'resend_rate_limited',
          message: quota
              ? 'Resend sending quota exceeded.'
              : 'Resend rate limited the request.',
          httpStatus: status,
          retryable: !quota,
        ),
      );
    }
    if (status == 409) {
      final concurrent = name == 'concurrent_idempotent_requests';
      return ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: concurrent
              ? 'resend_idempotent_in_progress'
              : 'resend_idempotent_conflict',
          message: concurrent
              ? 'Resend is still processing an identical request.'
              : 'Resend rejected the idempotency key or payload.',
          httpStatus: status,
          retryable: concurrent,
        ),
      );
    }
    if (status >= 500) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'resend_http_$status',
          message: 'Resend returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    final (code, message) = switch (status) {
      400 => ('resend_validation', 'Resend rejected the request payload.'),
      401 => ('resend_auth', 'Resend API key was rejected.'),
      403 => (
          'resend_forbidden',
          'Resend denied the request; check domain and key permissions.'
        ),
      422 => ('resend_validation', 'Resend rejected the request fields.'),
      _ => ('resend_http_$status', 'Resend returned HTTP $status.'),
    };
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(code: code, message: message, httpStatus: status),
    );
  }

  String? _errorName(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final name = decoded['name'];
        if (name is String && name.isNotEmpty) return name;
      }
    } on FormatException {
      return null;
    }
    return null;
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

  ProviderResponse _failure(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );
}
