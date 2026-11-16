import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/email/email_address.dart';
import '../../shared/email/email_options.dart';
import '../../shared/email/email_target.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/transport/provider_http.dart';
import 'config/postmark_config.dart';

/// Postmark single-email API adapter. Call close() when finished.
final class PostmarkProvider
    extends NotificationProvider<EmailTarget, EmailOptions> {
  PostmarkProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final PostmarkConfig config;
  final JsonHttpTransport _transport;

  static final _endpoint = Uri.https('api.postmarkapp.com', '/email');
  static const _maxBodyBytes = 5 * 1024 * 1024;
  static const _maxMessageBytes = 10 * 1024 * 1024;
  static const _blockedExtensions = {
    'vbs',
    'exe',
    'bin',
    'bat',
    'chm',
    'com',
    'cpl',
    'crt',
    'hlp',
    'hta',
    'inf',
    'ins',
    'isp',
    'jse',
    'lnk',
    'mdb',
    'pcd',
    'pif',
    'reg',
    'scr',
    'sct',
    'shs',
    'vbe',
    'vba',
    'wsf',
    'wsh',
    'wsl',
    'msc',
    'msi',
    'msp',
    'mst',
  };

  @override
  bool get supportsSafeRetry => false;

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
      return providerFailure('postmark_recipient_required',
          'Postmark requires at least one To recipient.');
    }
    if (target.to.length + target.cc.length + target.bcc.length > 50) {
      return providerFailure('postmark_recipient_limit',
          'Postmark accepts at most 50 To, Cc and Bcc recipients combined.');
    }
    final replyTo = options?.replyTo ?? const <EmailAddress>[];
    final addresses = [
      config.from,
      ...target.to,
      ...target.cc,
      ...target.bcc,
      ...replyTo
    ];
    if (addresses.any((address) => !_validAddress(address))) {
      return providerFailure('postmark_invalid_address',
          'Each Postmark address must contain a single email address.');
    }
    final from = _formatAddress(config.from);
    final subject = message.title;
    if (from.runes.length > 255 || (subject?.runes.length ?? 0) > 2000) {
      return providerFailure('postmark_header_limit',
          'The Postmark sender or subject exceeds the API limit.');
    }
    final text = message.body.trim().isEmpty ? null : message.body;
    final html = (message.htmlBody?.trim().isNotEmpty ?? false)
        ? message.htmlBody
        : null;
    final textBytes = text == null ? 0 : utf8.encode(text).length;
    final htmlBytes = html == null ? 0 : utf8.encode(html).length;
    if (textBytes > _maxBodyBytes || htmlBytes > _maxBodyBytes) {
      return providerFailure('postmark_body_limit',
          'Postmark accepts at most 5 MB per text or HTML body.');
    }
    var messageBytes = textBytes + htmlBytes;
    for (final file in message.attachments) {
      final dot = file.fileName.lastIndexOf('.');
      if (dot >= 0 &&
          _blockedExtensions.contains(
              file.fileName.substring(dot + 1).trim().toLowerCase())) {
        return providerFailure('postmark_attachment_type',
            'Postmark blocks this attachment file extension.');
      }
      messageBytes += 4 * ((file.bytes.length + 2) ~/ 3);
    }
    if (messageBytes > _maxMessageBytes) {
      return _messageSizeFailure();
    }
    final payload = <String, Object?>{
      'From': from,
      'To': _addressList(target.to),
      if (target.cc.isNotEmpty) 'Cc': _addressList(target.cc),
      if (target.bcc.isNotEmpty) 'Bcc': _addressList(target.bcc),
      if (replyTo.isNotEmpty) 'ReplyTo': _addressList(replyTo),
      if (subject != null) 'Subject': subject,
      if (text != null) 'TextBody': text,
      if (html != null) 'HtmlBody': html,
      if (config.messageStream != null) 'MessageStream': config.messageStream,
      if (message.attachments.isNotEmpty)
        'Attachments': [
          for (final file in message.attachments)
            {
              'Name': file.fileName,
              'Content': base64Encode(file.bytes),
              'ContentType': file.contentType,
            },
        ],
    };
    if (utf8.encode(jsonEncode(payload)).length > _maxMessageBytes) {
      return _messageSizeFailure();
    }
    final response = await sendProviderRequest(
      'postmark',
      () => _transport.send(
        endpoint: _endpoint,
        payload: payload,
        timeout: config.timeout,
        headers: {'X-Postmark-Server-Token': config.serverToken},
      ),
    );
    return _readResponse(response);
  }

  static final _emailPattern = RegExp(r'^[^@\s,<>";\\]+@[^@\s,<>";\\]+$');
  static final _controlCharacter = RegExp(r'[\x00-\x1f\x7f]');

  bool _validAddress(EmailAddress address) =>
      address.address.runes.length <= 254 &&
      _emailPattern.hasMatch(address.address) &&
      !_controlCharacter.hasMatch(address.address) &&
      !_controlCharacter.hasMatch(address.name ?? '');

  String _addressList(Iterable<EmailAddress> addresses) =>
      addresses.map(_formatAddress).join(', ');

  String _formatAddress(EmailAddress address) {
    final name = address.name;
    if (name == null || name.trim().isEmpty) return address.address;
    final quoted = name.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '"$quoted" <${address.address}>';
  }

  ProviderResponse _messageSizeFailure() => providerFailure(
        'postmark_payload_limit',
        'Postmark accepts at most 10 MB including base64-encoded attachments.',
      );

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    if (isAmbiguousHttp(status)) {
      return providerHttpFailure('postmark', response);
    }
    final body = readProviderJson(response);
    final errorCode = body?['ErrorCode'];
    if (isSuccessfulHttp(status)) {
      final messageId = body?['MessageID'];
      if (errorCode is int &&
          errorCode == 0 &&
          messageId is String &&
          messageId.trim().isNotEmpty) {
        return ProviderResponse.accepted(messageId: messageId);
      }
      if (errorCode is! int || errorCode == 0) {
        return invalidProviderResponse('postmark', response);
      }
    }
    final (code, message) = switch (errorCode) {
      10 => ('auth', 'Postmark rejected the server token.'),
      406 => ('inactive_recipient', 'Postmark rejected an inactive recipient.'),
      411 => ('attachment_type', 'Postmark blocked an attachment file type.'),
      412 || 413 || 1480 => ('forbidden', 'Postmark denied the send.'),
      1235 || 1236 => (
          'message_stream',
          'Postmark rejected the message stream.'
        ),
      _ => switch (status) {
          400 || 422 => ('validation', 'Postmark rejected the email fields.'),
          401 => ('auth', 'Postmark rejected the server token.'),
          403 => ('forbidden', 'Postmark denied the send.'),
          413 => ('payload_limit', 'Postmark rejected the email size.'),
          429 => ('rate_limited', 'Postmark rate limited the request.'),
          _ => ('http_$status', 'Postmark rejected the request.'),
        },
    };
    return providerFailure('postmark_$code', message,
        response: response, retryable: status == 429);
  }
}
