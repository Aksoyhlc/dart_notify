import 'dart:async';
import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final message = NotifyMessage(
      title: 'Alert',
      body: 'Türkçe',
      htmlBody: '<b>Alert</b>',
      priority: NotifyPriority.high,
      data: {'id': 42});
  final target = WebhookTarget(Uri.parse('https://example.com/hooks/alerts'));

  test('default JSON and configured authentication are sent without redirects',
      () async {
    late http.Request request;
    final webhook = WebhookProvider(
        id: 'hook',
        config: WebhookConfig(headers: {'Authorization': 'Bearer secret'}),
        client: MockClient((r) async {
          request = r;
          return http.Response('', 204);
        }));
    final result = await DartNotify(destinations: [])
        .sendDirect(message, provider: webhook, target: target);
    expect(result.isFullyAccepted, isTrue);
    expect(request.method, 'POST');
    expect(request.url, target.endpoint);
    expect(request.followRedirects, isFalse);
    expect(request.headers['authorization'], 'Bearer secret');
    expect(request.headers['content-type'], contains('application/json'));
    expect(jsonDecode(request.body), {
      'title': 'Alert',
      'body': 'Türkçe',
      'htmlBody': '<b>Alert</b>',
      'priority': 'high',
      'data': {'id': 42}
    });
  });

  test(
      'custom builder and per-send options replace payload and override headers',
      () async {
    final requests = <http.Request>[];
    final webhook = WebhookProvider(
        id: 'hook',
        config: WebhookConfig(
          method: WebhookMethod.put,
          headers: {'X-Route': 'default', 'Authorization': 'Bearer default'},
          payloadBuilder: (message) => {'text': message.body},
        ),
        client: MockClient((r) async {
          requests.add(r);
          return http.Response('', 200);
        }));
    final notify = DartNotify(destinations: [
      ProviderDestination(id: 'hook', provider: webhook, target: target)
    ]);
    await notify.send(message, to: [
      'hook'
    ], options: {
      'hook': WebhookOptions(
          method: WebhookMethod.patch,
          headers: {'authorization': 'Bearer override'},
          payload: {'event': 'custom'})
    });
    await notify.send(message, to: ['hook']);
    expect(requests[0].method, 'PATCH');
    expect(requests[0].headers['authorization'], 'Bearer override');
    expect(requests[0].headers['x-route'], 'default');
    expect(jsonDecode(requests[0].body), {'event': 'custom'});
    expect(requests[1].method, 'PUT');
    expect(requests[1].headers['authorization'], 'Bearer default');
    expect(jsonDecode(requests[1].body), {'text': 'Türkçe'});
  });

  test('explicit receiver idempotency enables retries with a stable header',
      () async {
    final keys = <String?>[];
    final delays = <Duration>[];
    final webhook = WebhookProvider(
        id: 'hook',
        config: WebhookConfig(idempotencyHeader: 'Idempotency-Key'),
        client: MockClient((r) async {
          keys.add(r.headers['idempotency-key']);
          return keys.length == 1
              ? http.Response('', 429, headers: {'retry-after': '7'})
              : http.Response('', 202);
        }));
    final notify =
        DartNotify(destinations: [], wait: (d) async => delays.add(d));
    final result = await notify.sendDirect(message,
        provider: webhook,
        target: target,
        options: WebhookOptions(
            headers: {'Idempotency-Key': 'caller-cannot-reuse-this'}));
    expect(result.attempts, 2);
    expect(result.isFullyAccepted, isTrue);
    expect(keys[0], isNotNull);
    expect(keys[0], isNot('caller-cannot-reuse-this'));
    expect(keys[0], keys[1]);
    expect(delays, [const Duration(seconds: 7)]);
    await notify.sendDirect(message, provider: webhook, target: target);
    expect(keys[2], isNot(keys[0]));
  });

  for (final status in [302, 400, 401, 429, 503]) {
    test('HTTP $status is sanitized and not retried by default', () async {
      var calls = 0;
      final webhook = WebhookProvider(
          id: 'hook',
          config: WebhookConfig(),
          client: MockClient((_) async {
            calls++;
            return http.Response('Bearer secret', status,
                headers: {'location': 'https://another.example/hook'});
          }));
      final result = await DartNotify(destinations: [])
          .sendDirect(message, provider: webhook, target: target);
      expect(result.isFullyAccepted, isFalse);
      expect(result.error?.code, 'webhook_http_$status');
      expect(result.error.toString(), isNot(contains('secret')));
      expect(calls, 1);
    });
  }

  test('default timeout is unknown and never automatically resubmitted',
      () async {
    var calls = 0;
    final webhook = WebhookProvider(
        id: 'hook',
        config: WebhookConfig(),
        client: MockClient((_) async {
          calls++;
          throw TimeoutException('secret');
        }));
    final result = await DartNotify(destinations: [])
        .sendDirect(message, provider: webhook, target: target);
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'webhook_timeout');
    expect(calls, 1);
  });

  test('invalid JSON data fails before any request', () async {
    var calls = 0;
    final webhook = WebhookProvider(
        id: 'hook',
        config: WebhookConfig(),
        client: MockClient((_) async {
          calls++;
          return http.Response('', 200);
        }));
    final result = await DartNotify(destinations: []).sendDirect(message,
        provider: webhook,
        target: target,
        options: WebhookOptions(payload: {'invalid': Object()}));
    expect(result.status, DeliveryStatus.failed);
    expect(result.error?.code, 'webhook_invalid_payload');
    expect(calls, 0);
  });

  test('header injection, reserved headers and unsafe endpoints are rejected',
      () {
    expect(() => WebhookConfig(headers: {'X-Token': 'abc\r\nInjected: yes'}),
        throwsArgumentError);
    expect(() => WebhookOptions(headers: {'Content-Length': '3'}),
        throwsArgumentError);
    expect(() => WebhookConfig(headers: {'Bad Header': 'value'}),
        throwsArgumentError);
    expect(() => WebhookConfig(idempotencyHeader: 'Authorization'),
        throwsArgumentError);
    for (final uri in [
      'http://example.com/hook',
      'https://user:pass@example.com/hook',
      'https://example.com/hook#fragment',
      'https:///hook'
    ]) {
      expect(() => WebhookTarget(Uri.parse(uri)), throwsArgumentError);
    }
  });
}
