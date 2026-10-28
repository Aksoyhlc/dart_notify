import 'dart:async';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/http/recording_http_client.dart';

void main() {
  final message = NotifyMessage(body: 'Alert');
  final smsTarget = NetgsmTarget(numbers: ['5321234567']);
  final hookTarget = WebhookTarget(Uri.parse('https://example.com/hook'));

  test('Netgsm and Webhook dispatch together with independent outcomes',
      () async {
    var smsCalls = 0;
    var hookCalls = 0;
    final sms = NetgsmProvider(
        id: 'sms',
        config: NetgsmConfig(username: 'u', password: 'p', sender: 'APP'),
        client: MockClient((_) async {
          smsCalls++;
          return http.Response('{"code":"00","jobid":"sms-job"}', 200);
        }));
    final webhook = WebhookProvider(
        id: 'hook',
        config: WebhookConfig(),
        client: MockClient((_) async {
          hookCalls++;
          return http.Response('secret', 503);
        }));
    final report = await DartNotify(destinations: [
      ProviderDestination(id: 'sms', provider: sms, target: smsTarget),
      ProviderDestination(id: 'hook', provider: webhook, target: hookTarget),
    ], groups: {
      'ops': ['sms', 'hook']
    }).send(message, groups: ['ops']);
    expect(report.results.map((r) => r.destinationId), ['sms', 'hook']);
    expect(report.acceptedCount, 1);
    expect(report.unknownCount, 1);
    expect(report.isPartiallyAccepted, isTrue);
    expect(smsCalls, 1);
    expect(hookCalls, 1);
  });

  test('closing providers leaves injected clients caller-owned and usable',
      () async {
    final smsClient = RecordingHttpClient('{"code":"00","jobid":"job"}');
    final hookClient = RecordingHttpClient('');
    addTearDown(smsClient.close);
    addTearDown(hookClient.close);
    final sms = NetgsmProvider(
        id: 'sms',
        config: NetgsmConfig(username: 'u', password: 'p', sender: 'APP'),
        client: smsClient);
    final webhook = WebhookProvider(
        id: 'hook', config: WebhookConfig(), client: hookClient);
    sms.close();
    webhook.close();
    expect(smsClient.isClosed, isFalse);
    expect(hookClient.isClosed, isFalse);
    final notify = DartNotify(destinations: []);
    expect(
        (await notify.sendDirect(message, provider: sms, target: smsTarget))
            .isFullyAccepted,
        isTrue);
    expect(
        (await notify.sendDirect(message,
                provider: webhook, target: hookTarget))
            .isFullyAccepted,
        isTrue);
  });

  test('configured request timeout bounds a never-completing SMS response',
      () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final sms = NetgsmProvider(
        id: 'sms',
        config: NetgsmConfig(
            username: 'u',
            password: 'p',
            sender: 'APP',
            timeout: const Duration(milliseconds: 10)),
        client: MockClient((_) {
          calls++;
          return pending.future;
        }));
    final result = await DartNotify(destinations: [])
        .sendDirect(message, provider: sms, target: smsTarget);
    pending.complete(http.Response('{"code":"00","jobid":"late"}', 200));
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'netgsm_timeout');
    expect(calls, 1);
  });

  test('Webhook with idempotency recovers from an ambiguous server failure',
      () async {
    final keys = <String?>[];
    final hook = WebhookProvider(
        id: 'hook',
        config: WebhookConfig(idempotencyHeader: 'X-Notification-Key'),
        client: MockClient((r) async {
          keys.add(r.headers['x-notification-key']);
          return http.Response('', keys.length == 1 ? 503 : 200);
        }));
    final result = await DartNotify(destinations: [], wait: (_) async {})
        .sendDirect(message, provider: hook, target: hookTarget);
    expect(result.isFullyAccepted, isTrue);
    expect(result.attempts, 2);
    expect(keys[0], keys[1]);
  });
}
