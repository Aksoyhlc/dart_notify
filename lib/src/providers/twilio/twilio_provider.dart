import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/provider_http.dart';
import 'config/twilio_config.dart';
import 'options/twilio_options.dart';
import 'targets/twilio_target.dart';

/// Twilio Programmable Messaging SMS adapter. Call close() when finished.
final class TwilioProvider
    extends NotificationProvider<TwilioTarget, TwilioOptions> {
  TwilioProvider({
    required this.id,
    required this.config,
    http.Client? client,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final TwilioConfig config;
  final http.Client _client;
  final bool _ownsClient;

  @override
  bool get supportsSafeRetry => false;

  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required TwilioTarget target,
    required DeliveryContext context,
    TwilioOptions? options,
  }) async {
    if (message.attachments.isNotEmpty) {
      return providerFailure(
          'attachment_unsupported', 'Twilio SMS does not support attachments.');
    }
    if (message.body.trim().isEmpty) {
      return providerFailure(
          'twilio_body_required', 'Twilio requires SMS text.');
    }
    if (message.body.runes.length > 1600) {
      return providerFailure('twilio_body_limit',
          'Twilio SMS text must not exceed 1600 characters.');
    }
    final endpoint = Uri.https('api.twilio.com',
        '/2010-04-01/Accounts/${config.accountSid}/Messages.json');
    final username = config.apiKeySid ?? config.accountSid;
    final credentials = base64Encode(utf8.encode('$username:${config.secret}'));
    final request = http.Request('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll({
        'accept': 'application/json',
        'authorization': 'Basic $credentials',
      })
      ..bodyFields = {
        'To': target.number,
        'Body': message.body,
        if (config.from case final from?) 'From': from,
        if (config.messagingServiceSid case final sid?)
          'MessagingServiceSid': sid,
        if (options?.statusCallback case final callback?)
          'StatusCallback': callback.toString(),
      };
    final response = await sendProviderRequest(
      'twilio',
      () => _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(config.timeout),
    );
    return _readResponse(response);
  }

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    if (isAmbiguousHttp(status)) return providerHttpFailure('twilio', response);
    final body = readProviderJson(response);
    if (isSuccessfulHttp(status)) {
      final sid = body?['sid'];
      if (sid is! String || sid.trim().isEmpty) {
        return invalidProviderResponse('twilio', response);
      }
      return switch (body?['status']) {
        'accepted' ||
        'queued' ||
        'sending' ||
        'sent' ||
        'delivered' =>
          ProviderResponse.accepted(messageId: sid),
        'failed' || 'undelivered' || 'canceled' => providerFailure(
            'twilio_message_failed',
            'Twilio reported a failed outbound message.',
            response: response,
            messageId: sid),
        _ => invalidProviderResponse('twilio', response),
      };
    }
    final (code, message) = switch (body?['code']) {
      20003 => ('auth', 'Twilio rejected the credentials or account access.'),
      20429 => ('rate_limited', 'Twilio rate limited the request.'),
      21603 || 21606 || 21657 => (
          'invalid_sender',
          'Twilio rejected the SMS sender.'
        ),
      21211 || 21614 => (
          'invalid_recipient',
          'Twilio rejected the SMS recipient.'
        ),
      21610 => (
          'recipient_opted_out',
          'Twilio declined to send to an opted-out recipient.'
        ),
      21617 => ('body_limit', 'Twilio rejected the SMS text length.'),
      _ => switch (status) {
          400 => ('validation', 'Twilio rejected the SMS fields.'),
          401 => ('auth', 'Twilio rejected the credentials.'),
          403 => ('forbidden', 'Twilio denied the send.'),
          429 => ('rate_limited', 'Twilio rate limited the request.'),
          _ => ('http_$status', 'Twilio rejected the request.'),
        },
    };
    return providerFailure('twilio_$code', message,
        response: response, retryable: status == 429 || body?['code'] == 20429);
  }
}
