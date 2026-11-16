import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../../support/http/provider_http_fixture.dart';

void main() {
  final accountSid = 'AC${'0' * 32}';
  final keySid = 'SK${'1' * 32}';
  final serviceSid = 'MG${'2' * 32}';
  final messageSid = 'SM${'3' * 32}';
  final target = TwilioTarget(number: '+14155550123');
  late ProviderHttpFixture fixture;

  setUp(() {
    fixture = ProviderHttpFixture('{"sid":"$messageSid","status":"accepted"}',
        status: 201);
    addTearDown(fixture.client.close);
  });

  Future<DeliveryResult> send(
    NotifyMessage message, {
    TwilioConfig? config,
    TwilioOptions? options,
  }) async {
    final provider = TwilioProvider(
      id: 'twilio',
      config: config ??
          TwilioConfig(
            accountSid: accountSid,
            apiKeySid: keySid,
            apiKeySecret: 'key-secret',
            messagingServiceSid: serviceSid,
          ),
      client: fixture.client,
    );
    addTearDown(provider.close);
    return DartNotify(destinations: []).sendDirect(
      message,
      provider: provider,
      target: target,
      options: options,
    );
  }

  test('submits Unicode SMS as a form using API key Basic auth', () async {
    const body = 'Sipariş hazır + 1 & 2';
    final callback = Uri.parse('https://example.com/status?source=sms');

    final result = await send(
      NotifyMessage(body: body),
      options: TwilioOptions(statusCallback: callback),
    );

    expect(result.status, DeliveryStatus.accepted);
    expect(result.messageId, messageSid);
    final request = fixture.requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(),
        'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json');
    expect(request.followRedirects, isFalse);
    expect(request.headers['content-type'],
        startsWith('application/x-www-form-urlencoded'));
    final auth = request.headers['authorization']!;
    expect(auth, startsWith('Basic '));
    expect(utf8.decode(base64Decode(auth.substring('Basic '.length))),
        '$keySid:key-secret');
    expect(request.bodyFields, {
      'To': '+14155550123',
      'MessagingServiceSid': serviceSid,
      'Body': body,
      'StatusCallback': callback.toString(),
    });
  });

  test('account auth token works with a From sender and queued result',
      () async {
    fixture.respond =
        (_) => http.Response('{"sid":"$messageSid","status":"queued"}', 201);

    final result = await send(
      NotifyMessage(body: 'Ready'),
      config: TwilioConfig.withAuthToken(
        accountSid: accountSid,
        authToken: 'account-auth-token',
        from: '+14155550124',
      ),
    );

    expect(result.status, DeliveryStatus.accepted);
    final request = fixture.requests.single;
    expect(request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('$accountSid:account-auth-token'))}');
    expect(request.bodyFields['From'], '+14155550124');
    expect(request.bodyFields, isNot(contains('MessagingServiceSid')));
  });

  test('rejects invalid targets, missing senders and insecure callbacks', () {
    expect(() => TwilioTarget(number: '0532 123 45 67'), throwsArgumentError);
    expect(
      () => TwilioConfig.withAuthToken(accountSid: accountSid, authToken: 'tk'),
      throwsArgumentError,
    );
    expect(
      () =>
          TwilioOptions(statusCallback: Uri.parse('http://example.com/status')),
      throwsArgumentError,
    );
  });

  test('invalid SMS content never reaches Twilio', () async {
    final noText =
        await send(NotifyMessage(body: '', htmlBody: '<b>Ready</b>'));
    final tooLong = await send(NotifyMessage(body: 'x' * 1601));
    final attachment = await send(NotifyMessage(body: 'Ready', attachments: [
      NotifyAttachment(fileName: 'report.pdf', bytes: Uint8List(1)),
    ]));

    expect(noText.error?.code, 'twilio_body_required');
    expect(tooLong.error?.code, 'twilio_body_limit');
    expect(attachment.error?.code, 'attachment_unsupported');
    expect(fixture.requests, isEmpty);
  });

  test('a message resource with failed status is not accepted', () async {
    fixture.respond = (_) => http.Response(
        '{"sid":"$messageSid","status":"failed","error_message":"private"}',
        201);

    final result = await send(NotifyMessage(body: 'Ready'));

    expect(result.status, DeliveryStatus.failed);
    expect(result.messageId, messageSid);
    expect(result.error?.code, 'twilio_message_failed');
    expect(result.error?.message, isNot(contains('private')));
  });

  test('recipient opt-out is a sanitized, terminal rejection', () async {
    fixture.respond = (_) =>
        http.Response('{"code":21610,"message":"+14155550123 opted out"}', 400);

    final result = await send(NotifyMessage(body: 'Ready'));

    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'twilio_recipient_opted_out');
    expect(result.error?.retryable, isFalse);
    expect(result.error?.message, isNot(contains(target.number)));
  });
}
