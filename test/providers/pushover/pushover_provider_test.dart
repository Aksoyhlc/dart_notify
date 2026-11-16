import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../support/http/provider_http_fixture.dart';

void main() {
  final appToken = 'a' * 30;
  final userKey = 'u' * 30;
  late ProviderHttpFixture fixture;
  late PushoverProvider provider;

  setUp(() {
    fixture = ProviderHttpFixture('{"status":1,"request":"request-1"}');
    provider = PushoverProvider(
      id: 'pushover',
      config: PushoverConfig(appToken: appToken),
      client: fixture.client,
    );
    addTearDown(fixture.client.close);
    addTearDown(provider.close);
  });

  Future<DeliveryResult> send(
    NotifyMessage message, {
    PushoverOptions? options,
  }) =>
      DartNotify(destinations: []).sendDirect(
        message,
        provider: provider,
        target: PushoverTarget(userKey: userKey, devices: ['phone', 'tablet']),
        options: options,
      );

  test('publishes HTML and a single image with device targeting', () async {
    final png = MockClient.pngResponse().bodyBytes;
    final result = await send(
      NotifyMessage(
        body: '',
        htmlBody: '<b>Yedek hazır</b>',
        title: 'Sistem',
        priority: NotifyPriority.high,
        attachments: [
          NotifyAttachment(
              fileName: 'chart.png', bytes: png, contentType: 'image/png'),
        ],
      ),
      options: PushoverOptions(
        html: true,
        ttl: const Duration(minutes: 5),
        url: Uri.parse('https://example.com/backup'),
        urlTitle: 'Backup log',
      ),
    );

    expect(result.status, DeliveryStatus.accepted);
    expect(result.messageId, 'request-1');
    final request = fixture.requests.single;
    expect(request.method, 'POST');
    expect(request.url.toString(), 'https://api.pushover.net/1/messages.json');
    expect(request.followRedirects, isFalse);
    final payload = jsonDecode(request.body) as Map;
    expect(payload.remove('attachment_base64'), base64Encode(png));
    expect(payload, {
      'token': appToken,
      'user': userKey,
      'message': '<b>Yedek hazır</b>',
      'device': 'phone,tablet',
      'title': 'Sistem',
      'priority': 1,
      'html': 1,
      'ttl': 300,
      'url': 'https://example.com/backup',
      'url_title': 'Backup log',
      'attachment_type': 'image/png',
    });
  });

  test('sends emergency timings and returns the acknowledgement receipt',
      () async {
    fixture.respond = (_) => http.Response(
        '{"status":1,"request":"request-1","receipt":"receipt-1"}', 200);
    final callback = Uri.parse('https://example.com/pushover/ack');
    final result = await send(
      NotifyMessage(body: 'Database offline'),
      options: PushoverOptions(
        priority: PushoverPriority.emergency,
        retryEvery: const Duration(seconds: 30),
        expireAfter: const Duration(hours: 3),
        acknowledgementCallback: callback,
      ),
    );

    expect(result.status, DeliveryStatus.accepted);
    expect(result.messageId, 'receipt-1');
    final payload = jsonDecode(fixture.requests.single.body) as Map;
    expect(payload['priority'], 2);
    expect(payload['retry'], 30);
    expect(payload['expire'], 10800);
    expect(payload['callback'], callback.toString());
    expect(payload, isNot(contains('ttl')));
  });

  test('rejects invalid or misplaced emergency options', () {
    const emergency = PushoverPriority.emergency;
    expect(() => PushoverOptions(priority: emergency), throwsArgumentError);
    expect(
      () => PushoverOptions(
        priority: emergency,
        retryEvery: const Duration(seconds: 29),
        expireAfter: const Duration(minutes: 10),
      ),
      throwsArgumentError,
    );
    expect(
      () => PushoverOptions(
        priority: emergency,
        retryEvery: const Duration(minutes: 1),
        expireAfter: const Duration(hours: 3, seconds: 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => PushoverOptions(retryEvery: const Duration(minutes: 1)),
      throwsArgumentError,
    );
  });

  test('measures Pushover text limits in characters, including emoji',
      () async {
    final accepted = await send(NotifyMessage(body: '🔔' * 1024));
    final tooLong = await send(NotifyMessage(body: '🔔' * 1025));

    expect(accepted.status, DeliveryStatus.accepted);
    expect(tooLong.error?.code, 'pushover_message_limit');
    expect(fixture.requests, hasLength(1));
  });

  test('rejects non-image, multiple and oversized attachments locally',
      () async {
    final icon = NotifyAttachment(
      fileName: 'icon.png',
      bytes: MockClient.pngResponse().bodyBytes,
      contentType: 'image/png',
    );
    final wrongType = await send(NotifyMessage(body: 'Alert', attachments: [
      NotifyAttachment(fileName: 'log.txt', bytes: Uint8List(1)),
    ]));
    final multiple =
        await send(NotifyMessage(body: 'Alert', attachments: [icon, icon]));
    final oversized = await send(NotifyMessage(body: 'Alert', attachments: [
      NotifyAttachment(
        fileName: 'large.png',
        bytes: Uint8List(5242881),
        contentType: 'image/png',
      ),
    ]));

    expect(wrongType.error?.code, 'pushover_attachment_type');
    expect(multiple.error?.code, 'pushover_attachment_count');
    expect(oversized.error?.code, 'pushover_attachment_size');
    expect(fixture.requests, isEmpty);
  });

  test('HTTP 429 is quota exhaustion and status 0 is a rejection', () async {
    fixture.respond = (_) => http.Response('{"status":0}', 429);
    final quota = await send(NotifyMessage(body: 'Alert'));
    fixture.respond = (_) => http.Response(
        '{"status":0,"errors":["User $userKey is invalid"]}', 200);
    final rejected = await send(NotifyMessage(body: 'Alert'));

    expect(quota.status, DeliveryStatus.failed);
    expect(quota.error?.code, 'pushover_quota_exceeded');
    expect(quota.error?.retryable, isFalse);
    expect(rejected.status, DeliveryStatus.failed);
    expect(rejected.error?.code, 'pushover_validation');
    expect(rejected.error?.message, isNot(contains(userKey)));
    expect(fixture.requests, hasLength(2));
  });
}
