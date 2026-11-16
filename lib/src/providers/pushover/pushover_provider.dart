import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/delivery/delivery_context.dart';
import '../../core/enums/notify_priority.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/transport/provider_http.dart';
import 'config/pushover_config.dart';
import 'enums/pushover_priority.dart';
import 'options/pushover_options.dart';
import 'targets/pushover_target.dart';

/// Pushover Message API adapter. Call close() when finished.
final class PushoverProvider
    extends NotificationProvider<PushoverTarget, PushoverOptions> {
  PushoverProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final PushoverConfig config;
  final JsonHttpTransport _transport;

  static final _endpoint = Uri.https('api.pushover.net', '/1/messages.json');
  static const _maxAttachmentBytes = 5 * 1024 * 1024;

  @override
  bool get supportsSafeRetry => false;

  @override
  bool get supportsAttachments => true;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required PushoverTarget target,
    required DeliveryContext context,
    PushoverOptions? options,
  }) async {
    final html = options?.html ?? false;
    final text = html && (message.htmlBody?.trim().isNotEmpty ?? false)
        ? message.htmlBody!
        : message.body;
    if (text.trim().isEmpty) {
      return providerFailure(
          'pushover_body_required', 'Pushover requires a message body.');
    }
    if (text.runes.length > 1024 || (message.title?.runes.length ?? 0) > 250) {
      return providerFailure('pushover_message_limit',
          'Pushover accepts up to 1024 message and 250 title characters.');
    }
    if (message.attachments.length > 1) {
      return providerFailure('pushover_attachment_count',
          'Pushover accepts at most one image attachment.');
    }
    final file = message.attachments.firstOrNull;
    String? mimeType;
    if (file != null) {
      mimeType = _imageMimeType(file.contentType);
      if (mimeType == null) {
        return providerFailure('pushover_attachment_type',
            'Pushover only accepts image attachments.');
      }
      if (file.bytes.isEmpty || file.bytes.length > _maxAttachmentBytes) {
        return providerFailure('pushover_attachment_size',
            'Pushover requires a non-empty image up to 5242880 bytes.');
      }
    }
    final priority = options?.priority ??
        switch (message.priority) {
          NotifyPriority.low => PushoverPriority.low,
          NotifyPriority.normal => PushoverPriority.normal,
          NotifyPriority.high => PushoverPriority.high,
        };
    final payload = <String, Object?>{
      'token': config.appToken,
      'user': target.userKey,
      'message': text,
      'priority': priority.value,
      if (target.devices.isNotEmpty) 'device': target.devices.join(','),
      if (message.title case final title?) 'title': title,
      if (html) 'html': 1,
      if (options?.sound case final sound?) 'sound': sound,
      if (options?.url case final url?) 'url': url.toString(),
      if (options?.urlTitle case final title?) 'url_title': title,
      if (options?.ttl case final ttl?) 'ttl': ttl.inSeconds,
      if (options?.retryEvery case final retry?) 'retry': retry.inSeconds,
      if (options?.expireAfter case final expire?) 'expire': expire.inSeconds,
      if (options?.acknowledgementCallback case final callback?)
        'callback': callback.toString(),
      if (file != null) ...{
        'attachment_base64': base64Encode(file.bytes),
        'attachment_type': mimeType,
      },
    };
    final response = await sendProviderRequest(
      'pushover',
      () => _transport.send(
          endpoint: _endpoint, payload: payload, timeout: config.timeout),
    );
    return _readResponse(response,
        emergency: priority == PushoverPriority.emergency);
  }

  String? _imageMimeType(String value) {
    try {
      final type = MediaType.parse(value);
      return type.type == 'image' && type.subtype != '*' ? type.mimeType : null;
    } on FormatException {
      return null;
    }
  }

  ProviderResponse _readResponse(
    http.Response response, {
    required bool emergency,
  }) {
    final status = response.statusCode;
    if (isAmbiguousHttp(status)) {
      return providerHttpFailure('pushover', response);
    }
    if (status == 429) {
      return providerFailure(
        'pushover_quota_exceeded',
        'Pushover rejected the send because the account quota is exhausted.',
        response: response,
      );
    }
    final body = readProviderJson(response);
    final outcome = body?['status'];
    if (isSuccessfulHttp(status)) {
      if (outcome is int && outcome == 1) {
        final id = body?[emergency ? 'receipt' : 'request'];
        return ProviderResponse.accepted(
            messageId: id is String && id.trim().isNotEmpty ? id : null);
      }
      if (outcome is! int) return invalidProviderResponse('pushover', response);
    }
    if (status == 400 || (outcome is int && outcome != 1)) {
      return providerFailure(
        'pushover_validation',
        'Pushover rejected the credentials, target or message fields.',
        response: response,
      );
    }
    return providerHttpFailure('pushover', response);
  }
}
