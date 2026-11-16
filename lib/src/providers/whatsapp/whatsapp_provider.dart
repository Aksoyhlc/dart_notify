import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/transport/provider_http.dart';
import 'config/whatsapp_config.dart';
import 'options/whatsapp_options.dart';
import 'options/whatsapp_template_parameter.dart';
import 'targets/whatsapp_target.dart';

/// Meta WhatsApp Cloud API adapter. Call close() when finished.
final class WhatsAppProvider
    extends NotificationProvider<WhatsAppTarget, WhatsAppOptions> {
  WhatsAppProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final WhatsAppConfig config;
  final JsonHttpTransport _transport;

  @override
  bool get supportsSafeRetry => false;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required WhatsAppTarget target,
    required DeliveryContext context,
    WhatsAppOptions? options,
  }) async {
    if (message.attachments.isNotEmpty) {
      return providerFailure('attachment_unsupported',
          'WhatsApp text and templates do not support file uploads.');
    }
    final settings = options ?? const WhatsAppOptions.text();
    final template = settings.templateName;
    if (template == null) {
      if (message.body.trim().isEmpty) {
        return providerFailure(
            'whatsapp_body_required', 'WhatsApp requires a text body.');
      }
      if (message.body.runes.length > 4096) {
        return providerFailure('whatsapp_body_limit',
            'WhatsApp text must not exceed 4096 characters.');
      }
    }
    final payload = <String, Object?>{
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': target.number,
      if (config.messagingAccountId case final accountId?)
        'messaging_account_id': accountId,
      if (template == null) ...{
        'type': 'text',
        'text': {
          'body': message.body,
          if (settings.previewUrl) 'preview_url': true,
        },
      } else ...{
        'type': 'template',
        'template': {
          'name': template,
          'language': {'code': settings.languageCode!},
          if (settings.headerParameters.isNotEmpty ||
              settings.bodyParameters.isNotEmpty)
            'components': [
              if (settings.headerParameters.isNotEmpty)
                _component('header', settings.headerParameters),
              if (settings.bodyParameters.isNotEmpty)
                _component('body', settings.bodyParameters),
            ],
        },
      },
    };
    final endpoint = Uri.https('graph.facebook.com',
        '/${config.graphApiVersion}/${config.phoneNumberId}/messages');
    final response = await sendProviderRequest(
      'whatsapp',
      () => _transport.send(
        endpoint: endpoint,
        payload: payload,
        timeout: config.timeout,
        headers: {'authorization': 'Bearer ${config.accessToken}'},
      ),
    );
    return _readResponse(response);
  }

  Map<String, Object?> _component(
    String type,
    Iterable<WhatsAppTemplateParameter> parameters,
  ) =>
      {
        'type': type,
        'parameters': [
          for (final parameter in parameters)
            {
              'type': 'text',
              if (parameter.name case final name?) 'parameter_name': name,
              'text': parameter.text,
            },
        ],
      };

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    if (isAmbiguousHttp(status)) {
      return providerHttpFailure('whatsapp', response);
    }
    final body = readProviderJson(response);
    final error = body?['error'];
    final upstreamCode = error is Map<String, dynamic> ? error['code'] : null;
    if (isSuccessfulHttp(status) && upstreamCode is! int) {
      final messages = body?['messages'];
      if (error == null && messages is List && messages.length == 1) {
        final entry = messages.first;
        final messageId = entry is Map<String, dynamic> ? entry['id'] : null;
        if (messageId is String && messageId.trim().isNotEmpty) {
          return ProviderResponse.accepted(messageId: messageId);
        }
      }
      return invalidProviderResponse('whatsapp', response);
    }
    final (code, message) = switch (upstreamCode) {
      0 || 190 => ('auth', 'Meta rejected the WhatsApp access token.'),
      3 || 10 || 200 || 131005 => (
          'forbidden',
          'Meta denied WhatsApp messaging access.'
        ),
      4 || 130429 || 131056 => (
          'rate_limited',
          'Meta rate limited the WhatsApp send.'
        ),
      131026 => (
          'undeliverable',
          'Meta reported that the WhatsApp message is undeliverable.'
        ),
      131047 => (
          'template_required',
          'The customer service window has closed. Use an approved template.'
        ),
      131048 => (
          'spam_rate_limit',
          'Meta restricted sending because of message quality or volume.'
        ),
      132000 || 132012 => (
          'template_parameters',
          'Meta rejected the WhatsApp template parameters.'
        ),
      132001 => (
          'template_not_found',
          'Meta did not find the approved WhatsApp template for this language.'
        ),
      132015 || 132016 => (
          'template_unavailable',
          'Meta paused or disabled the WhatsApp template.'
        ),
      _ => switch (status) {
          400 || 422 => (
              'validation',
              'Meta rejected the WhatsApp message fields.'
            ),
          401 => ('auth', 'Meta rejected the WhatsApp access token.'),
          403 => ('forbidden', 'Meta denied WhatsApp messaging access.'),
          429 => ('rate_limited', 'Meta rate limited the WhatsApp send.'),
          _ => ('http_$status', 'Meta rejected the WhatsApp send.'),
        },
    };
    return providerFailure('whatsapp_$code', message,
        response: response, retryable: code == 'rate_limited');
  }
}
