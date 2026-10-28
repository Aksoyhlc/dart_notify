import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../support/core/fake_provider.dart';
import '../../support/core/fake_target.dart';
import '../../support/core/utils/destination.dart';
import '../../support/smtp/fake_smtp_transport.dart';

void main() {
  final message = NotifyMessage(body: 'Report');

  test('widened option mismatches are rejected when destinations are built',
      () {
    expect(
      () => ProviderDestination<NotificationTarget, NotificationOptions>(
        id: 'wrong-options',
        provider: FakeProvider(id: 'plain'),
        target: const FakeTarget('user'),
        options: OneSignalOptions(),
      ),
      throwsArgumentError,
    );
  });

  test('direct sends reject widened targets and options before delivery',
      () async {
    final provider = FakeProvider(id: 'plain');
    final notify = DartNotify(destinations: []);
    await expectLater(
      notify.sendDirect<NotificationTarget, NotificationOptions>(
        message,
        provider: provider,
        target: EmailTarget(to: [EmailAddress('ops@example.com')]),
      ),
      throwsArgumentError,
    );
    await expectLater(
      notify.sendDirect<NotificationTarget, NotificationOptions>(
        message,
        provider: provider,
        target: const FakeTarget('user'),
        options: EmailOptions(),
      ),
      throwsArgumentError,
    );
    expect(provider.calls, isEmpty);
  });

  test('all batch options are validated before any selected provider runs',
      () async {
    final provider = FakeProvider(id: 'plain');
    final notify =
        DartNotify(destinations: [dest('a', provider), dest('b', provider)]);
    await expectLater(
      notify.send(message, to: ['a', 'b'], options: {'b': EmailOptions()}),
      throwsArgumentError,
    );
    await expectLater(
      notify.send(message,
          to: ['a'], options: {'b': const NoNotificationOptions()}),
      throwsArgumentError,
    );
    await expectLater(
      notify.send(message, to: ['a'], options: {'missing': EmailOptions()}),
      throwsArgumentError,
    );
    expect(provider.calls, isEmpty);
  });

  test('OneSignal overrides replace defaults without mutating the target',
      () async {
    final payloads = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      payloads.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"id":"ok"}', 200);
    });
    addTearDown(client.close);
    final provider = OneSignalProvider(
      id: 'push',
      config: OneSignalConfig(appId: 'app', apiKey: 'key'),
      client: client,
    );
    final notify = DartNotify(destinations: [
      ProviderDestination(
        id: 'alerts',
        provider: provider,
        target: OneSignalTarget.externalIds(['user']),
        options: OneSignalOptions(
            collapseId: 'default', ttl: const Duration(hours: 1)),
      ),
    ], groups: {
      'team': ['alerts']
    });
    await notify.send(message, groups: [
      'team'
    ], options: {
      'alerts': OneSignalOptions(
        language: 'tr',
        localizedBodies: {'tr': 'Rapor'},
        collapseId: 'override',
      ),
    });
    await notify.send(message, to: ['alerts']);
    expect(payloads[0]['collapse_id'], 'override');
    expect(payloads[0].containsKey('ttl'), isFalse);
    expect(payloads[0]['contents'], {'en': 'Report', 'tr': 'Rapor'});
    expect(payloads[1]['collapse_id'], 'default');
    expect(payloads[1]['ttl'], 3600);
    expect(payloads[1]['include_aliases'], {
      'external_id': ['user']
    });
  });

  test('SMTP message attachments and reply-to defaults apply per send',
      () async {
    final transport = FakeSmtpTransport();
    final provider = SmtpProvider(
      id: 'mail',
      config: SmtpConfig(
          host: 'smtp.example.com', from: EmailAddress('from@example.com')),
      transport: transport,
    );
    final notify = DartNotify(destinations: [
      ProviderDestination(
        id: 'ops',
        provider: provider,
        target: EmailTarget(to: [EmailAddress('ops@example.com')]),
        options: EmailOptions(replyTo: [EmailAddress('default@example.com')]),
      ),
    ]);
    await notify.send(
        NotifyMessage(
          body: 'Report',
          attachments: [
            NotifyAttachment(
                fileName: 'report.txt', bytes: Uint8List.fromList([65, 66])),
          ],
        ),
        to: ['ops'],
        options: {'ops': EmailOptions()});
    expect(transport.seenMessage.attachments.single.bytes, [65, 66]);
    expect(transport.seenOptions!.replyTo, isEmpty);
    await notify.send(message, to: ['ops']);
    expect(transport.seenMessage.attachments, isEmpty);
    expect(
        transport.seenOptions!.replyTo.single.address, 'default@example.com');
  });

  test('attachment bytes cannot be changed between concurrent deliveries', () {
    final input = Uint8List.fromList([65]);
    final attachment = NotifyAttachment(fileName: 'a.txt', bytes: input);
    input[0] = 66;
    expect(attachment.bytes, [65]);
    expect(() => attachment.bytes[0] = 67, throwsUnsupportedError);
  });
}
