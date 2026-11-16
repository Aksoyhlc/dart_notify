import 'dart:async';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/http/provider_http_fixture.dart';

void main() {
  test('all four providers retain independent outcomes without resending',
      () async {
    final pending = Completer<http.Response>();
    addTearDown(() => pending.complete(http.Response('', 503)));
    final mailHttp =
        ProviderHttpFixture('{"message":"internal secret"}', status: 503);
    final smsHttp = ProviderHttpFixture('')..respond = (_) => pending.future;
    final pushHttp = ProviderHttpFixture('')
      ..respond = (_) => throw http.ClientException('private address');
    final chatHttp = ProviderHttpFixture('{"messages":[{}]}');
    for (final fixture in [mailHttp, smsHttp, pushHttp, chatHttp]) {
      addTearDown(fixture.client.close);
    }

    final mail = PostmarkProvider(
      id: 'postmark',
      config: PostmarkConfig(
        serverToken: 'server-token',
        from: EmailAddress('orders@example.com'),
      ),
      client: mailHttp.client,
    );
    final sms = TwilioProvider(
      id: 'twilio',
      config: TwilioConfig.withAuthToken(
        accountSid: 'AC${'0' * 32}',
        authToken: 'example-token',
        from: '+14155550123',
        timeout: const Duration(milliseconds: 50),
      ),
      client: smsHttp.client,
    );
    final push = PushoverProvider(
      id: 'pushover',
      config: PushoverConfig(appToken: 'a' * 30),
      client: pushHttp.client,
    );
    final chat = WhatsAppProvider(
      id: 'whatsapp',
      config: WhatsAppConfig(
        phoneNumberId: '106540352242922',
        accessToken: 'example-token',
        graphApiVersion: 'v25.0',
      ),
      client: chatHttp.client,
    );
    addTearDown(mail.close);
    addTearDown(sms.close);
    addTearDown(push.close);
    addTearDown(chat.close);

    final notify = DartNotify(
      destinations: [
        ProviderDestination(
          id: 'mail',
          provider: mail,
          target: EmailTarget(to: [EmailAddress('buyer@example.com')]),
        ),
        ProviderDestination(
          id: 'sms',
          provider: sms,
          target: TwilioTarget(number: '+14155550124'),
        ),
        ProviderDestination(
          id: 'push',
          provider: push,
          target: PushoverTarget(userKey: 'u' * 30),
        ),
        ProviderDestination(
          id: 'chat',
          provider: chat,
          target: WhatsAppTarget(number: '+14155550124'),
        ),
      ],
      groups: const {
        'order': ['mail', 'sms', 'push', 'chat'],
      },
      maxConcurrent: 4,
      retryPolicy: RetryPolicy(maxAttempts: 3),
      wait: (_) async => fail('These providers must never retry automatically'),
    );

    final report = await notify
        .send(NotifyMessage(body: 'Order ready'), groups: ['order']);

    expect(report.unknownCount, 4);
    expect(report.results.map((result) => result.destinationId),
        ['mail', 'sms', 'push', 'chat']);
    expect(report.results.map((result) => result.error?.code), [
      'postmark_http_503',
      'twilio_timeout',
      'pushover_network_error',
      'whatsapp_invalid_response',
    ]);
    expect(report.results.map((result) => result.attempts), [1, 1, 1, 1]);
    expect(
        report.results[0].error?.message, isNot(contains('internal secret')));
    expect(
        report.results[2].error?.message, isNot(contains('private address')));
    for (final fixture in [mailHttp, smsHttp, pushHttp, chatHttp]) {
      expect(fixture.requests, hasLength(1));
    }
  });
}
